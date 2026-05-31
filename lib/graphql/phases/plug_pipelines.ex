defmodule Bonfire.API.GraphQL.PlugPipelines do
  # alias Bonfire.API.GraphQL.Phase.Arguments
  alias Absinthe.Phase
  alias Absinthe.Pipeline

  # Default complexity ceiling for the PUBLIC GraphQL endpoint. Generous enough for
  # introspection + rich client queries, low enough that pathological pagination/nesting
  # (Needle-pointer assocs are recursive) is rejected. Tune in prod via config:
  #   config :bonfire_api_graphql, max_complexity: N
  @default_max_complexity 8_000

  # Default lexer token ceiling: rejects absurdly large documents (megabyte payloads) before
  # parsing. Generous for any legit query incl. introspection (~1-2k tokens). Tune via:
  #   config :bonfire_api_graphql, token_limit: N
  @default_token_limit 15_000

  @doc """
  Pipeline for the public `Absinthe.Plug` endpoint. Enables complexity analysis so abusive
  queries are rejected before resolution. NOTE: this is wired only into the public HTTP
  endpoint (see the graphql_router `forward`); internal `Absinthe.run/3` calls (the
  REST-on-GraphQL reads) use Absinthe's default pipeline and are intentionally NOT limited.
  """
  def default_pipeline(config, opts) do
    max_complexity =
      Application.get_env(:bonfire_api_graphql, :max_complexity, @default_max_complexity)

    token_limit =
      Application.get_env(:bonfire_api_graphql, :token_limit, @default_token_limit)

    opts =
      Keyword.merge(opts,
        analyze_complexity: true,
        max_complexity: max_complexity,
        token_limit: token_limit
      )

    Absinthe.Plug.default_pipeline(config, opts)

    # |> Pipeline.replace( # FIXME: this breaks triggering subscription notifications
    #   Phase.Document.Execution.Resolution,
    #   Bonfire.API.GraphQL.Phase.ExecutionResolution
    # )

    # |> Pipeline.insert_after(Phase.Schema.TypeImports, __MODULE__)
    # |> Pipeline.insert_before(Phase.Document.Result, Bonfire.API.GraphQL.Phase.Debug)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Parse)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.insert_after(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.replace(Phase.Document.Arguments.FlagInvalid, Arguments.FlagInvalid)
    # |> Pipeline.replace(Phase.Document.Arguments.Data, Arguments.Data)
  end

  # This receives (and should also return) the blueprint of the schema:
  def run(blueprint, _) do
    {
      :ok,
      blueprint

      # |> IO.inspect(label: "blueprint")
    }
  end
end
