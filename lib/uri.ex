defmodule Telepoison.URI do
  @moduledoc """
  Exposes a function to normalise URIs in a format suitable for usage as Open Telemetry metadata.
  """

  alias HTTPoison.Request

  @default_route "/"

  @spec infer_route(String.t() | URI.t() | Request.t()) :: String.t()
  @doc """
  Infers the route of the provided `uri`, returned in a format suitable for usage as Open Telemetry metadata.
  """
  def infer_route(uri) when is_nil(uri) or byte_size(uri) <= 1, do: @default_route

  def infer_route(%URI{path: path}) when is_nil(path) or byte_size(path) <= 1, do: @default_route

  def infer_route(%Request{url: url}) when is_nil(url) or byte_size(url) <= 1, do: @default_route

  def infer_route(uri) when is_binary(uri), do: uri |> URI.parse() |> infer_route()

  def infer_route(%Request{url: url}), do: infer_route(url)

  def infer_route(%URI{path: path}) do
    segments =
      path
      |> String.split("/")
      |> Enum.filter(&(byte_size(String.trim(&1)) > 0))

    case Enum.count(segments) do
      1 ->
        "/#{Enum.take(segments, 1)}"

      count when count > 1 ->
        segments
        |> Enum.take(1)
        |> (&"/#{&1}/:subpath").()

      _ ->
        @default_route
    end
  end
end
