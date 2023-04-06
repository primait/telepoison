defmodule Telepoison.Configuration do
  @moduledoc false

  alias HTTPoison.Request

  @spec setup(infer_fn: (Request.t() -> String.t()), ot_attributes: [{String.t(), String.t()}]) :: :ok
  def setup(opts \\ []) do
    Agent.start_link(fn -> set_defaults(opts) end, name: __MODULE__)

    :ok
  end

  defp set_defaults(opts) do
    infer_fn =
      case Keyword.get(opts, :infer_route) do
        nil ->
          &Telepoison.URI.infer_route_from_request/1

        infer_fn when is_function(infer_fn, 1) ->
          infer_fn
      end

    ot_attributes =
      case Keyword.get(opts, :ot_attributes) do
        ot_attributes when is_list(ot_attributes) ->
          Enum.map(ot_attributes, fn
            {key, value} when is_binary(key) and is_binary(value) ->
              {key, value}

            _ ->
              nil
          end)

        _ ->
          []
      end

    {infer_fn, ot_attributes}
  end

  @doc """
  Get a configuration value or raise `ArgumentError`
  """
  @spec get!(:infer_fn | :ot_attributes) :: any
  def get!(key) do
    case get(key) do
      {:ok, value} -> value
      {:error, error} -> raise ArgumentError, error
    end
  end

  @doc """
  Get a configuration value if present and `setup` has been called or return an error
  """
  @spec get(:infer_fn | :ot_attributes) :: {:ok, any()} | {:error, String.t()}
  def get(key)

  def get(:infer_fn) do
    if agent_started?() do
      Agent.get(
        __MODULE__,
        fn
          {infer_fn, _} when is_function(infer_fn, 1) ->
            {:ok, infer_fn}

          _ ->
            {:error, "The configured :infer_route keyword option value must be a function with an arity of 1"}
        end
      )
    else
      {:error, "Route inference function hasn't been configured"}
    end
  end

  def get(:ot_attributes) do
    if agent_started?() do
      attributes =
        Agent.get(
          __MODULE__,
          fn
            {_, ot_attributes} when is_list(ot_attributes) ->
              ot_attributes

            _ ->
              []
          end
        )

      {:ok, attributes}
    else
      {:ok, []}
    end
  end

  defp agent_started?, do: Process.whereis(__MODULE__) != nil
end
