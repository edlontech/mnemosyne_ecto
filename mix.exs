defmodule MnemosyneEcto.MixProject do
  use Mix.Project

  def project do
    [
      app: :mnemosyne_ecto,
      description: description(),
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.19",
      test_coverage: [tool: ExCoveralls],
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MnemosyneEcto.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.post": :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        "test.integration": :test
      ]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.8", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: :dev},
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.24", optional: true},
      {:ex_check, "~> 0.16", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:assert_eventually, "~> 1.0", only: :test},
      {:mimic, "~> 2.0", only: :test},
      {:mix_audit, ">= 0.0.0", only: [:dev, :test], runtime: false},
      {:mnemosyne, "~> 0.3"},
      {:oeditus_credo, "~> 0.8", only: [:dev], runtime: false},
      {:pgvector, "~> 0.3", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      {:sqlite_vec, "~> 0.1", optional: true},
      {:recode, "~> 0.8", only: [:dev, :test], runtime: false},
      {:splode, "~> 0.3"},
      {:sycophant, "~> 0.1", only: [:dev, :test]},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true},
      {:telemetry, "~> 1.3"},
      {:tidewave, "~> 0.5", only: :dev, runtime: false},
      {:zoi, "~> 0.11"}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.integration": ["test --only integration"]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/edlontech/mnemosyne_ecto",
      extras: [
        {"README.md", title: "Overview"},
        {"LICENSE", title: "License"}
      ],
      groups_for_extras: [
        About: [
          "LICENSE"
        ]
      ],
      groups_for_modules: []
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description() do
    "Database-agnostic Ecto backend (PostgreSQL/pgvector or SQLite/sqlite-vec) " <>
      "for the Mnemosyne agentic memory library."
  end

  defp package() do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/edlontech/mnemosyne_ecto"},
      files: ~w(lib priv mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end
end
