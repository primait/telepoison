defmodule TelepoisonTest do
  alias Telepoison
  use ExUnit.Case
  doctest Telepoison

  require OpenTelemetry.Tracer

  setup do
    Telepoison.setup()
    OpenTelemetry.Tracer.start_span("unit test")
    :ok
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
end
