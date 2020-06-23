defmodule Telepoison do
  @moduledoc """
  Documentation for `Telepoison`.
  """

  use HTTPoison.Base
  require OpenTelemetry

  require OpenTelemetry.Tracer
  require OpenTelemetry.Span
  require Record

  def setup() do
    OpenTelemetry.register_application_tracer(:telepoison)
  end

  def process_request_options(options) do
    OpenTelemetry.Tracer.start_span(
      Keyword.get(options, :ot_span_name, "HTTPoison client request")
    )

    options
  end

  def process_request_url(url) do
    OpenTelemetry.Span.set_attribute("http.url", url)
    url
  end

  def process_request_headers(headers) do
    :ot_propagation.http_inject(headers)
  end

  def process_response_status_code(status_code) do
    OpenTelemetry.Span.set_attribute("http.status_code", status_code)
    # OpenTelemetry.status(code, message) # TODO: transform http status in span status
    OpenTelemetry.Tracer.end_span()
    status_code
  end
end
