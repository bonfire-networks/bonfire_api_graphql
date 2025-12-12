if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Conversation do
    @moduledoc """
    Maps Bonfire Message threads to Mastodon Conversation format.

    A Mastodon Conversation represents a DM thread with:
    - id: Thread ID
    - accounts: Participants in the conversation
    - unread: Whether there are unseen messages
    - last_status: The most recent message in the thread

    ## Usage

        # Transform a thread message (from latest_in_threads query)
        Mappers.Conversation.from_thread(message, current_user: user)
    """

    use Bonfire.Common.Utils
    use Bonfire.Common.Repo
    import Untangle

    alias Bonfire.API.MastoCompat.{Helpers, Mappers, Schemas}
    alias Bonfire.Social.Threads

    import Helpers, only: [get_field: 2, get_fields: 2]

    @doc """
    Transform a Bonfire thread message into a Mastodon Conversation.

    Expects a message from `Bonfire.Messages.list/3` with `latest_in_threads: true`.

    ## Options

    - `:current_user` - The current user (required for participants and seen status)

    ## Examples

        iex> from_thread(message, current_user: user)
        %{"id" => "thread_123", "accounts" => [...], "unread" => false, "last_status" => {...}}
    """
    def from_thread(message, opts \\ [])

    def from_thread(nil, _opts), do: nil

    def from_thread(message, opts) when is_map(message) do
      current_user = Keyword.get(opts, :current_user)

      thread_id = get_thread_id(message)

      if thread_id do
        conversation =
          Schemas.Conversation.new(%{
            "id" => to_string(thread_id),
            "accounts" => get_participants(message, thread_id, opts),
            "unread" => check_unread(message, opts),
            "last_status" => build_last_status(message, opts)
          })

        Helpers.validate_and_return(conversation, Schemas.Conversation)
      else
        warn(message, "Could not extract thread_id from message")
        nil
      end
    end

    def from_thread(_, _opts), do: nil

    defp get_thread_id(message) do
      # Try to get thread_id from replied association
      # Falls back to the message's own ID if it's the thread root
      replied = get_field(message, :replied)
      thread_id = get_field(replied, :thread_id)

      # If no thread_id, this message might be the thread root
      thread_id || get_field(message, :id)
    end

    defp get_participants(message, thread_id, opts) do
      current_user = Keyword.get(opts, :current_user)

      participants =
        Threads.list_participants(message, thread_id, current_user: current_user)

      # Skip expensive stats for conversation participants (N+1 query prevention)
      account_opts = Keyword.merge(opts, skip_expensive_stats: true)

      participants
      |> Enum.map(&Mappers.Account.from_user(&1, account_opts))
      |> Enum.reject(&is_nil/1)
      |> filter_current_user(current_user)
    end

    defp filter_current_user(accounts, nil), do: accounts

    defp filter_current_user(accounts, current_user) do
      current_user_id = Types.uid(current_user)

      # Optionally exclude current user from participants list
      # Mastodon includes the current user, so we keep them
      # but this can be changed if needed
      accounts
    end

    defp check_unread(message, _opts) do
      # The :with_seen preload adds seen to activity.seen (not directly on message)
      # See activities.ex:864-866 for the preload structure
      activity = get_field(message, :activity)
      seen = get_field(activity, :seen)

      # If seen is nil or empty, it's unread
      # If seen exists (has an edge), it's been read
      cond do
        is_nil(seen) -> true
        seen == false -> true
        is_map(seen) and map_size(seen) == 0 -> true
        is_list(seen) and length(seen) == 0 -> true
        true -> false
      end
    end

    defp build_last_status(message, opts) do
      # Ensure necessary associations are loaded for Status transformation
      # Messages need:
      # - post_content for message content
      # - activity.subject with profile/character for Account mapper
      # - tagged with tag.character for mentions extraction
      message =
        message
        |> repo().maybe_preload([
          :post_content,
          activity: [subject: [:character, profile: :icon]],
          # Preload tags (mentions) - Tagged mixin with character data for mentioned users
          tagged: [tag: [:character, :profile]]
        ])

      # Messages loaded via Ecto (not GraphQL) are structured like Posts:
      # - message.post_content for content
      # - message.activity.subject for the sender
      # - message.tagged for mentions
      # Use from_post which handles this structure correctly
      # Pass for_conversation: true so Status mapper sets visibility to "direct"
      Mappers.Status.from_post(message, Keyword.put(opts, :for_conversation, true))
    end
  end
end
