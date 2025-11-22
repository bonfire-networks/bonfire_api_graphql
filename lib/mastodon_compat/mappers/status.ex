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
    alias Bonfire.Me.API.GraphQLMasto.Adapter, as: MeAdapter

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
      context = build_activity_context(activity, opts)

      # Determine if this is a boost/reblog
      is_boost = is_boost_activity?(context)

      if is_boost do
        # This is a boost - build status with nested reblog
        build_boost_status(context, opts)
      else
        # Regular status
        build_regular_status(context, opts)
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
      build_regular_status(context, opts)
    end

    # Private functions

    defp build_activity_context(activity, _opts) do
      object = get_field(activity, :object)

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
        media: get_field(activity, :media) || []
      }
    end

    defp build_post_context(post, _opts) do
      activity = get_field(post, :activity) || %{}
      post_content = get_field(post, :post_content) || %{}

      %{
        post: post,
        activity: activity,
        id: get_field(post, :id),
        created_at: get_field(activity, :created_at) || get_field(post, :created_at),
        uri: get_field(activity, :uri) || get_field(post, :canonical_uri),
        post_content: post_content,
        creator: get_field(activity, :creator) || get_field(activity, :subject),
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
      IO.inspect(context[:media], label: "Media cazz")
      account = extract_account(context, opts)
      content_data = extract_content(context)
      media_attachments = prepare_media_attachments(context[:media])

      # Build base status
      Schemas.Status.new(%{
        "id" => context[:id] || context[:object_id],
        "created_at" => context[:created_at],
        "uri" => context[:uri],
        "url" => context[:uri],
        "account" => account,
        "content" => content_data.html,
        "text" => content_data.text,
        "spoiler_text" => content_data.spoiler_text,
        "media_attachments" => media_attachments,
        # TODO: Map actual visibility from Bonfire boundaries
        "visibility" => "public",
        # TODO: Map actual sensitive flag
        "sensitive" => false
      })
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

    defp prepare_account(user_data, _opts) do
      case user_data do
        %{} = user when map_size(user) > 0 ->
          prepared = Utils.maybe_apply(MeAdapter, :prepare_user, user, fallback_return: user)

          # Validate has required ID field
          if is_map(prepared) &&
               (Map.has_key?(prepared, :id) || Map.has_key?(prepared, "id")) do
            prepared
          else
            nil
          end

        _ ->
          nil
      end
    end

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
      IO.inspect(media, label: "Media Attachment cazz")
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

    # Helper to safely get nested fields
    defp get_field(nil, _field), do: nil
    defp get_field(data, field) when is_map(data), do: Map.get(data, field)
    defp get_field(_, _), do: nil
  end
end
