defmodule Telepoison.Configuration do
  @moduledoc false

  @default_route_inference_function &Telepoison.URI.infer_route_from_request/1

  defstruct [:infer_route, :ot_attributes]

  alias HTTPoison.Request

  @spec setup(infer_route: (Request.t() -> String.t()), ot_attributes: [{String.t(), String.t()}]) :: :ok
  def setup(opts \\ []) do
    Agent.start_link(fn -> set_configuration(opts) end, name: __MODULE__)

    :ok
  end

  defp set_configuration(opts) do
    infer_fn =
      case Keyword.get(opts, :infer_route) do
        # Unset, return default function
        nil ->
          @default_route_inference_function

        infer_fn when is_function(infer_fn, 1) ->
          infer_fn

        # Set incorrectly
        _ ->
          raise RuntimeError, "The configured :infer_route keyword option value must be a function with an arity of 1"
      end

    ot_attributes =
      case Keyword.get(opts, :ot_attributes) do
        nil ->
          []

        ot_attributes when is_list(ot_attributes) ->
          Enum.filter(ot_attributes, fn
            {key, value} when is_binary(key) and is_binary(value) ->
              true

            _ ->
              false
          end)

        _ ->
          raise RuntimeError, "The configured :ot_attributes option must be a [{key, value}] list"
      end

    %__MODULE__{infer_route: infer_fn, ot_attributes: ot_attributes}
  end

  @doc """
  Get a configuration value or raise a `RuntimeError`
  """
  @spec get!(:infer_route | :ot_attributes) :: any
  def get!(key) do
    case get(key) do
      {:ok, value} -> value
      {:error, error} -> raise RuntimeError, error
    end
  end

  @doc """
  Get a configuration value if present and `setup` has been called or return an error
  """
  @spec get(:infer_route | :ot_attributes) :: {:ok, any()} | {:error, String.t()}
  def get(key)

  def get(:infer_route) do
    try do
      Agent.get(
        __MODULE__,
        fn
          %__MODULE__{infer_route: infer_fn} ->
            {:ok, infer_fn}
        end
      )
    catch
      :exit, {:noproc, _} ->
        {:ok, @default_route_inference_function}
    end
  end

  def get(:ot_attributes) do
    try do
      attributes =
        Agent.get(
          __MODULE__,
          fn
            %__MODULE__{ot_attributes: ot_attributes} ->
              ot_attributes
          end
        )

      {:ok, attributes}
    catch
      :exit, {:noproc, _} ->
        {:ok, []}
    end
  end
end
