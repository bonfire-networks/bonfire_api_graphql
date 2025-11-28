defmodule Bonfire.API.MastoCompat.Schemas.Mention do
  @moduledoc """
  Schema definition for Mastodon Mention entity.

  Per the Mastodon OpenAPI spec (mastodon-openapi.yaml lines 1862-1895),
  a Mention represents a mention of a user within the content of a status.

  All fields are required per the spec.
  """

  @doc """
  Returns the default values for a Mastodon Mention.
  """
  def defaults do
    %{
      "id" => nil,
      "username" => nil,
      "acct" => nil,
      "url" => nil
    }
  end

  @doc """
  Creates a new Mention map with defaults merged with provided attributes.
  """
  def new(attrs) when is_map(attrs) do
    Map.merge(defaults(), attrs)
  end

  @doc """
  Required fields for a valid Mastodon Mention.

  Per the spec, all four fields are required.
  """
  def required_fields, do: ["id", "username", "acct", "url"]

  @doc """
  Validates that a Mention has all required fields.

  Returns `{:ok, mention}` if valid, `{:error, {:missing_fields, fields}}` otherwise.
  """
  def validate(mention) when is_map(mention) do
    missing =
      required_fields()
      |> Enum.filter(fn field -> is_nil(mention[field]) end)

    if missing == [] do
      {:ok, mention}
    else
      {:error, {:missing_fields, missing}}
    end
  end

  def validate(_), do: {:error, {:invalid_input, "expected a map"}}
end
