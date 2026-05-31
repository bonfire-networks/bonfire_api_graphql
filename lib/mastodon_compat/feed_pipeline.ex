if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.FeedPipeline do
    @moduledoc """
    Masto-API feed preload specs + a direct (non-GraphQL) feed loader.

      * **Preload specs** (`feed_preloads/0`, `postload_preloads/0`,
        `single_status_preloads/0`) — single source of truth for which associations
        the Mastodon read paths preload, reused by the GraphQL resolvers
        (`social_api_graphql.ex`) and the direct single-status read.

      * **`load/3`** — a direct `FeedActivities.feed` loader. NOT the production read
        path (production timelines/notifications go through the GraphQL Schema via
        `Absinthe.run`, see GRAPHQL_FIRST_MASTO_PLAN.md); kept only as the variant-A
        direct baseline for the perf benchmark (`feed_benchmark_test.exs`, `@tag :benchmark`).
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.Social.FeedActivities
    alias Bonfire.Social.Activities

    # `:with_creator` loads the object's creator (e.g. the author of a boosted post)
    # batched in the feed query, so reblogs carry their account without a per-item lookup.
    @feed_preloads [
      :with_subject,
      :with_creator,
      :with_object_more,
      :with_post_content,
      :with_replied
    ]
    # Applied after loading (media isn't part of the base feed query).
    @postload_preloads [:with_media]
    # Single-status read: richer than the feed set (creator, reply-to, object peering).
    @single_status_preloads [
      :with_subject,
      :with_creator,
      :with_media,
      :with_object_more,
      :with_object_peered,
      :with_reply_to,
      # carries the Replied mixin's denormalized reply counts (replies_count)
      :with_replied
    ]

    @doc "Preloads requested from the feed query (single source of truth for read endpoints)."
    def feed_preloads, do: @feed_preloads

    @doc "Preloads applied after the feed query (e.g. media)."
    def postload_preloads, do: @postload_preloads

    @doc "Preloads for loading a single status by id."
    def single_status_preloads, do: @single_status_preloads

    @doc """
    Load a feed and return its activities.

    `params` is the map produced by
    `Bonfire.API.MastoCompat.PaginationHelpers.build_feed_params/3` — i.e. it
    carries a `:filter` map plus `:first`/`:last`/`:after`/`:before` pagination
    keys.

    ## Options

    - `:feed_preloads` — override the preloads requested from the feed query
    - `:postload_preloads` — override the post-load preloads
    - `:default_pagination` — pagination args when none are given (default `%{first: 20}`)

    Returns `{:ok, activities, page_info}`, `{:ok, [], %{}}` for an empty/unknown
    feed shape, or `{:error, reason}`.
    """
    def load(params, current_user, opts \\ []) do
      filters =
        params
        |> Map.get(:filter, Map.get(params, "filter", %{}))
        |> normalize_feed_filters()
        |> maybe_force_local_origin()

      feed_name =
        Bonfire.Common.Types.maybe_to_atom(
          Map.get(filters, :feed_name) || Map.get(filters, "feed_name") ||
            Bonfire.Social.FeedLoader.feed_name_or_default(:default, current_user)
        )

      pagination_args =
        case Map.take(params, [:first, :last, :after, :before]) do
          empty when map_size(empty) == 0 -> Keyword.get(opts, :default_pagination, %{first: 20})
          args -> args
        end

      FeedActivities.feed(
        feed_name,
        filters,
        [
          current_user: current_user,
          paginate: pagination_args,
          preload: Keyword.get(opts, :feed_preloads, @feed_preloads)
        ] ++ Keyword.get(opts, :extra_feed_opts, [])
      )
      |> handle_feed_result(current_user, opts)
    end

    defp handle_feed_result({:error, _} = error, _current_user, _opts), do: error

    defp handle_feed_result(%{edges: edges, page_info: page_info}, current_user, opts)
         when is_list(edges) do
      activities =
        edges
        |> Activities.activity_preloads(Keyword.get(opts, :postload_preloads, @postload_preloads),
          current_user: current_user,
          skip_boundary_check: true,
          preload_nested: {[:activity], []}
        )
        |> Enum.map(fn edge -> Map.get(edge, :activity, edge) end)

      {:ok, activities, page_info}
    end

    defp handle_feed_result(other, _current_user, _opts) do
      debug(other, "FeedPipeline: unexpected feed result shape, returning empty")
      {:ok, [], %{}}
    end

    @doc "Object IDs for a list of loaded activities (deduplicated, nils dropped)."
    def object_ids(activities) when is_list(activities) do
      activities
      |> Enum.map(&Map.get(&1, :object_id))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
    end

    @doc """
    Normalize a Mastodon filter map (string keys from query params) into the atom
    keys that `Bonfire.Social` feed filters expect.
    """
    def normalize_feed_filters(filters) when is_map(filters) do
      key_names = feed_filter_key_names()

      Map.new(filters, fn
        {key, value} when is_binary(key) -> {Map.get(key_names, key, key), value}
        pair -> pair
      end)
    end

    def normalize_feed_filters(_), do: %{}

    # Built at runtime (not as a module attribute) to avoid a compile-time
    # dependency on bonfire_social from this extension.
    defp feed_filter_key_names do
      Map.new(Bonfire.Social.API.GraphQL.feed_filter_keys(), &{to_string(&1), &1})
    end

    defp maybe_force_local_origin(%{feed_name: feed_name} = filters)
         when feed_name in [:local, "local"] do
      Map.put_new(filters, :origin, :local)
    end

    defp maybe_force_local_origin(filters), do: filters
  end
end
