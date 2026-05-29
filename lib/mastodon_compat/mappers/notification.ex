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
    - `quote` - Someone quoted one of your statuses
    - `quoted_update` - A status you quoted has been edited

    ## Usage

        Mappers.Notification.from_activity(activity, current_user: user)
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.{Schemas, Mappers, Helpers}

    import Helpers, only: [get_field: 2, get_fields: 2]

    @type_to_masto %{
      favourite: "favourite",
      reblog: "reblog",
      follow: "follow",
      follow_request: "follow_request",
      poll: "poll",
      mention: "mention",
      admin_report: "admin.report",
      quote: "quote",
      quoted_update: "quoted_update",
      status: "status",
      update: "update"
    }

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
    def from_candidate(
          %{__struct__: Bonfire.Social.Notifications.Candidate} = candidate,
          opts \\ []
        ) do
      opts =
        candidate
        |> Map.get(:status_context, [])
        |> Keyword.merge(opts)
        |> Keyword.put(:notification_type, Map.fetch!(@type_to_masto, Map.get(candidate, :type)))
        |> Keyword.put(:subject, Map.get(candidate, :actor))
        |> Keyword.put(:mentions, Map.get(candidate, :mentions, []))
        |> Keyword.put(:status_post, Map.get(candidate, :status_post))

      from_activity(Map.get(candidate, :activity), opts)
    end

    def from_activity(activity, opts \\ [])
    def from_activity(%{node: activity}, opts), do: from_activity(activity, opts)

    def from_activity(activity, opts) when is_map(activity) do
      # Handle both GraphQL maps (verb: %{verb: "Create"}) and Ecto structs (verb: %Verb{verb: "Create"} or verb_id: "...")
      verb_id =
        case get_field(activity, :verb) do
          %{verb: v} when is_binary(v) -> v
          v when is_binary(v) -> v
          _ -> get_field(activity, :verb_id)
        end

      current_user = Keyword.get(opts, :current_user)
      object_id = get_field(activity, :object_id)

      mentions_by_object = Keyword.get(opts, :mentions_by_object, %{})
      raw_mentions = Keyword.get(opts, :mentions) || Map.get(mentions_by_object, object_id, [])

      notification_type =
        Keyword.get(opts, :notification_type) ||
          map_verb_to_type(verb_id,
            current_user: current_user,
            mentions: raw_mentions,
            edge_table_id: get_field(get_field(activity, :edge), :table_id)
          )

      if is_nil(notification_type) do
        nil
      else
        subject = get_subject(activity, opts)
        account_data = Mappers.Account.from_user(subject, skip_expensive_stats: true)

        status_data =
          if should_include_status?(notification_type) do
            extract_status(notification_type, activity, opts)
          else
            nil
          end

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

        activity_id = get_field(activity, :id)

        created_at =
          get_field(activity, :created_at) || get_field(activity, :date) ||
            (activity_id && Bonfire.Common.DatesTimes.date_from_pointer(activity_id))

        notification =
          Schemas.Notification.new(%{
            "id" => activity_id,
            "type" => notification_type,
            "created_at" => created_at,
            "account" => account_data
          })

        notification =
          if status_data do
            Map.put(notification, "status", status_data)
          else
            notification
          end

        Helpers.validate_and_return(notification, Schemas.Notification)
      end
    end

    def from_activity(_, _opts), do: nil

    @doc """
    Maps a Bonfire verb ID to a Mastodon notification type.

    For `:create` and `:reply` activities, only returns "mention" when the
    current user was mentioned. Unsupported or unmentioned activities return
    `nil` so the Mastodon notifications endpoint can drop them.

    ## Options

    - `:current_user` - The current user viewing notifications
    - `:mentions` - List of mention tags from the post
    """
    def map_verb_to_type(verb_id, opts \\ [])

    def map_verb_to_type(nil, _opts) do
      warn(nil, "Notification has nil verb_id, dropping")
      nil
    end

    def map_verb_to_type(verb_id, opts) do
      cond do
        verb_id == verb_id(:like) ->
          "favourite"

        verb_id == verb_id(:boost) ->
          "reblog"

        verb_id == verb_id(:follow) ->
          "follow"

        verb_id == verb_id(:request) ->
          request_type(opts)

        verb_id == verb_id(:vote) ->
          "poll"

        verb_id == verb_id(:create) ->
          if user_is_mentioned?(opts), do: "mention"

        verb_id == verb_id(:reply) ->
          if user_is_mentioned?(opts), do: "mention"

        verb_id == verb_id(:flag) ->
          "admin.report"

        true ->
          warn(verb_id, "Unknown verb ID in Mastodon notification mapper, dropping")
          nil
      end
    end

    defp verb_id(slug) do
      maybe_apply(Bonfire.Boundaries.Verbs, :get_id!, [slug], fallback_return: nil)
    end

    @doc """
    Determines if a notification type should include a status object.
    """
    def should_include_status?(notification_type) do
      notification_type in [
        "mention",
        "status",
        "reblog",
        "favourite",
        "poll",
        "update",
        "quote",
        "quoted_update"
      ]
    end

    defp quote_request?(opts) do
      Keyword.get(opts, :edge_table_id) ==
        maybe_apply(Bonfire.Social.Quotes, :quote_verb_id, [], fallback_return: nil)
    end

    defp follow_request?(opts) do
      Keyword.get(opts, :edge_table_id) ==
        Bonfire.Common.Types.table_id(Bonfire.Data.Social.Follow)
    end

    defp request_type(opts) do
      cond do
        quote_request?(opts) -> "quote"
        follow_request?(opts) -> "follow_request"
        true -> nil
      end
    end

    defp user_is_mentioned?(opts) do
      current_user_id = Keyword.get(opts, :current_user) |> id()
      mentions = Keyword.get(opts, :mentions, [])

      current_user_id &&
        Enum.any?(mentions, fn mention ->
          mention_user_id = get_fields(mention, [:tag_id, :id])
          mention_user_id == current_user_id
        end)
    end

    defp get_subject(activity, opts) do
      subject_id = get_field(activity, :subject_id)
      subjects_by_id = Keyword.get(opts, :subjects_by_id, %{})
      batch_subject = subject_id && Map.get(subjects_by_id, subject_id)
      subject = Keyword.get(opts, :subject) || get_fields(activity, [:account, :subject])

      cond do
        present_subject?(batch_subject) ->
          batch_subject

        present_subject?(subject) ->
          subject

        true ->
          nil
      end
    end

    defp extract_status("quote", activity, opts) do
      case Keyword.get(opts, :status_post) || get_field(get_field(activity, :edge), :subject) do
        quote_post when is_map(quote_post) ->
          Mappers.Status.from_post(quote_post, Keyword.merge(opts, for_notification: true))

        _ ->
          nil
      end
    end

    defp extract_status(_notification_type, activity, opts) do
      case Keyword.get(opts, :status_post) do
        status_post when is_map(status_post) ->
          Mappers.Status.from_post(status_post, Keyword.merge(opts, for_notification: true))

        _ ->
          extract_status_from_activity(activity, opts)
      end
    end

    defp extract_status_from_activity(activity, opts) do
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
          fallback_status_from_activity(activity, opts)
      end
    end

    defp fallback_status_from_activity(activity, opts) do
      object_id = get_field(activity, :object_id)
      post_content = get_field(activity, :object_post_content)

      post_content =
        if is_nil(post_content) || post_content == %{} do
          post_content_by_id = Keyword.get(opts, :post_content_by_id, %{})
          Map.get(post_content_by_id, object_id) || %{}
        else
          post_content
        end

      subject = get_subject(activity, opts)

      if object_id && subject do
        account = Mappers.Account.from_user(subject, skip_expensive_stats: true)

        html_content =
          get_field(post_content, :content) ||
            get_field(post_content, :html_body) ||
            ""

        mentions_by_object = Keyword.get(opts, :mentions_by_object, %{})
        raw_mentions = Map.get(mentions_by_object, object_id, [])
        current_user = Keyword.get(opts, :current_user)
        mentions = Mappers.Mention.from_tags(raw_mentions, current_user: current_user)
        status_created_at = fallback_status_created_at(activity, object_id)
        status_uri = fallback_status_uri(activity, object_id)

        Schemas.Status.new(%{
          "id" => object_id,
          "created_at" => status_created_at,
          "uri" => status_uri,
          "url" => status_uri,
          "account" => account,
          "content" => html_content,
          "spoiler_text" => get_field(post_content, :summary) || "",
          "mentions" => mentions
        })
      else
        nil
      end
    end

    defp fallback_status_created_at(activity, object_id) do
      activity_id = get_field(activity, :id)

      get_field(activity, :created_at) ||
        get_field(activity, :date) ||
        (object_id && Bonfire.Common.DatesTimes.date_from_pointer(object_id)) ||
        (activity_id && Bonfire.Common.DatesTimes.date_from_pointer(activity_id))
    end

    defp fallback_status_uri(activity, object_id) do
      get_field(activity, :uri) ||
        get_field(activity, :url) ||
        (object_id && Bonfire.Common.URIs.maybe_generate_canonical_url(object_id)) ||
        (object_id && "/post/#{object_id}")
    end

    defp present_subject?(nil), do: false
    defp present_subject?(%Ecto.Association.NotLoaded{}), do: false
    defp present_subject?(%{} = subject), do: map_size(subject) > 0
    defp present_subject?(_), do: true
  end
end
