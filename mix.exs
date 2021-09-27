defmodule Telepoison.MixProject do
  use Mix.Project

  def project do
    [
      app: :telepoison,
      version: "1.0.0-rc.4",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: description(),
      aliases: aliases()
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
      {:opentelemetry_api, "~> 1.0.0-rc.2"}
    ] ++ dev_deps()
  end

  def dev_deps, do:
    [
      {:opentelemetry, "~> 1.0.0-rc.2", only: :test},
      {:plug, "~> 1.12", only: :test},
      {:plug_cowboy, "~> 2.2", only: :test},
      {:credo, "~> 1.5", only: [:dev, :test]},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.25.3", only: :dev, runtime: false}
    ]

  def package do
    [
      name: "telepoison",
      maintainers: ["Leonardo Donelli"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/primait/telepoison"}
    ]
  end

  defp aliases do
    [
      "format.all": [
        "format mix.exs \"lib/**/*.{ex,exs}\" \"test/**/*.{ex,exs}\" \"priv/**/*.{ex,exs}\" \"config/**/*.{ex,exs}\""
      ]
    ]
  end

  def description do
    "Telepoison is a opentelemetry-instrumented wrapper around HTTPPoison."
  end
end
