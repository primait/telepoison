defmodule Telepoison do
  @moduledoc """
  OpenTelemetry-instrumented wrapper around HTTPoison.Base

  A client request span is created on request creation, and ended once we get the response.
  http.status and other standard http span attributes are set automatically.
  """

  use HTTPoison.Base

  require OpenTelemetry
  require OpenTelemetry.Tracer
  require OpenTelemetry.Span
  require Record

  alias HTTPoison.Request
  alias OpenTelemetry.Tracer

  @doc ~S"""
  Configures Telepoison using the provided `opts` `Keyword list`.
  You should call this function within your application startup, before Telepoison is used.

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

  """
  def setup(opts \\ []) do
    Agent.start_link(
      fn ->
        infer_fn =
          case Keyword.get(opts, :infer_route) do
            nil ->
              &Telepoison.URI.infer_route_from_request/1

            infer_fn when is_function(infer_fn, 1) ->
              infer_fn
          end

        ot_attributes =
          case Keyword.get(opts, :ot_attributes) do
            ot_attributes when is_list(ot_attributes) ->
              Enum.map(ot_attributes, fn
                {key, value} when is_binary(key) and is_binary(value) ->
                  {key, value}

                _ ->
                  nil
              end)

            _ ->
              []
          end

        {infer_fn, ot_attributes}
      end,
      name: __MODULE__
    )

    :ok
  end

  def process_request_headers(headers) when is_map(headers) do
    headers
    |> Enum.into([])
    |> process_request_headers()
  end

  def process_request_headers(headers) when is_list(headers) do
    :otel_propagator_text_map.inject(headers)
  end

  @doc ~S"""
  Performs a request using Telepoison with the provided `t:HTTPoison.Request/0` `request`.

  Depending on configuration passed to `Telepoison.setup/1` and whether or not the `:ot_resource_route`
  option is set to `:infer` (provided as a part of the `t:HTTPoison.Request/0` `options` `Keyword list`)
  this may attempt to automatically set the `http.route` Open Telemetry metadata attribute by obtaining
  the first segment of the `t:HTTPoison.Request/0` `url` (since this part typically does not contain dynamic data)

  If this behavior is not desirable, it can be set directly as a string or a function
  with an arity of 1 (the `t:HTTPoison.Request/0` `request`) by using the aforementioned `:ot_resource_route` option.

  It can also be circumvented entirely by suppling `:ignore`  instead.

    ## Examples

      iex> Telepoison.setup()
      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}]}
      iex> Telepoison.request(request)

      iex> Telepoison.setup()
      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: :infer]}
      iex> Telepoison.request(request)

      iex> Telepoison.setup()
      iex> resource_route = "/users/edit/"
      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [ot_resource_route: resource_route]}
      iex> Telepoison.request(request)

      iex> Telepoison.setup()
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

      iex> Telepoison.setup()
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

    span_name = Keyword.get_lazy(opts, :ot_span_name, fn -> compute_default_span_name(request) end)

    %URI{host: host} = request.url |> process_request_url() |> URI.parse()

    resource_route = fn ->
      case get_resource_route(opts, request) do
        resource_route when is_binary(resource_route) ->
          [{"http.route", resource_route}]

        nil ->
          []
      end
    end

    ot_attributes =
      get_standard_ot_attributes(request, host) ++
        get_ot_attributes(opts) ++
        resource_route.()

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

    Tracer.set_attribute("http.status_code", status_code)
    end_span()
    status_code
  end

  defp end_span do
    Tracer.end_span()
    restore_parent_ctx()
  end

  def compute_default_span_name(request) do
    method_str = request.method |> Atom.to_string() |> String.upcase()
    %URI{authority: authority} = request.url |> process_request_url() |> URI.parse()
    "#{method_str} #{authority}"
  end

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

  defp get_standard_ot_attributes(request, host) do
    [
      {"http.method",
       request.method
       |> Atom.to_string()
       |> String.upcase()},
      {"http.url", request.url},
      {"net.peer.name", host}
    ]
  end

  defp get_ot_attributes(opts) do
    default_ot_attributes = get_defaults(:ot_attributes)

    default_ot_attributes
    |> Enum.concat(Keyword.get(opts, :ot_attributes, []))
    |> Enum.reduce(%{}, fn {key, value}, acc -> Map.put(acc, key, value) end)
    |> Enum.into([], fn {key, value} -> {key, value} end)
  end

  defp get_resource_route([ot_resource_route: route], _) when is_binary(route) do
    route
  end

  defp get_resource_route([ot_resource_route: infer_fn], request) when is_function(infer_fn, 1) do
    infer_fn.(request)
  end

  defp get_resource_route([ot_resource_route: :infer], request) do
    get_defaults(:infer_fn).(request)
  end

  defp get_resource_route([ot_resource_route: :ignore], _) do
    nil
  end

  defp get_resource_route([ot_resource_route: _], _) do
    raise ArgumentError,
          "The :ot_resource_route keyword option value must either be a binary, a function with an arity of 1 or the :infer or :ignore atom"
  end

  defp get_resource_route(_, _) do
    nil
  end

  defp get_defaults(:infer_fn) do
    Agent.get(
      __MODULE__,
      fn
        {infer_fn, _} when is_function(infer_fn, 1) ->
          infer_fn

        _ ->
          raise ArgumentError,
                "The configured :infer_route keyword option value must be a function with an arity of 1"
      end
    )
  end

  defp get_defaults(:ot_attributes) do
    Agent.get(
      __MODULE__,
      fn
        {_, ot_attributes} when is_list(ot_attributes) ->
          ot_attributes

        _ ->
          []
      end
    )
  end
end
