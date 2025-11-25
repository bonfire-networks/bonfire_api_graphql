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

    import Helpers, only: [get_field: 2]

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
    # Handle edge nodes
    def from_activity(%{node: activity}, opts), do: from_activity(activity, opts)

    def from_activity(activity, opts \\ []) do
      # Ensure subject and creator are properly loaded (handles NotLoaded associations)
      activity = Activities.prepare_subject_and_creator(activity, opts)

      context = build_activity_context(activity, opts)

      # Determine if this is a boost/reblog
      is_boost = is_boost_activity?(context)

      status =
        if is_boost do
          # This is a boost - build status with nested reblog
          build_boost_status(context, opts)
        else
          # Regular status
          build_regular_status(context, opts)
        end

      # Validate before returning
      validate_and_return(status)
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
      validate_and_return(status)
    end

    # Private functions

    defp build_activity_context(activity, _opts) do
      object = get_field(activity, :object)
      replied = get_field(activity, :replied)

      %{
        activity: activity,
        id: get_field(activity, :id),
        created_at: get_field(activity, :created_at),
        uri: get_field(activity, :uri),
        object: object,
        object_id: get_field(activity, :object_id),
        object_post_content: get_field(activity, :object_post_content),
        subject: get_field(activity, :account) || get_field(activity, :subject),
        verb: get_field(activity, :verb) |> get_field(:verb),
        media: get_field(activity, :media) || [],
        # Extract reply-to information for threading
        replied: replied,
        in_reply_to_id: get_field(replied, :reply_to_id),
        in_reply_to_account_id: get_field(replied, :reply_to) |> get_field(:subject_id),
        # Extract interaction flags from GraphQL (Dataloader-batched)
        liked_by_me: get_field(activity, :liked_by_me),
        boosted_by_me: get_field(activity, :boosted_by_me),
        bookmarked_by_me: get_field(activity, :bookmarked_by_me),
        # Extract engagement counts from GraphQL (from EdgeTotal system)
        like_count: get_field(activity, :like_count),
        boost_count: get_field(activity, :boost_count),
        replies_count: get_field(activity, :replies_count)
      }
    end

    defp build_post_context(post, _opts) do
      activity = get_field(post, :activity) || %{}
      post_content = get_field(post, :post_content) || %{}
      created = get_field(post, :created) || %{}
      post_id = get_field(post, :id)

      # Extract creator: try activity associations first, then Created mixin
      creator =
        get_field(activity, :creator) ||
          get_field(activity, :subject) ||
          get_field(created, :creator)

      # Extract created_at: try activity first, then post, then extract from ULID
      # Note: DatesTimes.date_from_pointer extracts timestamp from ULID without DB query
      created_at =
        get_field(activity, :created_at) ||
          get_field(post, :created_at) ||
          (post_id && Bonfire.Common.DatesTimes.date_from_pointer(post_id))

      # Extract URI: try activity first, then post canonical_uri, then construct from ID
      # Note: We construct a simple path to avoid N+1 queries from URIs.path/1
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
        media: get_field(post, :media) || get_field(activity, :media) || []
      }
    end

    defp is_boost_activity?(context) do
      verb_id = context[:verb]
      # Check if verb is boost/announce
      boost_verb_id = Bonfire.Boundaries.Verbs.get_id!(:boost)
      verb_id == boost_verb_id || verb_id == "Announce" || verb_id == "announce"
    end

    defp build_boost_status(context, opts) do
      # Extract the account who boosted
      account = prepare_account(context[:subject], opts)

      # Get the nested reblog
      reblog = extract_reblog(context, opts)

      # Build minimal status for the boost itself
      Schemas.Status.new(%{
        "id" => context[:id],
        "created_at" => context[:created_at],
        "uri" => context[:uri],
        "url" => context[:uri],
        "account" => account,
        # Boosts don't have content, just reference
        "content" => "",
        "reblog" => reblog,
        # User boosted this
        "reblogged" => true
      })
    end

    defp build_regular_status(context, opts) do
      # Extract data from context
      account = extract_account(context, opts)
      content_data = extract_content(context)
      media_attachments = prepare_media_attachments(context[:media])
      object_id = context[:id] || context[:object_id]

      # Build base status
      base_status =
        Schemas.Status.new(%{
          "id" => object_id,
          "created_at" => context[:created_at],
          "uri" => context[:uri],
          "url" => context[:uri],
          "account" => account,
          "content" => content_data.html,
          "text" => content_data.text,
          "spoiler_text" => content_data.spoiler_text,
          "media_attachments" => media_attachments,
          # Threading fields for conversation display
          "in_reply_to_id" => context[:in_reply_to_id],
          "in_reply_to_account_id" => context[:in_reply_to_account_id],
          # Engagement counts (from EdgeTotal system via GraphQL)
          "favourites_count" => context[:like_count] || 0,
          "reblogs_count" => context[:boost_count] || 0,
          "replies_count" => context[:replies_count] || 0,
          # TODO: Map actual visibility from Bonfire boundaries
          "visibility" => "public",
          # TODO: Map actual sensitive flag
          "sensitive" => false
        })

      # Add interaction states
      # Priority: 1) Dataloader results from context, 2) manual batch loading, 3) fallback queries
      add_interaction_states(
        base_status,
        object_id,
        context,
        Keyword.get(opts, :current_user),
        Keyword.get(opts, :interaction_states)
      )
    end

    # Add interaction states for current user
    # Priority:
    # 1. Dataloader results from GraphQL context (liked_by_me, boosted_by_me, bookmarked_by_me)
    # 2. Manual batch loading via interaction_states map
    # 3. Fallback to individual queries (backward compatibility, causes N+1)
    defp add_interaction_states(
           status,
           object_id,
           context,
           current_user,
           interaction_states \\ nil
         ) do
      # First, try to get flags from Dataloader results in context
      favourited = context[:liked_by_me]
      reblogged = context[:boosted_by_me]
      bookmarked = context[:bookmarked_by_me]

      # If Dataloader provided boolean values, use them (most efficient)
      if is_boolean(favourited) && is_boolean(reblogged) && is_boolean(bookmarked) do
        status
        |> Map.put("favourited", favourited)
        |> Map.put("reblogged", reblogged)
        |> Map.put("bookmarked", bookmarked)
      else
        # Fallback to manual batch loading or individual queries
        case interaction_states do
          %{^object_id => states} when is_map(states) ->
            # Use manually batch-loaded states (no queries)
            status
            |> Map.put("favourited", Map.get(states, :favourited, false))
            |> Map.put("reblogged", Map.get(states, :reblogged, false))
            |> Map.put("bookmarked", Map.get(states, :bookmarked, false))

          _ ->
            # Last resort: individual queries (backward compatibility, causes N+1)
            if current_user && object_id do
              try do
                favourited = Bonfire.Social.Likes.liked?(current_user, object_id) || false
                reblogged = Bonfire.Social.Boosts.boosted?(current_user, object_id) || false

                bookmarked =
                  Bonfire.Social.Bookmarks.bookmarked?(current_user, object_id) || false

                status
                |> Map.put("favourited", favourited)
                |> Map.put("reblogged", reblogged)
                |> Map.put("bookmarked", bookmarked)
              rescue
                # If any check fails (e.g., module not available), return status unchanged
                _ -> status
              end
            else
              status
            end
        end
      end
    end

    defp extract_reblog(context, opts) do
      object = context[:object]

      case get_field(object, :__typename) do
        "Boost" ->
          # Double-nested boost - unwrap
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
      # Try different fields depending on context type
      user_data =
        context[:subject] ||
          context[:creator] ||
          get_field(context[:activity], :account) ||
          get_field(context[:activity], :subject)

      prepare_account(user_data, opts)
    end

    defp prepare_account(nil, _opts), do: nil

    # NotLoaded associations are now handled by Activities.prepare_subject_and_creator
    # which is called at the start of from_activity
    defp prepare_account(%Ecto.Association.NotLoaded{}, _opts), do: nil

    defp prepare_account(user_data, _opts) do
      # Delegate to Account mapper - single source of truth for account normalization
      # This ensures all account preparation uses the same normalization path
      # (handles both GraphQL data and raw Ecto structs with profile/character associations)
      case Mappers.Account.from_user(user_data) do
        nil -> nil
        account -> deep_clean_structs(account)
      end
    end

    # Recursively remove or convert any remaining structs to prevent serialization errors
    defp deep_clean_structs(value) when is_struct(value) do
      # Convert Ecto NotLoaded to nil, other structs to maps (but skip them for safety)
      case value do
        %Ecto.Association.NotLoaded{} -> nil
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        %NaiveDateTime{} = dt -> NaiveDateTime.to_iso8601(dt)
        %Date{} = d -> Date.to_iso8601(d)
        # Skip other structs entirely (they shouldn't be in the output)
        _ -> nil
      end
    end

    defp deep_clean_structs(value) when is_map(value) do
      value
      |> Enum.map(fn {k, v} -> {k, deep_clean_structs(v)} end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end

    defp deep_clean_structs(value) when is_list(value) do
      value
      |> Enum.map(&deep_clean_structs/1)
      |> Enum.reject(&is_nil/1)
    end

    defp deep_clean_structs(value), do: value

    defp extract_content(context) do
      # Get content from different possible sources
      post_content =
        context[:post_content] ||
          context[:object_post_content] ||
          get_field(context[:object], :post_content) ||
          %{}

      html =
        get_field(post_content, :content) ||
          get_field(post_content, :html_body) ||
          ""

      text =
        get_field(post_content, :name) ||
          strip_html_tags(html)

      spoiler_text = get_field(post_content, :summary) || ""

      %{
        html: html,
        text: text,
        spoiler_text: spoiler_text
      }
    end

    # Helper to strip HTML tags for plain text version
    defp strip_html_tags(html) when is_binary(html) do
      html
      |> String.replace(~r/<[^>]+>/, "")
      |> String.trim()
    end

    defp strip_html_tags(_), do: ""

    # Media attachment transformation
    defp prepare_media_attachments(nil), do: []
    defp prepare_media_attachments([]), do: []

    defp prepare_media_attachments(media) when is_list(media) do
      media
      |> Enum.map(&prepare_media_attachment/1)
      |> Enum.reject(&is_nil/1)
    end

    defp prepare_media_attachments(_other), do: []

    defp prepare_media_attachment(media) when is_map(media) do
      media_type = get_field(media, :media_type) || "unknown"

      # Determine Mastodon media type from MIME type
      type =
        cond do
          String.starts_with?(media_type, "image/") -> "image"
          String.starts_with?(media_type, "video/") -> "video"
          String.starts_with?(media_type, "audio/") -> "audio"
          true -> "unknown"
        end

      %{
        "id" => get_field(media, :id) || "",
        "type" => type,
        "url" => get_field(media, :url) || get_field(media, :path) || "",
        "preview_url" => get_field(media, :url) || get_field(media, :path) || "",
        "remote_url" => nil,
        "meta" => %{},
        "description" => get_field(media, :description) || get_field(media, :label) || "",
        "blurhash" => nil
      }
    end

    defp prepare_media_attachment(_), do: nil

    # Validate status against schema before returning
    defp validate_and_return(nil), do: nil

    defp validate_and_return(status) do
      case Schemas.Status.validate(status) do
        {:ok, valid_status} ->
          valid_status

        {:error, {:missing_fields, fields}} ->
          warn("Status missing required fields: #{inspect(fields)}, status: #{inspect(status)}")
          nil

        {:error, reason} ->
          warn("Status validation failed: #{inspect(reason)}")
          nil
      end
    end
  end
end
