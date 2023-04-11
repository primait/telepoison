defmodule ConfigurationTest do
  alias Telepoison.Configuration
  use ExUnit.Case

  doctest Telepoison

  test "it does not crash on `get` if it has not been setup" do
    assert {:error, "Route inference function hasn't been configured"} == Configuration.get(:infer_fn)
    assert {:ok, []} == Configuration.get(:ot_attributes)
  end
end
