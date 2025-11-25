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
      # Extract verb and map to notification type
      verb_id = get_field(activity, :verb) |> get_field(:verb)
      notification_type = map_verb_to_type(verb_id)

      # Extract subject (the account that triggered the notification)
      subject = get_field(activity, :account) || get_field(activity, :subject)
      account_data = Mappers.Account.from_user(subject)

      # Build base notification
      notification =
        Schemas.Notification.new(%{
          "id" => get_field(activity, :id),
          "type" => notification_type,
          "created_at" => get_field(activity, :created_at),
          "account" => account_data
        })

      # Conditionally add status for certain notification types
      notification =
        if should_include_status?(notification_type) do
          status_data = extract_status(activity, opts)
          if status_data, do: Map.put(notification, "status", status_data), else: notification
        else
          notification
        end

      validate_notification(notification)
    end

    def from_activity(_, _opts), do: nil

    @doc """
    Maps a Bonfire verb ID to a Mastodon notification type.
    """
    def map_verb_to_type(nil) do
      warn(nil, "Notification has nil verb_id, defaulting to 'status'")
      "status"
    end

    def map_verb_to_type(verb_id) do
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
          # For create activities in notifications feed:
          # - If user is mentioned → "mention" type
          # - If user has notifications enabled for author → "status" type
          # TODO: Check post mentions to properly distinguish these cases
          # For now, default to "mention" as it's more common in notifications feed
          "mention"

        verb_id == Bonfire.Boundaries.Verbs.get_id!(:flag) ->
          # Note: This should be filtered for admin-only notifications
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

    defp extract_status(activity, opts) do
      object = get_field(activity, :object)

      case get_field(object, :__typename) do
        "Post" ->
          # Direct post object
          Mappers.Status.from_post(object, Keyword.merge(opts, for_notification: true))

        "Boost" ->
          # Boost object - extract the original post
          edge = get_field(object, :edge)
          original_post = get_field(edge, :object)

          if get_field(original_post, :__typename) == "Post" do
            Mappers.Status.from_post(original_post, Keyword.merge(opts, for_notification: true))
          else
            # Fallback to building from activity
            fallback_status_from_activity(activity, opts)
          end

        _ ->
          # Unknown or missing object type - try to build fallback status
          fallback_status_from_activity(activity, opts)
      end
    end

    defp fallback_status_from_activity(activity, _opts) do
      # Try to build a minimal status from activity data
      object_id = get_field(activity, :object_id)
      post_content = get_field(activity, :object_post_content) || %{}
      subject = get_field(activity, :account) || get_field(activity, :subject)

      if object_id && subject do
        account = Mappers.Account.from_user(subject)

        html_content =
          get_field(post_content, :content) ||
            get_field(post_content, :html_body) ||
            ""

        Schemas.Status.new(%{
          "id" => object_id,
          "created_at" => get_field(activity, :created_at),
          "uri" => get_field(activity, :uri),
          "url" => get_field(activity, :uri),
          "account" => account,
          "content" => html_content,
          "spoiler_text" => get_field(post_content, :summary) || ""
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
