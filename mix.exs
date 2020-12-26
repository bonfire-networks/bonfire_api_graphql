Code.eval_file("mess.exs")
defmodule Bonfire.GraphQL.MixProject do
  use Mix.Project

  def project do
    [
      app: :bonfire_api_graphql,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      deps: Mess.deps [
        {:phoenix_live_reload, "~> 1.2", only: :dev},
        {:bonfire_me, git: "https://github.com/bonfire-ecosystem/bonfire_me", branch: "main", optional: true},
        {:zest, "~> 0.1", only: :test},
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

end
