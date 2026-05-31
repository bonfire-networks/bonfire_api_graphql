if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Status do
    @moduledoc """
    Maps Bonfire Activity/Post objects to Mastodon Status format.

    This module consolidates all status transformation logic that was previously
    scattered across multiple prepare_* functions. It handles:

    - Timeline statuses (from Activity objects)
    - Reblog/boost statuses (nested Post objects)
    - Notification statuses
    - Fallback statuses (when object data is incomplete)

    ## Usage

        # Timeline status
        Mappers.Status.from_activity(activity, current_user: user)

        # Reblog (nested in a boost)
        Mappers.Status.from_post(post, is_reblog: true)

        # Notification status
        Mappers.Status.from_post(post, for_notification: true, current_user: user)
    """

    use Bonfire.Common.Utils
    use Arrows
    import Untangle

    alias Bonfire.API.MastoCompat.Schemas
    alias Bonfire.API.MastoCompat.Helpers
    alias Bonfire.API.MastoCompat.Mappers
    alias Bonfire.Social.Activities

    import Helpers, only: [get_field: 2, get_fields: 2]

    @doc """
    Transform a Bonfire Activity into a Mastodon Status.

    ## Options

    - `:current_user` - The current user (for interaction states)
    - `:for_notification` - Set true when building status for notification
    - `:fallback` - Set true when object data may be incomplete

    ## Examples

        iex> from_activity(activity, current_user: user)
        %{"id" => "123", "content" => "Hello", ...}
    """
    def from_activity(%{node: activity}, opts), do: from_activity(activity, opts)

    def from_activity(activity, opts \\ []) do
      # Only the Ecto-struct (direct) path needs subject/creator preloading. GraphQL nodes are
      # string-keyed maps that already carry them, and would otherwise hit
      # `prepare_subject_and_creator`'s "unrecognised object format" error branch on every row.
      activity =
        if is_struct(activity) do
          Activities.prepare_subject_and_creator(activity, opts)
        else
          activity
        end

      # Check if this is an event activity
      if is_event_activity?(activity) do
        Bonfire.Social.Events.API.GraphQLMasto.EventsAdapter.build_event_status(activity, opts)
      else
        context = build_activity_context(activity, opts)

        status =
          if is_boost_activity?(context) do
            build_boost_status(context, opts)
          else
            build_regular_status(context, opts)
          end

        Helpers.validate_and_return(status, Schemas.Status)
      end
    end

    @doc """
    Transform a Bonfire Post into a Mastodon Status.

    Used for reblog scenarios where we have a Post object without the outer Activity.

    ## Options

    - `:is_reblog` - Set true when this Post is being nested in a reblog field
    - `:for_notification` - Set true when building status for notification
    - `:current_user` - The current user (for interaction states)
    """
    def from_post(post, opts \\ []) do
      context = build_post_context(post, opts)
      status = build_regular_status(context, opts)
      Helpers.validate_and_return(status, Schemas.Status)
    end

    @doc """
    Transform a GraphQL `:post` node map (from `Absinthe.run`, string-keyed) into a
    Mastodon Status. GraphQL-output mapper for REST-on-GraphQL endpoints
    (GRAPHQL_FIRST_MASTO_PLAN.md Phases 5–8): the query aliases its selections to
    snake_case keys matching the struct field names (`post_content`, `liked_by_me`, …)
    so the shared builders read them via `Helpers.get_field/2` with no shape-specific
    branching, letting struct-shaped `from_post/2` callers collapse into this shape.
    """
    def from_graphql(node, opts \\ [])
    def from_graphql(%{node: node}, opts), do: from_graphql(node, opts)
    def from_graphql(node, opts), do: from_post(node, opts)

    @doc """
    Like `from_graphql/2` but for an activity-shaped GraphQL node (feed or single-status
    resolver). Delegates to `from_activity/2`, which handles the boost/reblog wrapper. Use
    for timelines/single-status reads (boost must render as a reblog); use `from_graphql/2`
    for post-shaped nodes (favourites).
    """
    def from_graphql_activity(node, opts \\ []), do: from_activity(node, opts)

    defp build_activity_context(activity, _opts) do
      object = get_field(activity, :object)
      replied = get_field(activity, :replied)
      activity_id = get_field(activity, :id)
      object_id = get_field(activity, :object_id)

      uri =
        get_field(activity, :uri) ||
          get_field(object, :canonical_uri) ||
          Bonfire.Common.URIs.canonical_url(object, preload_if_needed: false) ||
          Bonfire.Common.URIs.canonical_url(activity, preload_if_needed: false) ||
          (object_id && "/post/#{object_id}") ||
          (activity_id && "/post/#{activity_id}")

      created_at =
        get_field(activity, :created_at) ||
          get_field(object, :created_at) ||
          (activity_id && Bonfire.Common.DatesTimes.date_from_pointer(activity_id))

      %{
        activity: activity,
        id: activity_id,
        created_at: created_at,
        uri: uri,
        object: object,
        object_id: object_id,
        object_post_content: get_field(activity, :object_post_content),
        subject: get_fields(activity, [:account, :subject]),
        verb: get_field(activity, :verb) |> get_field(:verb),
        verb_id: get_field(activity, :verb_id) || get_field(activity, :verb) |> get_field(:id),
        media: get_field(activity, :media) || [],
        replied: replied,
        in_reply_to_id: get_field(replied, :reply_to_id),
        in_reply_to_account_id: get_field(replied, :reply_to) |> get_field(:subject_id),
        liked_by_me: get_field(activity, :liked_by_me),
        boosted_by_me: get_field(activity, :boosted_by_me),
        bookmarked_by_me: get_field(activity, :bookmarked_by_me),
        like_count: get_field(activity, :like_count),
        boost_count: get_field(activity, :boost_count),
        # GraphQL exposes :replies_count directly; on the direct path it comes from
        # the Replied mixin's denormalized counters (synchronously maintained).
        replies_count: get_field(activity, :replies_count) || replied_replies_count(replied),
        # :tags from GraphQL, :tagged from Ecto mixin
        tags:
          get_field(activity, :tags) ||
            get_field(object, :tags) ||
            get_field(activity, :tagged) ||
            get_field(object, :tagged) ||
            []
      }
    end

    defp replied_replies_count(replied) do
      get_field(replied, :total_replies_count) ||
        get_field(replied, :direct_replies_count) ||
        get_field(replied, :nested_replies_count) || 0
    end

    defp build_post_context(post, _opts) do
      activity = get_field(post, :activity) || %{}
      post_content = get_field(post, :post_content) || %{}
      created = get_field(post, :created) || %{}
      post_id = get_field(post, :id)

      creator =
        get_field(post, :creator) ||
          get_field(activity, :creator) ||
          get_field(activity, :subject) ||
          get_field(created, :creator)

      created_at =
        get_field(activity, :created_at) ||
          get_field(post, :created_at) ||
          (post_id && Bonfire.Common.DatesTimes.date_from_pointer(post_id))

      uri =
        get_field(activity, :uri) ||
          get_field(post, :canonical_uri) ||
          (post_id && "/post/#{post_id}")

      %{
        post: post,
        activity: activity,
        id: post_id,
        created_at: created_at,
        uri: uri,
        post_content: post_content,
        creator: creator,
        media: get_field(post, :media) || get_field(activity, :media) || [],
        # Interaction flags / engagement counts: present when the post's `activity` was
        # resolved via GraphQL (e.g. the `myLikes` field). nil for the direct/Ecto path
        # (the post's activity isn't loaded), where add_interaction_states falls back to
        # `interaction_states` opts — so this is a no-op there.
        liked_by_me: get_field(activity, :liked_by_me),
        boosted_by_me: get_field(activity, :boosted_by_me),
        bookmarked_by_me: get_field(activity, :bookmarked_by_me),
        like_count: get_field(activity, :like_count),
        boost_count: get_field(activity, :boost_count),
        replies_count: get_field(activity, :replies_count),
        # :tags from GraphQL, :tagged from Ecto mixin
        tags:
          get_field(post, :tags) ||
            get_field(activity, :tags) ||
            get_field(post, :tagged) ||
            get_field(activity, :tagged) ||
            []
      }
    end

    defp is_boost_activity?(context) do
      boost_verb_id = Bonfire.Boundaries.Verbs.get_id!(:boost)
      # On the direct/Ecto path compare by verb_id; the "Announce" names cover the
      # GraphQL/ActivityPub shapes where only the verb name is available.
      context[:verb_id] == boost_verb_id or
        context[:verb] in ["Announce", "announce", "Boost", "boost", :boost, :announce]
    end

    defp build_boost_status(context, opts) do
      account = prepare_account(context[:subject], opts)
      reblog = extract_reblog(context, opts)

      Schemas.Status.new(%{
        "id" => context[:id],
        "created_at" => context[:created_at],
        "uri" => context[:uri],
        "url" => context[:uri],
        "account" => account,
        "content" => "",
        "reblog" => reblog,
        "reblogged" => true
      })
    end

    def build_regular_status(context, opts) do
      account = extract_account(context, opts)
      content_data = extract_content(context)
      media_attachments = Mappers.MediaAttachment.from_media_list(context[:media])
      object_id = context[:object_id] || context[:id]
      mentions = extract_mentions(object_id, context, opts)

      base_status =
        Schemas.Status.new(%{
          "id" => object_id,
          "created_at" => context[:created_at],
          "uri" => context[:uri],
          "url" => context[:uri],
          "account" => account,
          "name" => content_data.name,
          "content" => content_data.html,
          "text" => content_data.text,
          "spoiler_text" => content_data.spoiler_text,
          "media_attachments" => media_attachments,
          "mentions" => mentions,
          "tags" => extract_hashtags(object_id, opts),
          "in_reply_to_id" => context[:in_reply_to_id],
          "in_reply_to_account_id" => context[:in_reply_to_account_id],
          "favourites_count" => context[:like_count] || 0,
          "reblogs_count" => context[:boost_count] || 0,
          "replies_count" => context[:replies_count] || 0,
          "visibility" => map_visibility(object_id, opts),
          # Bonfire has no separate sensitivity flag; a content warning marks it sensitive.
          "sensitive" => content_data.spoiler_text not in [nil, ""]
        })

      add_interaction_states(
        base_status,
        object_id,
        context,
        Keyword.get(opts, :current_user),
        Keyword.get(opts, :interaction_states),
        opts
      )
      |> maybe_add_poll(context, opts)
    end

    # The feed query carries only the object's `__typename` for poll detection, so load the full
    # `Bonfire.Poll.Question` (choices + post_content + voting_dates) and reuse the struct-based
    # `Mappers.Poll.from_question` — same supplementary-load pattern reblogs use. Only fires for
    # the (rare) poll rows; the feed itself stays on GraphQL.
    defp maybe_add_poll(status, context, opts) do
      object = context[:object]
      object_id = context[:object_id] || context[:id]

      if poll_object?(object) and object_id do
        current_user = Keyword.get(opts, :current_user)

        case load_poll_question(object_id, current_user) do
          nil ->
            status

          question ->
            Map.put(
              status,
              "poll",
              Mappers.Poll.from_question(question, current_user: current_user)
            )
        end
      else
        status
      end
    end

    defp poll_object?(object) do
      get_field(object, :__typename) == "Poll" or Mappers.Poll.is_poll?(object)
    end

    defp load_poll_question(object_id, current_user) do
      Bonfire.Poll.Questions.read(object_id, current_user)
      |> case do
        {:ok, question} -> with_choice_vote_counts(question, current_user)
        question when is_struct(question) -> with_choice_vote_counts(question, current_user)
        _ -> nil
      end
    rescue
      _ -> nil
    end

    # `Mappers.Poll` reads `choice.votes_count` (computed, not stored), so populate it per choice
    # from the canonical join-based `preview_vote_state_for_question/2` (same aggregate the web
    # preview uses). Choices returned as plain maps so the mapper's `e/3` reads the added :votes_count.
    defp with_choice_vote_counts(question, current_user) do
      counts =
        Bonfire.Poll.Votes.preview_vote_state_for_question(question, current_user)
        |> Map.get(:counts_by_choice_id, %{})

      choices =
        (Map.get(question, :choices) || [])
        |> Enum.map(fn choice ->
          cid = Map.get(choice, :id)
          choice |> choice_to_map() |> Map.put(:votes_count, Map.get(counts, cid, 0))
        end)

      Map.put(question, :choices, choices)
    end

    defp choice_to_map(%_{} = choice), do: Map.from_struct(choice)
    defp choice_to_map(choice) when is_map(choice), do: choice

    defp extract_hashtags(nil, _opts), do: []

    defp extract_hashtags(object_id, opts) do
      case Map.get(Keyword.get(opts, :hashtags_by_object, %{}), object_id) do
        hashtags when is_list(hashtags) ->
          hashtags
          |> Enum.map(&Mappers.Tag.from_hashtag(&1, []))
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    end

    defp extract_mentions(nil, _context, _opts), do: []

    defp extract_mentions(object_id, context, opts) do
      mentions_by_object = Keyword.get(opts, :mentions_by_object, %{})
      current_user = Keyword.get(opts, :current_user)

      case Map.get(mentions_by_object, object_id) do
        raw_mentions when is_list(raw_mentions) and raw_mentions != [] ->
          Mappers.Mention.from_tags(raw_mentions, current_user: current_user)

        [] ->
          []

        nil ->
          extract_mentions_from_context_tags(context, current_user, opts)
      end
    end

    defp extract_mentions_from_context_tags(context, current_user, opts \\ []) do
      post = context[:post]
      tags = context[:tags] || []

      cond do
        Keyword.get(opts, :lightweight, false) ->
          # Skip DB query for tags in lightweight mode (streaming)
          if is_list(tags) and tags != [] do
            Mappers.Mention.from_tags(tags, current_user: current_user)
          else
            []
          end

        is_struct(post) ->
          loaded_tags = Bonfire.Social.Tags.list_tags_mentions(post, current_user)
          Mappers.Mention.from_tags(loaded_tags, current_user: current_user)

        is_list(tags) and tags != [] ->
          Mappers.Mention.from_tags(tags, current_user: current_user)

        true ->
          []
      end
    end

    defp add_interaction_states(
           status,
           object_id,
           context,
           current_user,
           interaction_states \\ nil,
           opts \\ []
         ) do
      favourited = context[:liked_by_me]
      reblogged = context[:boosted_by_me]
      bookmarked = context[:bookmarked_by_me]

      if is_boolean(favourited) && is_boolean(reblogged) && is_boolean(bookmarked) do
        status
        |> Map.put("favourited", favourited)
        |> Map.put("reblogged", reblogged)
        |> Map.put("bookmarked", bookmarked)
      else
        lightweight? = Keyword.get(opts, :lightweight, false)

        case interaction_states do
          %{^object_id => states} when is_map(states) ->
            status
            |> Map.put("favourited", Map.get(states, :favourited, false))
            |> Map.put("reblogged", Map.get(states, :reblogged, false))
            |> Map.put("bookmarked", Map.get(states, :bookmarked, false))

          _ when current_user != nil and object_id != nil ->
            if lightweight? do
              status
              |> Map.put("favourited", false)
              |> Map.put("reblogged", false)
              |> Map.put("bookmarked", false)
            else
              favourited = Bonfire.Social.Likes.liked?(current_user, object_id) || false
              reblogged = Bonfire.Social.Boosts.boosted?(current_user, object_id) || false
              bookmarked = Bonfire.Social.Bookmarks.bookmarked?(current_user, object_id) || false

              status
              |> Map.put("favourited", favourited)
              |> Map.put("reblogged", reblogged)
              |> Map.put("bookmarked", bookmarked)
            end

          _ ->
            status
            |> Map.put("favourited", false)
            |> Map.put("reblogged", false)
            |> Map.put("bookmarked", false)
        end
      end
    end

    # The original post a boost wraps. On the direct path the boost activity's `object` is
    # that post (or a Boost mixin whose edge points to it), but often only partially loaded
    # (no creator) — so resolve its id and load it fully (boundary-aware) for account + content.
    defp extract_reblog(context, opts) do
      reblog_opts = Keyword.merge(opts, is_reblog: true)
      object = context[:object]

      cond do
        full_post?(object) ->
          from_post(object, reblog_opts)

        reblog_id = reblog_object_id(context) ->
          # Safety net only: the feed/single-status preloads (:with_creator) normally
          # provide the boosted post fully, so this per-item load should not fire.
          debug(reblog_id, "reblog post not preloaded; loading per-item")

          case Bonfire.Social.Objects.read(reblog_id,
                 current_user: Keyword.get(opts, :current_user),
                 preload: [:with_post_content, :with_creator, :with_media]
               ) do
            {:ok, post} -> from_post(post, reblog_opts)
            _ -> nil
          end

        true ->
          nil
      end
    end

    # Id of the original post being boosted.
    defp reblog_object_id(context) do
      object = context[:object]

      cond do
        is_struct(object, Bonfire.Data.Social.Boost) or get_field(object, :__typename) == "Boost" ->
          edge = get_field(object, :edge)
          get_field(edge, :object_id) || get_field(get_field(edge, :object), :id)

        true ->
          # boost activity's object is the original post itself
          context[:object_id] || get_field(object, :id)
      end
    end

    # A post we can render directly without another query: has both content and a
    # loaded creator/subject for the account.
    defp full_post?(%Ecto.Association.NotLoaded{}), do: false

    defp full_post?(post) when is_map(post) do
      not is_nil(get_field(post, :post_content)) and
        (present?(get_field(post, :creator)) or
           present?(get_field(post, :created) |> get_field(:creator)) or
           present?(get_field(get_field(post, :activity), :subject)))
    end

    defp full_post?(_), do: false

    defp present?(nil), do: false
    defp present?(%Ecto.Association.NotLoaded{}), do: false
    defp present?(_), do: true

    defp extract_account(context, opts) do
      user_data =
        context[:subject] ||
          context[:creator] ||
          get_field(context[:activity], :account) ||
          get_field(context[:activity], :subject)

      prepare_account(user_data, opts)
    end

    defp prepare_account(nil, _opts), do: nil
    defp prepare_account(%Ecto.Association.NotLoaded{}, _opts), do: nil

    defp prepare_account(user_data, _opts) do
      case Mappers.Account.from_user(user_data, skip_expensive_stats: true) do
        nil ->
          nil

        account ->
          Helpers.deep_struct_to_map(account, filter_nils: true, drop_unknown_structs: true)
      end
    end

    defp map_visibility(object_id, opts) do
      cond do
        Keyword.get(opts, :for_conversation, false) ->
          "direct"

        is_nil(object_id) ->
          "public"

        Keyword.get(opts, :lightweight, false) and
            not Keyword.has_key?(opts, :visibility_by_object) ->
          # In lightweight mode without pre-loaded visibility data, default to public
          "public"

        true ->
          # Check batch-loaded data first, fall back to individual query
          visibility_by_object = Keyword.get(opts, :visibility_by_object, %{})

          acl_ids =
            Map.get(visibility_by_object, object_id) ||
              Bonfire.Boundaries.Controlleds.list_preset_acl_ids_on_object(object_id)

          # For private vs direct distinction, check followers grants
          followers_grant_objects = Keyword.get(opts, :followers_grant_objects, nil)

          acl_ids_to_visibility(acl_ids, object_id, followers_grant_objects)
      end
    end

    defp acl_ids_to_visibility(acl_ids, object_id, followers_grant_objects)
         when is_struct(acl_ids, MapSet) do
      if MapSet.size(acl_ids) == 0 do
        # No preset ACLs = mentions-only or followers-only
        # Check if the object has a grant to the followers circle to distinguish
        has_followers =
          cond do
            is_struct(followers_grant_objects, MapSet) ->
              MapSet.member?(followers_grant_objects, object_id)

            not is_nil(object_id) ->
              Bonfire.Boundaries.Controlleds.object_has_followers_grant?(object_id)

            true ->
              false
          end

        if has_followers, do: "private", else: "direct"
      else
        remote_ids = MapSet.new(Bonfire.Boundaries.Acls.remote_public_acl_ids())
        has_remote = not MapSet.disjoint?(acl_ids, remote_ids)

        preset_acls = Bonfire.Common.Config.get!(:preset_acls_match)
        public_ids = MapSet.new(Bonfire.Boundaries.Acls.preset_acl_ids("public", preset_acls))
        local_ids = MapSet.new(Bonfire.Boundaries.Acls.preset_acl_ids("local", preset_acls))
        has_public = not MapSet.disjoint?(acl_ids, public_ids)
        has_local = not MapSet.disjoint?(acl_ids, local_ids)

        cond do
          has_remote -> "public"
          has_public -> "unlisted"
          has_local -> "unlisted"
          true -> "direct"
        end
      end
    end

    defp acl_ids_to_visibility(_, _, _), do: "public"

    defp extract_content(context) do
      post_content =
        context[:post_content] ||
          context[:object_post_content] ||
          get_field(context[:object], :post_content) ||
          %{}

      raw_content =
        get_field(post_content, :content) ||
          get_field(post_content, :html_body) ||
          ""

      # Convert markdown to HTML if needed (matches GraphQL resolver behavior)
      # When loaded via GraphQL, html_body goes through a resolver that calls maybe_markdown_to_html
      # When loaded via Ecto directly (e.g., InteractionHandler for boost/like), we get raw DB value
      html =
        if is_binary(raw_content) and raw_content != "" do
          Bonfire.Common.Text.maybe_markdown_to_html(raw_content, sanitize: true)
        else
          raw_content
        end

      text =
        get_field(post_content, :name) ||
          strip_html_tags(html)

      name = get_field(post_content, :name)
      spoiler_text = get_field(post_content, :summary) || ""

      %{
        html: html,
        text: text,
        name: name,
        spoiler_text: spoiler_text
      }
    end

    defp strip_html_tags(html) when is_binary(html) do
      html
      |> String.replace(~r/<[^>]+>/, "")
      |> String.trim()
    end

    defp strip_html_tags(_), do: ""

    # Event detection and handling

    defp is_event_activity?(activity) do
      object = get_field(activity, :object)
      typename = get_field(object, :__typename)

      if typename == "Other" do
        get_field(object, :json)
        |> is_event_json?()
      else
        false
      end
    end

    defp is_event_json?(json) when is_map(json) do
      case json do
        %{"object" => %{"type" => "Event"}} -> true
        %{"type" => "Event"} -> true
        _ -> false
      end
    end

    defp is_event_json?(_), do: false
  end
end
