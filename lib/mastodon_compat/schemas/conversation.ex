if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Conversation do
    @moduledoc """
    Mastodon Conversation entity schema definition.

    Based on the Mastodon API OpenAPI spec (mastodon-openapi.yaml lines 2482-2505).
    Represents a conversation with "direct message" visibility.
    """

    @doc """
    Returns a new Conversation map with default values.
    Can optionally merge custom values via the overrides parameter.

    ## Examples

        iex> Conversation.new(%{"id" => "123", "accounts" => [account]})
        %{"id" => "123", "accounts" => [account], "unread" => false, ...}
    """
    def new(overrides \\ %{}) do
      defaults()
      |> Map.merge(overrides)
    end

    @doc """
    Returns the default values for all Conversation fields.

    ## Required fields (per Mastodon OpenAPI spec):
    - id: Local database ID of the conversation
    - accounts: Participants in the conversation
    - unread: Is the conversation currently marked as unread?

    ## Optional fields:
    - last_status: The most recent status in the conversation
    """
    def defaults do
      %{
        "id" => nil,
        "accounts" => [],
        "unread" => false,
        "last_status" => nil
      }
    end

    @doc """
    List of required fields per the Mastodon OpenAPI specification.
    """
    def required_fields do
      ["id", "accounts", "unread"]
    end

    @doc """
    Validates that all required fields are present and non-nil.
    Returns {:ok, conversation} or {:error, {:missing_fields, fields}}.
    """
    def validate(conversation) when is_map(conversation) do
      missing =
        required_fields()
        |> Enum.reject(fn field ->
          Map.has_key?(conversation, field) && !is_nil(conversation[field])
        end)

      case missing do
        [] -> {:ok, conversation}
        fields -> {:error, {:missing_fields, fields}}
      end
    end

    def validate(_), do: {:error, :invalid_conversation}
  end
end
