defmodule Vire.MixProject do
  use Mix.Project

  def project do
    [
      app: :vire,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        summary: [threshold: 90],
        ignore_modules: [
          VireWeb,
          Vire.Schema,
          VireWeb.ConnCase,
          Vire.DataCase,
          Vire.AccountsFixtures,
          Vire.ActivitiesFixtures,
          Vire.TrainingFixtures
        ]
      ]
    ]
  end

  def application do
    [
      mod: {Vire.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.16"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.22"},
      {:oban, "~> 2.24"},
      {:jason, "~> 1.4"},
      {:bandit, "~> 1.13"},
      {:bcrypt_elixir, "~> 3.3"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["cmd --cd assets npm ci"],
      "assets.build": ["cmd --cd assets npm run build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      precommit: [
        "compile --warnings-as-errors",
        "format",
        "credo --strict",
        "test --cover"
      ]
    ]
  end
end
