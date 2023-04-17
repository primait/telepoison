defmodule Telepoison.Configuration do
  @moduledoc false

  @spec validate() :: :ok | {:error, [String.t()]}
  def validate() do
    errors = []

    route_inference_fn = get(:infer_route)

    errors =
      if not is_function(route_inference_fn, 1),
        do: ["The configured :infer_route keyword option value must be a function with an arity of 1" | errors],
        else: errors

    ot_attributes = get(:ot_attributes)

    errors =
      if not is_list(ot_attributes),
        do: ["The configured :ot_attributes option must be a [{key, value}] list"],
        else: errors

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  @doc """
  Get a configured option
  """
  @spec get(:infer_route | :ot_attributes) :: any()
  def get(key)

  def get(:infer_route), do: Application.get_env(:telepoison, :infer_route, &Telepoison.URI.infer_route_from_request/1)

  def get(:ot_attributes), do: Application.get_env(:telepoison, :ot_attributes, [])
end
