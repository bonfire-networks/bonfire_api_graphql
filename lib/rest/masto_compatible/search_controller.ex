if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompatible.SearchController do
    @moduledoc """
    Mastodon-compatible search endpoint.

    Implements the v2 search endpoint which returns accounts, statuses, and hashtags.
    Delegates to Bonfire.Search.API.GraphQLMasto.Adapter for business logic.
    """
    use Bonfire.UI.Common.Web, :controller
    import Untangle

    alias Bonfire.Search.API.GraphQLMasto.Adapter

    @doc "Search for accounts, statuses, and hashtags"
    def search(conn, params) do
      debug(params, "GET /api/v2/search")

      Adapter.search(params, conn)
    end
  end
end
