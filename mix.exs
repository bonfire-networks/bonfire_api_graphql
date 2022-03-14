Code.eval_file("mess.exs")
defmodule Bonfire.API.GraphQL.MixProject do
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
        # {:bonfire_me, git: "https://github.com/bonfire-networks/bonfire_me", branch: "main", optional: true},
        {:grumble, "~> 0.1.3", only: [:dev, :test], optional: true}
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application, do: [extra_applications: [:logger]]

end
