if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Notification do
    @moduledoc """
    Maps Bonfire Activity objects to Mastodon Notification format.

    Handles transformation of Bonfire activities into Mastodon-compatible notifications,
    including mapping verb IDs to notification types and conditionally including status objects.

    ## Notification Types

    Per Mastodon API spec:
    - `follow` - Someone followed you
    - `follow_request` - Someone requested to follow you
    - `mention` - Someone mentioned you in their status
    - `reblog` - Someone boosted one of your statuses
    - `favourite` - Someone favourited one of your statuses
    - `poll` - A poll you have voted in or created has ended
    - `status` - Someone you enabled notifications for has posted
    - `update` - A status you interacted with has been edited

    ## Usage

        Mappers.Notification.from_activity(activity, current_user: user)
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.{Schemas, Mappers, Helpers}

    import Helpers, only: [get_field: 2]

    @doc """
    Transform a Bonfire Activity into a Mastodon Notification.

    Returns nil if the notification is invalid (missing required fields).

    ## Options

    - `:current_user` - The current user viewing the notification
    - `:subjects_by_id` - Map of subject IDs to preloaded user data
    - `:post_content_by_id` - Map of object IDs to preloaded post content
    - `:mentions_by_object` - Map of object IDs to preloaded mentions

    ## Examples

        iex> from_activity(activity)
        %{"id" => "123", "type" => "follow", "account" => %{...}}

        iex> from_activity(invalid_activity)
        nil
    """
    def from_activity(activity, opts \\ [])

    # Handle edge nodes
    def from_activity(%{node: activity}, opts), do: from_activity(activity, opts)

    def from_activity(activity, opts) when is_map(activity) do
      verb_id = get_field(activity, :verb) |> get_field(:verb)
      current_user = Keyword.get(opts, :current_user)
      object_id = get_field(activity, :object_id)

      # Get mentions for this object to determine notification type
      mentions_by_object = Keyword.get(opts, :mentions_by_object, %{})
      raw_mentions = Map.get(mentions_by_object, object_id, [])

      # Map verb to notification type (checking mentions for :create/:reply verbs)
      notification_type =
        map_verb_to_type(verb_id, current_user: current_user, mentions: raw_mentions)

      # Extract subject (the account that triggered the notification)
      subject = get_subject(activity, opts)
      account_data = Mappers.Account.from_user(subject)

      # Build status if this notification type includes one
      status_data =
        if should_include_status?(notification_type) do
          extract_status(activity, opts)
        else
          nil
        end

      # Fallback: try to get account from status if subject loading failed
      account_data =
        if is_nil(account_data) && is_map(status_data) do
          status_account = Map.get(status_data, "account")

          if is_map(status_account) && Map.get(status_account, "id") do
            status_account
          else
            nil
          end
        else
          account_data
        end

      # Build notification
      notification =
        Schemas.Notification.new(%{
          "id" => get_field(activity, :id),
          "type" => notification_type,
          "created_at" => get_field(activity, :created_at),
          "account" => account_data
        })

      notification =
        if status_data do
          Map.put(notification, "status", status_data)
        else
          notification
        end

      validate_notification(notification)
    end

    def from_activity(_, _opts), do: nil

    @doc """
    Maps a Bonfire verb ID to a Mastodon notification type.

    For `:create` and `:reply` activities, checks if the current user was mentioned
    to distinguish between "mention" (user was @mentioned) and "status" (subscribed to author).

    ## Options

    - `:current_user` - The current user viewing notifications
    - `:mentions` - List of mention tags from the post
    """
    def map_verb_to_type(verb_id, opts \\ [])

    def map_verb_to_type(nil, _opts) do
      warn(nil, "Notification has nil verb_id, defaulting to 'status'")
      "status"
    end

    def map_verb_to_type(verb_id, opts) do
      cond do
        verb_id == Bonfire.Boundaries.Verbs.get_id!(:like) ->
          "favourite"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:boost) ->
          "reblog"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:follow) ->
          "follow"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:request) ->
          "follow_request"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:create) ->
          if user_is_mentioned?(opts), do: "mention", else: "status"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:reply) ->
          if user_is_mentioned?(opts), do: "mention", else: "status"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:flag) ->
          "admin.report"

        true ->
          warn(verb_id, "Unknown verb ID in notification, defaulting to 'status'")
          "status"
      end
    end

    @doc """
    Determines if a notification type should include a status object.
    """
    def should_include_status?(notification_type) do
      notification_type in ["mention", "status", "reblog", "favourite", "poll", "update"]
    end

    # Private functions

    # Checks if the current user is mentioned in the post's mentions list
    defp user_is_mentioned?(opts) do
      current_user_id = Keyword.get(opts, :current_user) |> id()
      mentions = Keyword.get(opts, :mentions, [])

      current_user_id &&
        Enum.any?(mentions, fn mention ->
          mention_user_id = get_field(mention, :tag_id) || get_field(mention, :id)
          mention_user_id == current_user_id
        end)
    end

    # Get subject from activity or batch-loaded subjects
    defp get_subject(activity, opts) do
      subject = get_field(activity, :account) || get_field(activity, :subject)

      if is_nil(subject) || subject == %{} do
        subject_id = get_field(activity, :subject_id)
        subjects_by_id = Keyword.get(opts, :subjects_by_id, %{})
        Map.get(subjects_by_id, subject_id)
      else
        subject
      end
    end

    defp extract_status(activity, opts) do
      object = get_field(activity, :object)
      typename = get_field(object, :__typename)

      case typename do
        "Post" ->
          Mappers.Status.from_post(object, Keyword.merge(opts, for_notification: true))

        "Boost" ->
          edge = get_field(object, :edge)
          original_post = get_field(edge, :object)

          if get_field(original_post, :__typename) == "Post" do
            Mappers.Status.from_post(original_post, Keyword.merge(opts, for_notification: true))
          else
            fallback_status_from_activity(activity, opts)
          end

        _ ->
          # Unknown or missing object type - build fallback status from batch-loaded data
          fallback_status_from_activity(activity, opts)
      end
    end

    # Build a minimal status from activity data and batch-loaded content
    defp fallback_status_from_activity(activity, opts) do
      object_id = get_field(activity, :object_id)

      # Try to get post content from batch-loaded data
      post_content = get_field(activity, :object_post_content)

      post_content =
        if is_nil(post_content) || post_content == %{} do
          post_content_by_id = Keyword.get(opts, :post_content_by_id, %{})
          Map.get(post_content_by_id, object_id) || %{}
        else
          post_content
        end

      # Get subject from batch-loaded data
      subject = get_subject(activity, opts)

      if object_id && subject do
        account = Mappers.Account.from_user(subject)

        html_content =
          get_field(post_content, :content) ||
            get_field(post_content, :html_body) ||
            ""

        # Get mentions from batch-loaded mentions map
        mentions_by_object = Keyword.get(opts, :mentions_by_object, %{})
        raw_mentions = Map.get(mentions_by_object, object_id, [])
        current_user = Keyword.get(opts, :current_user)
        mentions = Mappers.Mention.from_tags(raw_mentions, current_user: current_user)

        Schemas.Status.new(%{
          "id" => object_id,
          "created_at" => get_field(activity, :created_at),
          "uri" => get_field(activity, :uri),
          "url" => get_field(activity, :uri),
          "account" => account,
          "content" => html_content,
          "spoiler_text" => get_field(post_content, :summary) || "",
          "mentions" => mentions
        })
      else
        nil
      end
    end

    defp validate_notification(notification) when is_map(notification) do
      case Schemas.Notification.validate(notification) do
        {:ok, valid_notification} ->
          valid_notification

        {:error, {:missing_fields, fields}} ->
          warn(
            "Notification missing required fields: #{inspect(fields)}, notification: #{inspect(notification)}"
          )

          nil

        {:error, {:invalid_type, type}} ->
          warn("Notification has invalid type: #{inspect(type)}")
          nil

        {:error, reason} ->
          warn("Notification validation failed: #{inspect(reason)}")
          nil
      end
    end

    defp validate_notification(_), do: nil
  end
end
