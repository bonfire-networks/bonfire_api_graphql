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
      activity = Activities.prepare_subject_and_creator(activity, opts)

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
        media: get_field(activity, :media) || [],
        replied: replied,
        in_reply_to_id: get_field(replied, :reply_to_id),
        in_reply_to_account_id: get_field(replied, :reply_to) |> get_field(:subject_id),
        liked_by_me: get_field(activity, :liked_by_me),
        boosted_by_me: get_field(activity, :boosted_by_me),
        bookmarked_by_me: get_field(activity, :bookmarked_by_me),
        like_count: get_field(activity, :like_count),
        boost_count: get_field(activity, :boost_count),
        replies_count: get_field(activity, :replies_count),
        # :tags from GraphQL, :tagged from Ecto mixin
        tags:
          get_field(activity, :tags) ||
            get_field(object, :tags) ||
            get_field(activity, :tagged) ||
            get_field(object, :tagged) ||
            []
      }
    end

    defp build_post_context(post, _opts) do
      activity = get_field(post, :activity) || %{}
      post_content = get_field(post, :post_content) || %{}
      created = get_field(post, :created) || %{}
      post_id = get_field(post, :id)

      creator =
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
      verb_id = context[:verb]
      boost_verb_id = Bonfire.Boundaries.Verbs.get_id!(:boost)
      verb_id == boost_verb_id || verb_id == "Announce" || verb_id == "announce"
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
          "in_reply_to_id" => context[:in_reply_to_id],
          "in_reply_to_account_id" => context[:in_reply_to_account_id],
          "favourites_count" => context[:like_count] || 0,
          "reblogs_count" => context[:boost_count] || 0,
          "replies_count" => context[:replies_count] || 0,
          "visibility" => map_visibility(object_id, opts),
          "sensitive" => false
        })

      add_interaction_states(
        base_status,
        object_id,
        context,
        Keyword.get(opts, :current_user),
        Keyword.get(opts, :interaction_states),
        opts
      )
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

    defp extract_reblog(context, opts) do
      object = context[:object]

      case get_field(object, :__typename) do
        "Boost" ->
          edge = get_field(object, :edge)
          original_post = get_field(edge, :object)

          if get_field(original_post, :__typename) == "Post" do
            from_post(original_post, Keyword.merge(opts, is_reblog: true))
          else
            nil
          end

        "Post" ->
          from_post(object, Keyword.merge(opts, is_reblog: true))

        _ ->
          nil
      end
    end

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
