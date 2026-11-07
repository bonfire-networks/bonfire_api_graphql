defmodule Bonfire.API.GraphQL.RuntimeConfig do
  @behaviour Bonfire.Common.ConfigModule

  @yes ~w(1 true yes on)

  def config_module, do: true

  def config do
    import Config

    # In tests, check every 200 JSON response of a Mastodon API route against the Mastodon spec (see `Bonfire.API.MastoCompat.Test.ValidateResponse`, only plugged in the test env). Opt-in until the responses that don't match yet are fixed
    config :bonfire_api_graphql, Bonfire.API.MastoCompat.Test.ValidateResponse,
      enabled: System.get_env("MASTO_VALIDATE") in @yes
  end
end
