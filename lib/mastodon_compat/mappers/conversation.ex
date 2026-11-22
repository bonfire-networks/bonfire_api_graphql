if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Conversation do
    @moduledoc """
    Maps a GraphQL conversation (`my_conversations` or `conversation(id:)`, selected with
    `Fragments.conversation_fields/0`) to a Mastodon Conversation. It only reads its input.

    A Mastodon Conversation represents a DM thread with:
    - id: Thread ID
    - accounts: Participants in the conversation
    - unread: Whether there are unseen messages
    - last_status: The most recent message in the thread
    """

    import Untangle

    alias Bonfire.API.MastoCompat.{Helpers, Mappers, Schemas}

    import Helpers, only: [get_field: 2]

    @doc """
    Transform a GraphQL conversation node (atom keys) into a Mastodon Conversation.

    ## Options

    - `:current_user` - The reader, for the mentions of the last status
    """
    def from_graphql(node, opts \\ [])

    def from_graphql(%{node: node}, opts), do: from_graphql(node, opts)

    def from_graphql(node, opts) when is_map(node) do
      participants = get_field(node, :participants) || []

      case get_field(node, :id) do
        nil ->
          warn(node, "A conversation came without an id")
          nil

        id ->
          Schemas.Conversation.new(%{
            "id" => to_string(id),
            "accounts" =>
              participants
              |> Enum.map(&Mappers.Account.from_user/1)
              |> Enum.reject(&is_nil/1),
            "unread" => get_field(node, :unread) != false,
            "last_status" =>
              last_status(get_field(node, :last_message), get_field(node, :sender), opts)
          })
          |> Helpers.validate_and_return(Schemas.Conversation)
      end
    end

    def from_graphql(_, _opts), do: nil

    # The sender is read with the reader's boundaries: one the reader may not see leaves no last status, as before. A DM is always "direct" (conversation decision 4).
    defp last_status(nil, _sender, _opts), do: nil
    defp last_status(_message, nil, _opts), do: nil

    defp last_status(message, sender, opts) do
      activity = get_field(message, :activity) || %{}

      message
      |> Map.put(:creator, sender)
      |> Map.put(:activity, Map.put(activity, :visibility, "direct"))
      |> Mappers.Status.from_post(current_user: Keyword.get(opts, :current_user))
    end
  end
end
