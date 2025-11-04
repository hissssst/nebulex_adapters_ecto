defmodule Nebulex.Adapters.Ecto.MixProject do
  use Mix.Project

  @version "1.1.0"

  def project do
    [
      app: :nebulex_adapters_ecto,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      package: package(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      docs: docs(),
      deps: deps()
    ]
  end

  def description do
    """
    Nebulex adapter powered by Ecto Postgres
    """
  end

  defp package do
    [
      description: description(),
      licenses: ["BSD-2-Clause"],
      files: [
        "lib",
        "mix.exs",
        "README.md",
        ".formatter.exs"
      ],
      maintainers: [
        "Georgy Sychev"
      ],
      links: %{
        GitHub: "https://github.com/hissssst/nebulex_adapters_ecto",
        Changelog: "https://github.com/hissssst/nebulex_adapters_ecto/blob/master/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      source_ref: "v#{@version}",
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nebulex, "~> 2.5"},
      {:ecto, "~> 3.10"},
      {:ecto_sql, "~> 3.10"},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: true},

      # For testing
      {:postgrex, ">= 0.0.0", only: :test},

      # Documentation, linters
      {:credo, "~> 1.5", only: :dev, runtime: false},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      test: [
        "ecto.drop --quiet",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
