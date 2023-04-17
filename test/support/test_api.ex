defmodule Telepoison.TestApi do
  @moduledoc false

  alias ExUnit.Callbacks

  def set_env(key, value) do
    env_to_restore = Application.get_env(:telepoison, key, :unset)
    Application.put_env(:telepoison, key, value)

    Callbacks.on_exit(fn ->
      case env_to_restore do
        :unset -> Application.delete_env(:telepoison, key)
        _ -> Application.put_env(:telepoison, key, env_to_restore)
      end
    end)
  end
end
