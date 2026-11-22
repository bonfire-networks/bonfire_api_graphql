if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Accounts do
    @moduledoc """
    Reads accounts by id through GraphQL (`characters(ids:)`), for mappers with no GraphQL parent
    to select them in: reports, conversations, a boost's booster.
    """

    use Bonfire.Common.Utils

    alias Bonfire.API.MastoCompat.{Fragments, Helpers}

    @query """
    query ($ids: [ID!]!) { characters(ids: $ids) { #{Fragments.actor_fields()} } }
    """

    # with the counts, for an account shown as an author
    @query_with_counts """
    query ($ids: [ID!]!) { characters(ids: $ids) { #{Fragments.author_fields()} } }
    """

    @account_schemas [
      Bonfire.Data.Identity.User,
      Bonfire.Data.Identity.Character,
      Bonfire.Classify.Category
    ]

    @doc "Whether `object` is something a Mastodon account is made from: a user, its character, or a group or topic. By schema, since `Types.object_type/1` answers `:group` for a group."
    def account?(object), do: Bonfire.Common.Types.object_type_schema(object) in @account_schemas

    @doc "`%{id => account}` for the ids the reader may see, in one GraphQL run (none for an empty list). `counts: true` selects the counts."
    def by_ids(ids, current_user, opts \\ []) do
      case ids |> List.wrap() |> Enum.reject(&is_nil/1) |> Enum.uniq() do
        [] ->
          %{}

        ids ->
          query = if opts[:counts], do: @query_with_counts, else: @query

          case Helpers.run_query(query, current_user, %{"ids" => ids}) do
            {:ok, %{data: %{characters: characters}}} when is_list(characters) ->
              characters
              |> Enum.reject(&is_nil/1)
              |> Map.new(&{&1[:id], &1})

            other ->
              warn(other, "Could not read accounts #{inspect(ids)}")
              %{}
          end
      end
    end
  end
end
