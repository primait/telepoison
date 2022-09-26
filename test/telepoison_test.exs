defmodule TelepoisonTest do
  alias Telepoison
  alias OpenTelemetry.Tracer
  use ExUnit.Case

  doctest Telepoison

  require OpenTelemetry.Tracer
  require Record

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  setup_all do
    Telepoison.setup()
    :ok
  end

  setup do
    flush_mailbox()
    :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  test "standard http client span attribute are set in span" do
    Telepoison.get!("http://localhost:8000")

    assert_receive {:span, span(attributes: attributes_record)}
    attributes = elem(attributes_record, 4)

    assert ["http.method", "http.status_code", "http.url"] ==
             attributes |> Map.keys() |> Enum.sort()

    assert {"http.method", "GET"} in attributes
  end

  test "additional span attributes can be passed to Telepoison invocation" do
    Telepoison.get!("http://localhost:8000", [], ot_attributes: [{"app.callname", "mariorossi"}])

    assert_receive {:span, span(attributes: attributes)}, 1000
    assert {"app.callname", "mariorossi"} in elem(attributes, 4)
  end

  describe "parent span is not affected" do
    test "with a successful request" do
      Tracer.with_span "parent" do
        pre_request_ctx = Tracer.current_span_ctx()
        Telepoison.get("http://localhost:8000")

        post_request_ctx = Tracer.current_span_ctx()
        assert post_request_ctx == pre_request_ctx
      end
    end

    test "with an nxdomain request" do
      Tracer.with_span "parent" do
        pre_request_ctx = Tracer.current_span_ctx()
        Telepoison.get("http://localghost:8000")

        post_request_ctx = Tracer.current_span_ctx()
        assert post_request_ctx == pre_request_ctx
      end
    end
  end

  describe "span_status is set to error for" do
    test "status codes >= 400" do
      Telepoison.get!("http://localhost:8000/status/400")

      assert_receive {:span, span(status: {:status, :error, ""})}
    end

    test "HTTP econnrefused errors" do
      {:error, %HTTPoison.Error{reason: expected_reason}} = Telepoison.get("http://localhost:8001")

      assert_receive {:span, span(status: {:status, :error, recorded_reason})}
      assert inspect(expected_reason) == recorded_reason
    end

    test "HTTP nxdomain errors" do
      {:error, %HTTPoison.Error{reason: expected_reason}} = Telepoison.get("http://localghost:8001")

      assert_receive {:span, span(status: {:status, :error, recorded_reason})}
      assert inspect(expected_reason) == recorded_reason
    end

    test "HTTP tls errors" do
      {:error, %HTTPoison.Error{reason: expected_reason}} = Telepoison.get("https://localhost:8000")
      assert_receive {:span, span(status: {:status, :error, recorded_reason})}
      assert inspect(expected_reason) == recorded_reason
    end
  end

  describe "traceparent header is injected" do
    test "when no headers" do
      %HTTPoison.Response{request: %{headers: headers}} = Telepoison.get!("http://localhost:8000")
      assert "traceparent" in Enum.map(headers, &elem(&1, 0))
    end

    test "when list headers" do
      %HTTPoison.Response{request: %{headers: headers}} =
        Telepoison.get!("http://localhost:8000", [{"Accept", "application/json"}])

      assert "traceparent" in Enum.map(headers, &elem(&1, 0))
    end

    test "to user-supplied map headers" do
      %HTTPoison.Response{request: %{headers: headers}} =
        Telepoison.get!("http://localhost:8000", %{"Accept" => "application/json"})

      assert "traceparent" in Enum.map(headers, &elem(&1, 0))
    end
  end

  def flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      10 -> :ok
    end
  end
end
