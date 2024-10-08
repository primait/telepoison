defmodule Telepoison do
  @moduledoc """
  OpenTelemetry-instrumented wrapper around HTTPoison.Base

  A client request span is created on request creation, and ended once we get the response.
  http.status and other standard http span attributes are set automatically.
  """

  use HTTPoison.Base

  require OpenTelemetry
  require OpenTelemetry.SemConv.HTTPAttributes, as: HTTPAttributes
  require OpenTelemetry.SemConv.URLAttributes, as: URLAttributes
  require OpenTelemetry.SemConv.Incubating.URLAttributes, as: IncubatingURLAttributes
  require OpenTelemetry.SemConv.ServerAttributes, as: ServerAttributes
  require OpenTelemetry.Span
  require OpenTelemetry.Tracer
  require Record
  require Logger

  alias HTTPoison.Request
  alias OpenTelemetry.Tracer
  alias Telepoison.Configuration

  @http_request_method Atom.to_string(HTTPAttributes.http_request_method())
  @http_response_status_code Atom.to_string(HTTPAttributes.http_response_status_code())
  @http_route Atom.to_string(HTTPAttributes.http_route())

  @server_address Atom.to_string(ServerAttributes.server_address())
  @server_port Atom.to_string(ServerAttributes.server_port())

  @url_full Atom.to_string(URLAttributes.url_full())
  @url_scheme Atom.to_string(URLAttributes.url_scheme())
  @url_template Atom.to_string(IncubatingURLAttributes.url_template())

  @doc ~S"""
  Configures Telepoison using the provided `opts` `Keyword list`.

  You should call this function within your application startup, before Telepoison is used.
  Using the `:ot_attributes` option, you can set default Open Telemetry metadata attributes
  to be added to each Telepoison request in the format of a list of two element tuples, with both elements
  being strings.

  Attributes can be overridden per each call to `Telepoison.request/1`.

  Using the `:infer_route` option, you can customise the URL resource route inference procedure
  that is used to set the `http.route` Open Telemetry metadata attribute.

  If a function with an arity of 1 (the `t:HTTPoison.Request/0` `request`) is provided
  then that function is used to determine the inference.

  If no value is provided then the out of the box, conservative inference provided by
  `Telepoison.URI.infer_route_from_request/1` is used to determine the inference.

  This can be overridden per each call to `Telepoison.request/1`.

  ## Examples
  iex> Telepoison.setup()
  :ok
  iex> infer_fn = fn
  ...>  %HTTPoison.Request{} = request -> URI.parse(request.url).path
  ...> end
  iex> Telepoison.setup(infer_route: infer_fn)
  :ok
  iex> Telepoison.setup(ot_attributes: [{"service.name", "..."}, {"service.namespace", "..."}])
  :ok
  iex> infer_fn = fn
  ...>  %HTTPoison.Request{} = request -> URI.parse(request.url).path
  ...> end
  iex> ot_attributes = [{"service.name", "..."}, {"service.namespace", "..."}]
  iex> Telepoison.setup(infer_route: infer_fn, ot_attributes: ot_attributes)
  :ok
  """
  @deprecated "setup/1 is deprecated, use `config :telepoison, ...` instead"
  def setup(opts \\ []) do
    Configuration.setup(opts)
    :ok
  end

  def process_request_headers(headers) when is_map(headers) do
    headers
    |> Enum.into([])
    |> process_request_headers()
  end

  def process_request_headers(headers) when is_list(headers) do
    headers
    # Convert atom header keys.
    # otel_propagator_text_map only accepts string keys, while Request.headers() keys can be atoms or strings.
    # The value in Request.headers() has to be a binary() so we don't need to convert it
    #
    # Note that this causes the header keys from HTTPoison.Response{request: %{headers: headers}} to also become strings
    # while with plain HTTPoison they would remain atoms.
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> :otel_propagator_text_map.inject()
  end

  @doc ~S"""
  Performs a request using Telepoison with the provided `t:HTTPoison.Request/0` `request`.

  Depending how `Telepoison` is configured and whether or not the `:ot_resource_route`
  option is set to `:infer` (provided as a part of the `t:HTTPoison.Request/0` `options` `Keyword list`)
  this may attempt to automatically set the `http.route` Open Telemetry metadata attribute by obtaining
  the first segment of the `t:HTTPoison.Request/0` `url` (since this part typically does not contain dynamic data)

  If this behavior is not desirable, it can be set directly as a string or a function
  with an arity of 1 (the `t:HTTPoison.Request/0` `request`) by using the aforementioned `:ot_resource_route` option.

  It can also be circumvented entirely by suppling `:ignore`  instead.

    ## Examples

      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}]}
      iex> Telepoison.request(request)

      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: :infer]}
      iex> Telepoison.request(request)

      iex> resource_route = "/users/edit/"
      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: resource_route]}
      iex> Telepoison.request(request)

      iex> infer_fn = fn
      ...>  %HTTPoison.Request{} = request -> URI.parse(request.url).path
      ...> end
      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: infer_fn]}
      iex> Telepoison.request(request)

      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: :ignore]}
      iex> Telepoison.request(request)

  """
  def request(%Request{options: opts} = request) do
    save_parent_ctx()

    span_name = Keyword.get_lazy(opts, :ot_span_name, fn -> default_span_name(request) end)

    %URI{scheme: scheme, host: host, port: port} = request.url |> process_request_url() |> URI.parse()

    resource_route_attribute =
      opts
      |> Keyword.get(:ot_resource_route, :unset)
      |> get_resource_route(request)
      |> case do
        resource_route when is_binary(resource_route) ->
          [{@http_route, resource_route}, {@url_template, resource_route}]

        nil ->
          []
      end

    ot_attributes =
      get_standard_ot_attributes(request, scheme, host, port) ++
        get_ot_attributes(opts) ++
        resource_route_attribute

    request_ctx = Tracer.start_span(span_name, %{kind: :client, attributes: ot_attributes})
    Tracer.set_current_span(request_ctx)

    result = super(request)

    if Tracer.current_span_ctx() == request_ctx do
      case result do
        {:error, %{reason: reason}} ->
          Tracer.set_status(:error, inspect(reason))
          end_span()

        _ ->
          :ok
      end
    end

    result
  end

  def process_response_status_code(status_code) do
    # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md#status
    if status_code >= 400 do
      Tracer.set_status(:error, "")
    end

    Tracer.set_attribute(@http_response_status_code, status_code)
    end_span()
    status_code
  end

  defp end_span do
    Tracer.end_span()
    restore_parent_ctx()
  end

  # see https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/http.md#name
  defp default_span_name(request), do: request.method |> Atom.to_string() |> String.upcase()

  @ctx_key {__MODULE__, :parent_ctx}
  defp save_parent_ctx do
    ctx = Tracer.current_span_ctx()
    Process.put(@ctx_key, ctx)
  end

  defp restore_parent_ctx do
    ctx = Process.get(@ctx_key, :undefined)
    Process.delete(@ctx_key)
    Tracer.set_current_span(ctx)
  end

  defp get_standard_ot_attributes(request, scheme, host, port) do
    [
      {@http_request_method,
       request.method
       |> Atom.to_string()
       |> String.upcase()},
      {@server_address, host},
      {@server_port, port},
      {@url_full, strip_uri_credentials(request.url)},
      {@url_scheme, scheme}
    ]
  end

  defp get_ot_attributes(opts) do
    default_ot_attributes = Configuration.get(:ot_attributes)

    default_ot_attributes
    |> Enum.concat(Keyword.get(opts, :ot_attributes, []))
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, key, value) end)
    |> Enum.into([], fn {key, value} -> {key, value} end)
  end

  defp get_resource_route(option, request)

  defp get_resource_route(route, _) when is_binary(route), do: route

  defp get_resource_route(infer_fn, request) when is_function(infer_fn, 1), do: infer_fn.(request)

  defp get_resource_route(:infer, request), do: Configuration.get(:infer_route).(request)

  defp get_resource_route(:ignore, _), do: nil

  defp get_resource_route(:unset, _), do: nil

  defp get_resource_route(_unknown_option, _),
    do:
      raise(
        ArgumentError,
        "The :ot_resource_route keyword option value must either be a binary, a function with an arity of 1 or the :infer or :ignore atom"
      )

  defp strip_uri_credentials(uri) do
    uri |> URI.parse() |> Map.put(:userinfo, nil) |> Map.put(:authority, nil) |> URI.to_string()
  end
end
