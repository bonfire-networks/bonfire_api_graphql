if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Notification do
    @moduledoc """
    Mastodon Notification entity schema definition.

    Based on the Mastodon API OpenAPI spec (mastodon-openapi.yaml line 2778+).
    This module provides a single source of truth for Notification field structure and defaults.

    All fields match the current implementation in graphql_masto_adapter.ex
    """

    @doc """
    Returns a new Notification map with default values.
    Can optionally merge custom values via the overrides parameter.

    ## Examples

        iex> Notification.new(%{"id" => "123", "type" => "follow"})
        %{"id" => "123", "type" => "follow", "created_at" => nil, ...}
    """
    def new(overrides \\ %{}) do
      defaults()
      |> Map.merge(overrides)
    end

    @doc """
    Returns the default values for all Notification fields.

    These defaults match the exact values currently used in prepare_notification/1.

    ## Required fields (per Mastodon OpenAPI spec):
    - id: The notification ID
    - type: Type of notification (follow, mention, reblog, favourite, etc.)
    - created_at: Timestamp of the notification
    - account: Account that caused the notification

    ## Optional fields:
    - status: Associated status (for mention, reblog, favourite, poll, status types)
    """
    def defaults do
      %{
        # Required fields
        "id" => nil,
        "type" => nil,
        "created_at" => nil,
        "account" => nil,

        # Optional fields
        "status" => nil
      }
    end

    @doc """
    List of required fields per the Mastodon OpenAPI specification.
    """
    def required_fields do
      ["id", "type", "created_at", "account"]
    end

    @doc """
    List of valid notification types per the Mastodon API spec.
    """
    def valid_types do
      [
        "follow",
        "follow_request",
        "mention",
        "reblog",
        "favourite",
        "poll",
        "status",
        "update"
      ]
    end

    @doc """
    Validates that all required fields are present and non-nil.
    Returns {:ok, notification} or {:error, reason}.
    """
    def validate(notification) when is_map(notification) do
      missing =
        required_fields()
        |> Enum.reject(fn field ->
          Map.has_key?(notification, field) && !is_nil(notification[field])
        end)

      case missing do
        [] ->
          # Also validate type if present
          type = Map.get(notification, "type")

          if type && type not in valid_types() do
            {:error, {:invalid_type, type}}
          else
            {:ok, notification}
          end

        fields ->
          {:error, {:missing_fields, fields}}
      end
    end

    def validate(_), do: {:error, :invalid_notification}
  end
end
