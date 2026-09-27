if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Notification do
    @moduledoc """
    Mastodon Notification entity schema definition.

    Based on the Mastodon API OpenAPI spec (mastodon-openapi.yaml line 2778+).
    This module provides a single source of truth for Notification field structure and defaults.

    All fields match the current implementation in graphql_masto_adapter.ex
    """
    use Bonfire.Common.Config

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
    Every notification type the Mastodon API documents, as it names them, declared in this extension's compile-time config (`config/bonfire_api_graphql.exs`). The one list of Mastodon's type names: `type_atom/1` and `type_name/1` translate through it.
    """
    def valid_types do
      Config.get([__MODULE__, :valid_types], [], :bonfire_api_graphql)
    end

    @doc """
    Our atom for a Mastodon notification type: its name with the admin types' `.` as `_` (`"admin.report"` is `:admin_report`). `nil` for a name that isn't one of `valid_types/0`, so a client's `types[]` can't make atoms of whatever it sends.

    ## Examples

        iex> type_atom("admin.report")
        :admin_report

        iex> type_atom("follow_request")
        :follow_request

        iex> type_atom("not_a_type")
        nil
    """
    def type_atom(name) when is_binary(name) do
      if name in valid_types(), do: name |> String.replace(".", "_") |> String.to_atom()
    end

    def type_atom(_), do: nil

    @doc """
    Mastodon's name for one of our notification type atoms, looked up in `valid_types/0` rather than rebuilt, since only the admin types use a `.` (`:follow_request` stays `"follow_request"`). `nil` for one Mastodon has no name for.

    ## Examples

        iex> type_name(:admin_report)
        "admin.report"

        iex> type_name(:follow_request)
        "follow_request"
    """
    def type_name(type) when is_atom(type) and not is_nil(type) do
      name = Atom.to_string(type)
      Enum.find(valid_types(), &(String.replace(&1, ".", "_") == name))
    end

    def type_name(_), do: nil

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
