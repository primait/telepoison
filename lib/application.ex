defmodule Telepoison.Application do
  @moduledoc false

  alias Telepoison.Configuration

  use Application

  require Logger

  def start(_type, _args) do
    Logger.debug("Starting telepoison...")
    Configuration.validate()
  end
end
