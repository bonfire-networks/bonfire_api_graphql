defmodule Bonfire.API.GraphQL.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule

  @yes ~w(1 true yes on)

  def config_module, do: true

  def config do
    import Config

    # In tests, check every 200 JSON response of a Mastodon API route against the Mastodon spec (see `Bonfire.API.MastoCompat.Test.ValidateResponse`, only plugged in the test env). Opt-in until the responses that don't match yet are fixed
    config :bonfire_api_graphql, Bonfire.API.MastoCompat.Test.ValidateResponse,
      enabled: System.get_env("MASTO_VALIDATE") in @yes

    # Limits on the GraphQL endpoint: how deep fields may nest in a query, how many queries one JSON batch may hold, and whether guests may read the schema (`__schema` queries and `GET /api/schema`; public except in prod, where only signed-in users may)
    config :bonfire_api_graphql,
      max_depth: String.to_integer(System.get_env("GRAPHQL_MAX_DEPTH", "15")),
      max_batch: String.to_integer(System.get_env("GRAPHQL_MAX_BATCH", "10")),
      public_introspection:
        System.get_env(
          "GRAPHQL_PUBLIC_INTROSPECTION",
          if(Bonfire.Common.Config.env() == :prod, do: "false", else: "true")
        ) in @yes
  end
end
