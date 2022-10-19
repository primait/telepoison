defmodule Telepoison.URITest do
  @moduledoc """
  Tests for `Telepoison.URI`
  """

  alias HTTPoison.Request

  use ExUnit.Case

  alias Telepoison.URI, as: UtilsURI

  @base_uri "https://www.test.com/"

  describe "infer_route/1" do
    test "Nil URI is inferred as a route of '/'" do
      result = UtilsURI.infer_route(nil)

      assert result == "/"
    end

    test "URI consisiting of whitespace is inferred as a route of '/'" do
      result = UtilsURI.infer_route("")

      assert result == "/"
    end

    test "URI '#{@base_uri}user/edit/24' is inferred as a route of '/user/:subpath'" do
      result = UtilsURI.infer_route("#{@base_uri}user/edit/24")

      assert result == "/user/:subpath"
    end

    test "URI '#{@base_uri}user/24' is inferred as a route of '/user:subpath'" do
      result = UtilsURI.infer_route("#{@base_uri}user/24")

      assert result == "/user/:subpath"
    end

    test "URI '#{@base_uri}user' is inferred as route of '/user'" do
      result = UtilsURI.infer_route("#{@base_uri}user")

      assert result == "/user"
    end

    test "URI '#{@base_uri}' is inferred as route of '/'" do
      result = UtilsURI.infer_route("#{@base_uri}")

      assert result == "/"
    end

    test "Nil URI path is inferred as a route of '/'" do
      uri = %URI{path: nil}

      result = UtilsURI.infer_route(uri)

      assert result == "/"
    end

    test "URI path consisiting of whitespace is inferred as a route of '/'" do
      uri = %URI{path: ""}

      result = UtilsURI.infer_route(uri)

      assert result == "/"
    end

    test "URI path '/user/edit/24' is inferred as a route of '/user/:subpath'" do
      uri = %URI{path: "/user/edit/24"}

      result = UtilsURI.infer_route(uri)

      assert result == "/user/:subpath"
    end

    test "URI path '/user/24' is inferred as a route of '/user:subpath'" do
      uri = %URI{path: "/user/24"}

      result = UtilsURI.infer_route(uri)

      assert result == "/user/:subpath"
    end

    test "URI path 'user' is inferred as route of '/user'" do
      uri = %URI{path: "user"}

      result = UtilsURI.infer_route(uri)

      assert result == "/user"
    end

    test "Nil Request URL is inferred as a route of '/'" do
      request = %Request{url: nil}

      result = UtilsURI.infer_route(request)

      assert result == "/"
    end

    test "Request URL consisiting of whitespace is inferred as a route of '/'" do
      request = %Request{url: ""}

      result = UtilsURI.infer_route(request)

      assert result == "/"
    end

    test "Request URL '/user/edit/24' is inferred as a route of '/user/:subpath'" do
      request = %Request{url: "/user/edit/24"}

      result = UtilsURI.infer_route(request)

      assert result == "/user/:subpath"
    end

    test "Request URL '/user/24' is inferred as a route of '/user:subpath'" do
      request = %Request{url: "/user/24"}

      result = UtilsURI.infer_route(request)

      assert result == "/user/:subpath"
    end

    test "Request URL 'user' is inferred as route of '/user'" do
      request = %Request{url: "user"}

      result = UtilsURI.infer_route(request)

      assert result == "/user"
    end
  end
end
