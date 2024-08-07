Code.eval_file("mess.exs", (if File.exists?("../../lib/mix/mess.exs"), do: "../../lib/mix/"))

defmodule Bonfire.API.GraphQL.MixProject do
  use Mix.Project

  def project do
    if System.get_env("AS_UMBRELLA") == "1" do
      [
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock"
      ]
    else
      []
    end
    ++
    [
      app: :bonfire_api_graphql,
      version: "0.2.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers(),
      deps:
        Mess.deps([
          {:phoenix_live_reload, "~> 1.2", only: :dev},
          # {:bonfire_me, git: "https://github.com/bonfire-networks/bonfire_me", optional: true, runtime: false},
          {:grumble, "~> 0.1.3", only: [:dev, :test], optional: true}
        ])
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]
end
