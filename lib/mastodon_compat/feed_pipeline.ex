if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.FeedPipeline do
    @moduledoc """
    Masto-API preload specs (`feed_preloads/0`, `postload_preloads/0`,
    `single_status_preloads/0`): the single source of truth for which associations
    the Mastodon read paths preload, reused by the GraphQL resolvers (`social_api_graphql.ex`).
    """

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
      :with_replied,
      # the activity's tags, which `mentions` and `hashtags` read; `Objects.read` cannot load them in its query, so `status`/`statuses` postload them (`with_tags/2`)
      :tags,
      # tree.parent, the group or topic the post was published in (`context_id`)
      :with_parent
    ]

    @doc "Preloads requested from the feed query (single source of truth for read endpoints)."
    def feed_preloads, do: @feed_preloads

    @doc "Preloads applied after the feed query (e.g. media)."
    def postload_preloads, do: @postload_preloads

    @doc "Preloads for loading a single status by id."
    def single_status_preloads, do: @single_status_preloads
  end
end
