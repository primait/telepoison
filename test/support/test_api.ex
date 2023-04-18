defmodule Telepoison.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  setup do
    on_exit(fn ->
      Application.delete_env(:telepoison, :infer_route)
      Application.delete_env(:telepoison, :ot_attributes)
    end)
  end

  using do
    quote do
      defp set_env(key, value), do: Application.put_env(:telepoison, key, value)
    end
  end
end
