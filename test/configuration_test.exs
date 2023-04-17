defmodule ConfigurationTest do
  alias Telepoison.Configuration
  alias Telepoison.TestApi

  use ExUnit.Case

  doctest Telepoison

  test "it does not crash on `get` if it has not been setup" do
    assert Configuration.get(:infer_route)
    assert Configuration.get(:ot_attributes)
  end

  test "if :ot_attributes are not a list it returns error" do
    TestApi.set_env(:ot_attributes, {:key, :value})

    {:error, errors} = Configuration.validate()
    assert length(errors) == 1
  end

  test "if :ot_attributes are a list it returns ok" do
    TestApi.set_env(:ot_attributes, [{:key, :value}])

    assert Configuration.validate() == :ok
  end

  test "if :infer_route is not a function it returns error" do
    TestApi.set_env(:infer_route, :not_a_function)

    {:error, errors} = Configuration.validate()
    assert length(errors) == 1
  end

  test "if :infer_route is a function of arity other than 1 it returns error" do
    TestApi.set_env(:infer_route, fn x, y, z -> {x, y, z} end)

    {:error, errors} = Configuration.validate()
    assert length(errors) == 1
  end

  test "if :infer_route is a function of arity 1 it returns ok" do
    TestApi.set_env(:infer_route, fn x -> x end)

    Configuration.validate() == :ok
  end
end
