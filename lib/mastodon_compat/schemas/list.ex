defmodule Bonfire.API.MastoCompat.Schemas.List do
  @moduledoc """
  Schema definition for Mastodon List entity.

  Mastodon Lists allow users to organize accounts they follow into
  named groups for creating custom timelines.

  In Bonfire, Lists map to Circles.
  """

  @doc """
  Returns the default values for a Mastodon List.

  Includes Mastodon 4.x fields:
  - `replies_policy`: Show replies in the list timeline ("followed", "list", or "none")
  - `exclusive`: Whether list members are hidden from home timeline
  """
  def defaults do
    %{
      "id" => nil,
      "title" => "",
      # Mastodon 4.x fields with sensible defaults
      "replies_policy" => "list",
      "exclusive" => false
    }
  end

  @doc """
  Creates a new List map with defaults merged with provided attributes.
  """
  def new(attrs) when is_map(attrs) do
    Map.merge(defaults(), attrs)
  end

  @doc """
  Required fields for a valid Mastodon List.
  """
  def required_fields, do: ["id", "title"]

  @doc """
  Validates that a List has all required fields.

  Returns `{:ok, list}` if valid, `{:error, {:missing_fields, fields}}` otherwise.
  """
  def validate(list) when is_map(list) do
    missing =
      required_fields()
      |> Enum.filter(fn field -> is_nil(list[field]) end)

    if missing == [] do
      {:ok, list}
    else
      {:error, {:missing_fields, missing}}
    end
  end

  def validate(_), do: {:error, {:invalid_input, "expected a map"}}
end
