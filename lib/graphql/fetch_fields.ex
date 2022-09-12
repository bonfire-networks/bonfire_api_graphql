# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.FetchFields do
  @enforce_keys [:queries, :query, :group_fn]
  defstruct [
    :queries,
    :query,
    :group_fn,
    map_fn: nil,
    filters: []
  ]

  import Bonfire.Common.Config, only: [repo: 0]

  alias Bonfire.API.GraphQL.Fields
  alias Bonfire.API.GraphQL.FetchFields

  @type t :: %FetchFields{
          queries: atom,
          query: atom,
          group_fn: (term -> term),
          map_fn: (term -> term) | nil,
          filters: list
        }

  def run(%FetchFields{
        queries: queries,
        query: query,
        group_fn: group_fn,
        map_fn: map_fn,
        filters: filters
      }) do
    apply(queries, :query, [query, filters])
    |> repo().many()
    |> Fields.new(group_fn, map_fn)
  end
end
