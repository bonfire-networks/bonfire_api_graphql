if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Helpers do
    @moduledoc """
    Shared helper functions for Mastodon API mappers.

    This module provides common utilities used across mappers to safely
    extract and transform data from Bonfire structures to Mastodon format.
    """
    import Untangle

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

    def get_field(map, key) when is_map(map) and is_atom(key) do
      case Map.get(map, key) do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> Map.get(map, Atom.to_string(key))
        value -> value
      end
    end

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

    @doc """
    Recursively converts structs to JSON-safe values.

    Handles DateTime, NaiveDateTime, Date, and Ecto NotLoaded associations.
    Can optionally filter out nil values and drop unknown struct types.

    ## Options

    - `:filter_nils` - Remove nil values from maps and lists (default: false)
    - `:drop_unknown_structs` - Return nil for unrecognized structs instead of converting to map (default: false)

    ## Examples

        iex> deep_struct_to_map(%{date: ~U[2024-01-15 10:30:00Z]})
        %{date: "2024-01-15T10:30:00Z"}

        iex> deep_struct_to_map(%{value: nil}, filter_nils: true)
        %{}

        iex> deep_struct_to_map(%Ecto.Association.NotLoaded{})
        nil
    """
    def deep_struct_to_map(value, opts \\ [])
    def deep_struct_to_map(nil, _opts), do: nil
    def deep_struct_to_map(%DateTime{} = dt, _opts), do: DateTime.to_iso8601(dt)
    def deep_struct_to_map(%NaiveDateTime{} = dt, _opts), do: NaiveDateTime.to_iso8601(dt) <> "Z"
    def deep_struct_to_map(%Date{} = d, _opts), do: Date.to_iso8601(d)
    def deep_struct_to_map(%Ecto.Association.NotLoaded{}, _opts), do: nil

    def deep_struct_to_map(data, opts) when is_struct(data) do
      if Keyword.get(opts, :drop_unknown_structs, false) do
        nil
      else
        data
        |> Map.from_struct()
        |> Map.drop([:__meta__])
        |> deep_struct_to_map(opts)
      end
    end

    def deep_struct_to_map(data, opts) when is_map(data) do
      result = Enum.map(data, fn {k, v} -> {k, deep_struct_to_map(v, opts)} end)

      if Keyword.get(opts, :filter_nils, false) do
        result
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      else
        Map.new(result)
      end
    end

    def deep_struct_to_map(data, opts) when is_list(data) do
      result = Enum.map(data, &deep_struct_to_map(&1, opts))

      if Keyword.get(opts, :filter_nils, false) do
        Enum.reject(result, &is_nil/1)
      else
        result
      end
    end

    def deep_struct_to_map(data, _opts), do: data

    @doc """
    Validates an entity against a schema module and returns the valid entity or nil.

    Logs warnings for validation failures to aid debugging without crashing.

    ## Parameters

    - `entity` - The map to validate
    - `schema_module` - The schema module with a `validate/1` function

    ## Examples

        iex> validate_and_return(%{"id" => "123"}, Schemas.Status)
        %{"id" => "123", ...}

        iex> validate_and_return(%{}, Schemas.Status)
        nil  # Logs warning about missing required fields
    """
    def validate_and_return(nil, _schema_module), do: nil

    def validate_and_return(entity, schema_module) do
      case schema_module.validate(entity) do
        {:ok, valid} ->
          valid

        {:error, {:missing_fields, fields}} ->
          debug(entity, "#{inspect(schema_module)} missing required fields: #{inspect(fields)}")
          nil

        {:error, {:invalid_type, type}} ->
          debug(entity, "#{inspect(schema_module)} has invalid type: #{inspect(type)}")
          nil

        {:error, reason} ->
          debug(entity, "#{inspect(schema_module)} validation failed: #{inspect(reason)}")
          nil
      end
    end

    @doc """
    Get the first non-nil value from a map by trying multiple keys in order.

    Useful when data can come from either GraphQL (with aliased field names)
    or directly from Ecto (with raw schema field names).

    ## Examples

        iex> get_fields(%{display_name: "Alice"}, [:display_name, :name])
        "Alice"

        iex> get_fields(%{name: "Bob"}, [:display_name, :name])
        "Bob"

        iex> get_fields(%{other: "value"}, [:display_name, :name])
        nil

        iex> get_fields(%{"avatar" => "url"}, [:avatar, "avatar", :icon, "icon"])
        "url"
    """
    def get_fields(nil, _keys), do: nil
    def get_fields(_map, []), do: nil

    def get_fields(map, keys) when is_map(map) and is_list(keys) do
      Enum.find_value(keys, fn key ->
        case Map.get(map, key) do
          %Ecto.Association.NotLoaded{} -> nil
          value -> value
        end
      end)
    end

    def get_fields(_, _), do: nil

    @doc """
    Normalize a hashtag string for querying.

    Removes # prefix if present and handles case normalization.
    Uses Bonfire's hashtag normalization if available, otherwise
    falls back to simple lowercase.

    ## Examples

        iex> normalize_hashtag("#Bonfire")
        "bonfire"

        iex> normalize_hashtag("ELIXIR")
        "elixir"

        iex> normalize_hashtag(nil)
        ""
    """
    def normalize_hashtag(hashtag) when is_binary(hashtag) do
      hashtag
      |> String.trim()
      |> String.trim_leading("#")
      |> then(fn tag ->
        if Code.ensure_loaded?(Bonfire.Tag.Hashtag) and
             function_exported?(Bonfire.Tag.Hashtag, :normalize_name, 1) do
          Bonfire.Tag.Hashtag.normalize_name(tag)
        else
          String.downcase(tag)
        end
      end)
    end

    def normalize_hashtag(_), do: ""
  end
end
