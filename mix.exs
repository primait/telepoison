defmodule Telepoison.MixProject do
  use Mix.Project

  def project do
    [
      app: :telepoison,
      version: "0.1.1",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.6"},
      {:opentelemetry_api, "~> 0.3.1"},
      {:opentelemetry, "~> 0.4.0", only: :test},
      {:plug, "~> 1.10", only: :test},
      {:plug_cowboy, "~> 2.2", only: :test},
      {:credo, "~> 1.4", only: [:dev, :test]},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
