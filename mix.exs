defmodule Giggly.MixProject do
  use Mix.Project

  def project do
    [
      app: :giggly,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:boundary] ++ Mix.compilers(),
      # Every boundary is strict: a boundary's `deps:` list is the whole of what it may call,
      # outside libraries included, and a boundary inherits nothing from its parent.
      boundary: [default: [type: :strict]],
      quality_steps: [
        {"format (write)", "mix format", skip_on_check: true},
        {"hex.audit", "mix hex.audit"},
        {"deps (unused)", "mix deps.unlock --check-unused"},
        {"compile (:dev)", "mix compile --warnings-as-errors"},
        {"compile (:test)", "MIX_ENV=test mix compile --warnings-as-errors"},
        {"test", "mix test --warnings-as-errors"},
        {"format", "mix format --check-formatted"},
        {"credo", "mix credo --strict"},
        {"rules", "mix tack.rules_check"}
      ],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env())
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
      {:tack, git: "git@github.com:srowley/tack.git", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.6", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev], runtime: false},
      {:muex, "== 0.11.3", only: [:dev, :test], runtime: false},
      {:boundary, "~> 0.11", runtime: false},
      {:table, "~> 0.1.2"},
      {:nimble_options, "~> 1.1"},
      {:color, "~> 0.13.0"},
      {:nx, "~> 1.0"}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases() do
    [quality: ["tack.quality"]]
  end

  defp elixirc_paths(:test) do
    ["lib", "test/support"]
  end

  defp elixirc_paths(_environment) do
    ["lib"]
  end
end
