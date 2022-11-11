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
  Setups the Open Telemetry instrumentation for Telepoison.

  You should call this function within your application startup, before Telepoison is used.
  """
  def setup(opts \\ []) do
    Agent.start_link(
      fn ->
        case Keyword.get(opts, :infer_route) do
          :default ->
            {:ok, &Telepoison.URI.infer_route_from_request/1}

          infer_fn when is_function(infer_fn, 1) ->
            {:ok, infer_fn}

          :disabled ->
            :ok

          _ ->
            :ok
        end
      end,
      name: Keyword.get(opts, :name, __MODULE__)
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
  Performs a request using Telepoison with the provided `request` options.

  See `HTTPoison.request/1` for further details regarding `request` options.

  Will attempt to automatically set the `http.route` Open Telemetry metadata attribute by
  removing the last part of the `request.url` (since this part typically contains dynamic data)
  if the `resource_route` option is set to `:infer`.

  If this behavior is not desirable, it can be set directly by using the aforementioned option.

    ## Examples

      iex> request = %HTTPoison.Request{
      ...> method: :post,
      ...> url: "https://www.example.com/users/edit/2",
      ...> body: ~s({"foo": 3}),
      ...> headers: [{"Accept", "application/json"}],
      ...> options: [resource_route: :infer]}
      iex> Telepoison.request(request)

  """
  def request(%Request{options: opts} = request) do
    save_parent_ctx()

    span_name = Keyword.get_lazy(opts, :ot_span_name, fn -> compute_default_span_name(request) end)

    resource_route =
      case Keyword.get(opts, :ot_resource_route) do
        route when is_binary(route) ->
          route

        infer_fn when is_function(infer_fn, 1) ->
          infer_fn.(request)

        :infer ->
          Agent.get(
            __MODULE__,
            fn
              {:ok, infer_fn} when is_function(infer_fn, 1) ->
                infer_fn.(request)

              :ok ->
                nil
            end
          )

        _ ->
          nil
      end

    attributes =
      [
        {"http.method", request.method |> Atom.to_string() |> String.upcase()},
        {"http.url", request.url}
      ] ++
        Keyword.get(opts, :ot_attributes, []) ++
        if resource_route != nil,
          do: [{"http.route", resource_route}],
          else: []

    new_ctx = Tracer.start_span(span_name, %{kind: :client, attributes: attributes})
    Tracer.set_current_span(new_ctx)

    super(request)
  end

  def process_response_status_code(status_code) do
    # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/trace/semantic_conventions/http.md#status
    Tracer.set_attribute("http.status_code", status_code)
    Tracer.end_span()
    restore_parent_ctx()
    status_code
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
end
