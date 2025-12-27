if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.BatchLoader do
    @moduledoc "Batch loads stats for multiple entities to avoid N+1 queries."

    alias Bonfire.Common.{Types, Utils}

    def preload_follow_counts(users) when is_list(users) do
      Utils.maybe_apply(
        Bonfire.Social.Graph.FollowCounts,
        :batch_load,
        [users],
        fallback_return: %{}
      )
    end

    def preload_follow_counts(_), do: %{}

    def preload_status_counts(users) when is_list(users) do
      Utils.maybe_apply(
        Bonfire.Posts,
        :count_for_users,
        [users],
        fallback_return: %{}
      )
    end

    def preload_status_counts(_), do: %{}

    def preload_account_stats(users) when is_list(users) do
      {preload_follow_counts(users), preload_status_counts(users)}
    end

    def preload_account_stats(_), do: {%{}, %{}}

    @doc "Maps users to Mastodon Account format with batch-loaded stats."
    def map_accounts(users, opts \\ []) when is_list(users) do
      skip_stats = Keyword.get(opts, :skip_expensive_stats, false)

      {follow_counts, status_counts} =
        if skip_stats do
          {%{}, %{}}
        else
          preload_account_stats(users)
        end

      alias Bonfire.API.MastoCompat.Mappers

      users
      |> Enum.map(fn user ->
        user_id = Types.uid(user)

        user_opts =
          opts
          |> Keyword.put(:follow_counts, Map.get(follow_counts, user_id))
          |> Keyword.put(:status_count, Map.get(status_counts, user_id))

        Mappers.Account.from_user(user, user_opts)
      end)
      |> Enum.reject(&is_nil/1)
    end
  end
end
