if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.BatchLoader do
    @moduledoc """
    Batch loads data for multiple entities to avoid N+1 queries.

    Use this module to preload stats and associations for lists of users/posts
    BEFORE mapping them with the Mappers modules.

    ## Example

        users = [user1, user2, user3]

        # Batch load all stats (2 queries instead of N*3)
        follow_counts = BatchLoader.preload_follow_counts(users)
        status_counts = BatchLoader.preload_status_counts(users)

        # Map with preloaded data
        accounts = Enum.map(users, fn user ->
          user_id = Types.uid(user)
          Mappers.Account.from_user(user,
            follow_counts: Map.get(follow_counts, user_id),
            status_count: Map.get(status_counts, user_id)
          )
        end)
    """

    use Bonfire.Common.Repo
    import Ecto.Query

    alias Bonfire.Common.Types

    @doc """
    Batch load follow counts (followers and following) for multiple users.

    Returns a map of user_id => %{followers: count, following: count}

    ## Example

        follow_counts = BatchLoader.preload_follow_counts(users)
        # => %{"user_id_1" => %{followers: 10, following: 5}, ...}
    """
    def preload_follow_counts(users) when is_list(users) do
      user_ids =
        users
        |> Enum.map(&Types.uid/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      if user_ids == [] do
        %{}
      else
        from(fc in Bonfire.Data.Social.FollowCount,
          where: fc.id in ^user_ids,
          select: {fc.id, %{followers: fc.object_count, following: fc.subject_count}}
        )
        |> repo().all()
        |> Map.new()
      end
    end

    def preload_follow_counts(_), do: %{}

    @doc """
    Batch load status (post) counts for multiple users.

    Returns a map of user_id => count

    ## Example

        status_counts = BatchLoader.preload_status_counts(users)
        # => %{"user_id_1" => 42, "user_id_2" => 15, ...}
    """
    def preload_status_counts(users) when is_list(users) do
      user_ids =
        users
        |> Enum.map(&Types.uid/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      if user_ids == [] do
        %{}
      else
        from(c in Bonfire.Data.Social.Created,
          join: p in Bonfire.Data.Social.Post,
          on: c.id == p.id,
          where: c.creator_id in ^user_ids,
          group_by: c.creator_id,
          select: {c.creator_id, count(c.id)}
        )
        |> repo().all()
        |> Map.new()
      end
    end

    def preload_status_counts(_), do: %{}

    @doc """
    Convenience function to batch load all account stats at once.

    Returns a tuple of {follow_counts_map, status_counts_map}

    ## Example

        {follow_counts, status_counts} = BatchLoader.preload_account_stats(users)
    """
    def preload_account_stats(users) when is_list(users) do
      {preload_follow_counts(users), preload_status_counts(users)}
    end

    def preload_account_stats(_), do: {%{}, %{}}

    @doc """
    Maps a list of users to Mastodon Account format with batch-loaded stats.

    This is the recommended way to map multiple accounts as it avoids N+1 queries.

    ## Options

    - `:current_user` - The current user (for relationship data)
    - `:skip_expensive_stats` - If true, skips loading stats entirely (default: false)

    ## Example

        accounts = BatchLoader.map_accounts(users, current_user: me)
    """
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
