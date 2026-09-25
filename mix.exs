defmodule TypedStructBuilderValidators.MixProject do
  use Mix.Project

  @version "0.2.0"
  @repo_url "https://github.com/heydtn/typed_struct_builder_validators"
  @description "A TypedStruct plugin for automatically generating type-safe helper methods for constructing, updating, and validating structs."

  def project do
    [
      app: :typed_struct_builder_validators,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "TypedStructBuilderValidators",
      description: @description,
      source_url: @repo_url,
      deps: deps(),
      dialyzer: dialyzer(),
      docs: docs(),
      package: package()
    ]
  end

  # The dialyzer fixtures are only built under `test`, so that `mix dialyzer`
  # never analyzes the deliberate type errors they contain.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:typed_struct, "~> 0.3.0"},
      {:credo, "~> 1.7.19", only: :dev, runtime: false},
      # Also under `test`: it is what puts OTP's :dialyzer on the code path for
      # the fixture suite in test/dialyzer_test.exs.
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp dialyzer do
    [
      # Use a custom PLT directory for continuous integration caching.
      plt_core_path: System.get_env("PLT_DIR"),
      plt_file: plt_file(),
      plt_add_deps: :app_tree,
      flags: [
        :error_handling,
        :underspecs,
        :unmatched_returns,
        :extra_return,
        :missing_return
      ]
    ]
  end

  defp docs do
    [
      extras: [
        "README.md": [title: "Overview"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      main: "readme",
      source_url: @repo_url,
      source_ref: "v#{@version}",
      formatters: ["html"]
    ]
  end

  defp plt_file do
    case System.get_env("PLT_DIR") do
      nil -> nil
      plt_dir -> {:no_warn, Path.join(plt_dir, "typed_struct_builder_validators.plt")}
    end
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Nate Heydt"],
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
      links: %{
        "GitHub" => @repo_url,
        "Changelog" => "#{@repo_url}/blob/v#{@version}/CHANGELOG.md"
      }
    ]
  end
end
