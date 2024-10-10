defmodule TelepoisonTest do
  alias Telepoison
  alias OpenTelemetry.Tracer
  use Telepoison.Case, async: false

  doctest Telepoison

  require OpenTelemetry.Tracer
  require Record

  for {name, spec} <- Record.extract_all(from_lib: "opentelemetry/include/otel_span.hrl") do
    Record.defrecord(name, spec)
  end

  setup do
    flush_mailbox()
    :otel_simple_processor.set_exporter(:otel_exporter_pid, self())
    :ok
  end

  describe "Telepoison default attributes and headers" do
    test "standard http client span attribute are set in span" do
      Telepoison.get!("http://localhost:8000")

      assert_receive {:span, span(attributes: attributes_record, name: "GET")}
      attributes = elem(attributes_record, 4)

      assert [
               "http.request.method",
               "http.response.status_code",
               "server.address",
               "server.port",
               "url.full",
               "url.scheme"
             ] ==
               attributes |> Map.keys() |> Enum.sort()

      assert {"http.request.method", "GET"} in attributes
      assert {"http.response.status_code", 200} in attributes
      assert {"server.address", "localhost"} in attributes
      assert {"server.port", 8000} in attributes
      assert {"url.full", "http://localhost:8000"} in attributes
      assert {"url.scheme", "http"} in attributes
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

    test "traceparent header is injected to atom user-supplied map headers" do
      %HTTPoison.Response{request: %{headers: headers}} = Telepoison.get!("http://localhost:8000", %{atom: "value"})

      assert "atom" in Enum.map(headers, &elem(&1, 0))
    end

    test "url.full don't contain credentials" do
      Telepoison.get!("http://user:pass@localhost:8000/user/edit/24")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"url.full", "http://localhost:8000/user/edit/24"})
    end
  end

  describe "Telepoison calls with additional options" do
    test "additional span attributes can be passed to Telepoison invocation" do
      Telepoison.get!("http://localhost:8000", [], ot_attributes: [{"app.callname", "mariorossi"}])

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"app.callname", "mariorossi"})
    end

    test "resource route can be explicitly passed to Telepoison invocation as a string" do
      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: "/user/edit")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit"})
      assert confirm_attributes(attributes, {"url.template", "/user/edit"})
    end

    test "resource route can be explicitly passed to Telepoison invocation as a function" do
      infer_fn = fn request -> URI.parse(request.url).path end

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: infer_fn)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit/24"})
      assert confirm_attributes(attributes, {"url.template", "/user/edit/24"})
    end

    test "resource route inference can be explicitly ignored" do
      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: :ignore)

      assert_receive {:span, span(attributes: attributes)}, 1000
      refute confirm_http_route_attribute(attributes)
    end

    test "resource route inference can be implicitly ignored" do
      Telepoison.get!("http://localhost:8000/user/edit/24")

      assert_receive {:span, span(attributes: attributes)}, 1000
      refute confirm_http_route_attribute(attributes)
    end

    test "resource route inference fails if an incorrect value is passed to the Telepoison invocation" do
      assert_raise(ArgumentError, fn ->
        Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: nil)
      end)

      assert_raise(ArgumentError, fn ->
        Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: 1)
      end)
    end

    test "resource route and attributes can be passed to Telepoison as options together" do
      Telepoison.get!("http://localhost:8000/user/edit/24", [],
        ot_resource_route: "/user/edit",
        ot_attributes: [{"app.callname", "mariorossi"}]
      )

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"http.route", "/user/edit"})
      assert confirm_attributes(attributes, {"url.template", "/user/edit"})
      assert confirm_attributes(attributes, {"app.callname", "mariorossi"})
    end
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
        Telepoison.get("http://domain.invalid:8000")

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
      {:error, %HTTPoison.Error{reason: expected_reason}} = Telepoison.get("http://domain.invalid:8001")

      assert_receive {:span, span(status: {:status, :error, recorded_reason})}
      assert inspect(expected_reason) == recorded_reason
    end

    test "HTTP tls errors" do
      {:error, %HTTPoison.Error{reason: expected_reason}} = Telepoison.get("https://localhost:8000")
      assert_receive {:span, span(status: {:status, :error, recorded_reason})}
      assert inspect(expected_reason) == recorded_reason
    end
  end

  describe "Telepoison with additional configuration" do
    test "default attributes can be set via a two element tuple list" do
      set_env(:ot_attributes, [{"test_attribute", "test"}])

      Telepoison.get!("http://localhost:8000/user/edit/24")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"test_attribute", "test"})
    end

    test "default attributes that are not binary will be ignored" do
      set_env(:ot_attributes, [
        {"test_attribute", "test"},
        {1, "ignored"},
        {:ignored, "ignored_too"}
      ])

      Telepoison.get!("http://localhost:8000/user/edit/24")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"test_attribute", "test"})
    end

    test "default attributes can be overridden via a two element tuple list passed to the Telepoison invocation" do
      set_env(:ot_attributes, [{"test_attribute", "test"}])

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_attributes: [{"test_attribute", "overridden"}])

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_attributes(attributes, {"test_attribute", "overridden"})
    end

    test "default attributes can be combined with attributes passed to the Telepoison invocation" do
      set_env(:ot_attributes, [{"test_attribute", "test"}])

      Telepoison.get!("http://localhost:8000/user/edit/24", [],
        ot_attributes: [{"another_test_attribute", "another test"}, {"test_attribute_overridden", "overridden"}]
      )

      assert_receive {:span, span(attributes: attributes)}, 1000

      assert confirm_attributes(attributes, {"test_attribute", "test"})
      assert confirm_attributes(attributes, {"another_test_attribute", "another test"})
      assert confirm_attributes(attributes, {"test_attribute_overridden", "overridden"})
    end

    test "resource route can be implicitly inferred by Telepoison invocation using a default function" do
      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: :infer)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_http_route_attribute(attributes, "/user/:subpath")
    end

    test "resource route can be inferred by Telepoison invocation via a configured function" do
      infer_fn = fn
        %HTTPoison.Request{} = request -> URI.parse(request.url).path
      end

      set_env(:infer_route, infer_fn)

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: :infer)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_http_route_attribute(attributes, "/user/edit/24")
    end

    test "implicit resource route inference can be overridden with a function passed to the Telepoison invocation" do
      infer_fn = fn
        %HTTPoison.Request{} = request -> URI.parse(request.url).path
      end

      invocation_infer_fn = fn _ -> "test" end

      set_env(:infer_route, infer_fn)

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: invocation_infer_fn)

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_http_route_attribute(attributes, "test")
    end

    test "implicit resource route inference can be overridden with a string passed to the Telepoison invocation" do
      infer_fn = fn
        %HTTPoison.Request{} = request -> URI.parse(request.url).path
      end

      set_env(:infer_route, infer_fn)

      Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_resource_route: "test")

      assert_receive {:span, span(attributes: attributes)}, 1000
      assert confirm_http_route_attribute(attributes, "test")
    end
  end

  test "Telepoison works if setup is not called" do
    Telepoison.get!("http://localhost:8000/user/edit/24", [], ot_attributes: [{"some_attribute", "some value"}])

    assert_receive {:span, span(attributes: attributes)}, 1000

    assert confirm_attributes(attributes, {"some_attribute", "some value"})
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

  defp confirm_http_route_attribute(attributes, value) do
    confirm_attributes(attributes, {"http.route", value})
    confirm_attributes(attributes, {"url.template", value})
  end

  defp confirm_http_route_attribute(attributes) do
    confirm_http_route_attribute(attributes, "")
  end
end
