if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Status do
    @moduledoc """
    Mastodon Status entity schema definition.

    Based on the Mastodon API OpenAPI spec (mastodon-openapi.yaml line 2047+).
    This module provides a single source of truth for Status field structure and defaults.

    All fields match the current implementation in graphql_masto_adapter.ex
    """

    @doc """
    Returns a new Status map with default values.
    Can optionally merge custom values via the overrides parameter.

    ## Examples

        iex> Status.new(%{"id" => "123", "content" => "Hello"})
        %{"id" => "123", "content" => "Hello", "visibility" => "public", ...}
    """
    def new(overrides \\ %{}) do
      defaults()
      |> Map.merge(overrides)
    end

    @doc """
    Returns the default values for all Status fields.

    These defaults match the exact values currently used in:
    - build_minimal_status/6
    - prepare_reblog/1
    - prepare_fallback_status/2
    - prepare_notification_post/2

    ## Required fields (per Mastodon OpenAPI spec):
    - id, uri, created_at, account, content
    - visibility, sensitive, spoiler_text
    - media_attachments (note: spec has typo "media_attachements")
    - mentions, tags, emojis
    - reblogs_count, favourites_count, replies_count

    ## Optional fields:
    - url, text, reblog, application, language
    - muted, bookmarked, pinned, favourited, reblogged
    - card, poll, in_reply_to_id, in_reply_to_account_id
    - filtered
    """
    def defaults do
      %{
        # Core identity fields (required)
        "id" => nil,
        "created_at" => nil,
        "uri" => nil,
        "url" => nil,

        # Account (required)
        "account" => nil,

        # Content fields (required)
        "content" => "",
        "text" => nil,
        "visibility" => "public",
        "sensitive" => false,
        "spoiler_text" => "",

        # Media and attachments (required)
        "media_attachments" => [],
        "mentions" => [],
        "tags" => [],
        "emojis" => [],

        # Interaction counts (required)
        "reblogs_count" => 0,
        "favourites_count" => 0,
        "replies_count" => 0,

        # User interaction states (optional)
        "favourited" => false,
        "reblogged" => false,
        "muted" => false,
        "bookmarked" => false,
        "pinned" => false,

        # Additional optional fields
        "filtered" => [],
        "reblog" => nil,
        "application" => nil,
        "language" => nil,
        "card" => nil,
        "poll" => nil,
        "in_reply_to_id" => nil,
        "in_reply_to_account_id" => nil
      }
    end

    @doc """
    List of required fields per the Mastodon OpenAPI specification.
    """
    def required_fields do
      [
        "id",
        "uri",
        "created_at",
        "account",
        "content",
        "visibility",
        "sensitive",
        "spoiler_text",
        "media_attachments",
        "mentions",
        "tags",
        "emojis",
        "reblogs_count",
        "favourites_count",
        "replies_count"
      ]
    end

    @doc """
    Validates that all required fields are present and non-nil.
    Returns {:ok, status} or {:error, missing_fields}.
    """
    def validate(status) when is_map(status) do
      missing =
        required_fields()
        |> Enum.reject(fn field -> Map.has_key?(status, field) && !is_nil(status[field]) end)

      case missing do
        [] -> {:ok, status}
        fields -> {:error, {:missing_fields, fields}}
      end
    end

    def validate(_), do: {:error, :invalid_status}
  end
end
