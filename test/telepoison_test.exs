defmodule TelepoisonTest do
  alias Telepoison
  use ExUnit.Case
  doctest Telepoison

  require Record
  require OpenTelemetry.Tracer

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/ot_span.hrl") do
    Record.defrecord(name, spec)
  end

  setup_all do
    Telepoison.setup()
    :ok
  end

  setup do
    :ot_batch_processor.set_exporter(:ot_exporter_pid, self())
    flush_mailbox()
    :ok
  end

  test "standard http client span attribute are set in span" do
    Telepoison.get!("http://localhost:8000")

    assert_receive {:span, span(attributes: attributes)}

    assert ["http.method", "http.status_code", "http.url"] ==
             attributes |> Enum.map(&elem(&1, 0)) |> Enum.sort()
  end

  test "traceparent header is injected when no headers" do
    %HTTPoison.Response{request: %{headers: headers}} = Telepoison.get!("http://localhost:8000")
    assert "traceparent" in Enum.map(headers, &elem(&1, 0))
  end

  test "traceparent header is injected when list headers" do
    %HTTPoison.Response{request: %{headers: headers}} =
      Telepoison.get!("http://localhost:8000", [{"Accept", "application/json"}])

    assert "traceparent" in Enum.map(headers, &elem(&1, 0))
  end

  test "traceparent header is injected to user-supplied map headers" do
    %HTTPoison.Response{request: %{headers: headers}} =
      Telepoison.get!("http://localhost:8000", %{"Accept" => "application/json"})

    assert "traceparent" in Enum.map(headers, &elem(&1, 0))
  end

  test "additional span attributes can be passed to Telepoison invocation" do
    %HTTPoison.Response{request: %{headers: headers}} =
      Telepoison.get!("http://localhost:8000", [], ot_attributes: [{"app.callname", "mariorossi"}])

    assert_receive {:span, span(attributes: attributes)}, 1000

    assert {"app.callname", "mariorossi"} in attributes
  end

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      10 -> :ok
    end
  end
end
