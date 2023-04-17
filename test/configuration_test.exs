defmodule ConfigurationTest do
  alias Telepoison.Configuration
  use ExUnit.Case

  doctest Telepoison

  test "it does not crash on `get` if it has not been setup" do
    assert Configuration.get(:infer_route)
    assert Configuration.get(:ot_attributes)
  end
end
