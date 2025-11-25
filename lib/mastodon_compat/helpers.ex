if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Helpers do
    @moduledoc """
    Shared helper functions for Mastodon API mappers.

    This module provides common utilities used across mappers to safely
    extract and transform data from Bonfire structures to Mastodon format.
    """

    @doc """
    Safely get a field from a map or struct, handling nil and NotLoaded associations.

    Returns `nil` for:
    - nil input
    - Empty maps
    - NotLoaded Ecto associations
    - Non-map inputs
    - Missing keys

    ## Examples

        iex> get_field(%{name: "test"}, :name)
        "test"

        iex> get_field(nil, :name)
        nil

        iex> get_field(%{}, :name)
        nil

        iex> get_field(%{assoc: %Ecto.Association.NotLoaded{}}, :assoc)
        nil
    """
    def get_field(nil, _key), do: nil
    def get_field(map, _key) when is_map(map) and map_size(map) == 0, do: nil

    def get_field(map, key) when is_map(map) do
      case Map.get(map, key) do
        %Ecto.Association.NotLoaded{} -> nil
        value -> value
      end
    end

    def get_field(_, _), do: nil

    @doc """
    Converts a value to string, handling nil gracefully.

    ## Examples

        iex> to_string_safe(123)
        "123"

        iex> to_string_safe(nil)
        nil

        iex> to_string_safe("already_string")
        "already_string"
    """
    def to_string_safe(nil), do: nil
    def to_string_safe(value) when is_binary(value), do: value
    def to_string_safe(value), do: to_string(value)

    @doc """
    Formats a datetime to ISO8601 format as expected by Mastodon API.

    Handles various datetime types (DateTime, NaiveDateTime, Date) and
    returns nil for invalid inputs.

    ## Examples

        iex> format_datetime(~U[2024-01-15 10:30:00Z])
        "2024-01-15T10:30:00.000Z"

        iex> format_datetime(nil)
        nil
    """
    def format_datetime(nil), do: nil
    def format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
    def format_datetime(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt) <> "Z"

    def format_datetime(value) when is_binary(value) do
      case DateTime.from_iso8601(value) do
        {:ok, dt, _} -> DateTime.to_iso8601(dt)
        _ -> value
      end
    end

    def format_datetime(_), do: nil
  end
end
