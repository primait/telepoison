defmodule TelepoisonTest do
  alias Telepoison
  use ExUnit.Case

  doctest Telepoison

  require Record

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  setup do
    flush_mailbox()
    :otel_batch_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  describe "Telepoison setup without additional configuration" do
    setup do
      Telepoison.setup()
    end

    test "standard http client span attribute are set in span" do
      Telepoison.get!("http://localhost:8000")

      assert_receive {:span, span(attributes: attributes_record)}
      attributes = elem(attributes_record, 4)

      assert ["http.method", "http.status_code", "http.url"] ==
               attributes |> Map.keys() |> Enum.sort()

      assert {"http.method", "GET"} in attributes
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
      Telepoison.get!("http://localhost:8000", [], ot_attributes: [{"app.callname", "mariorossi"}])

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"app.callname", "mariorossi"})
    end

    test "resource route can be explicitly passed to Telepoison invocation as a string" do
      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: "/user/edit")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit"})
    end

    test "resource route can be explicitly passed to Telepoison invocation as a function" do
      infer_fn = fn request -> URI.parse(request.url).path end

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: infer_fn)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit/24"})
    end
  end

  describe "Telepoison setup with additional configuration" do
    test "resource route can be implicitly inferred by Telepoison invocation by default function" do
      Telepoison.setup(infer_route: :default)

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: :infer)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/:subpath"})
    end

    test "resource route can be implicitly inferred by Telepoison invocation by explicitly configured function" do
      infer_fn = fn
        %HTTPoison.Request{} = request -> URI.parse(request.url).path
      end

      Telepoison.setup(infer_route: infer_fn)

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: :infer)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit/24"})
    end
  end

  def flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      10 -> :ok
    end
  end

  defp confirm_attributes(attributes, attributes_to_confirm) do
    attributes
    |> Tuple.to_list()
    |> Enum.filter(&is_map/1)
    |> Enum.any?(fn map ->
      attributes_to_confirm in map
    end)
  end
end
