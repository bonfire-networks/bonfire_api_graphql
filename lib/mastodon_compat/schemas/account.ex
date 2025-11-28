defmodule Bonfire.API.MastoCompat.Schemas.Account do
  @moduledoc """
  Schema definition for Mastodon Account entity.

  Mastodon Accounts represent user profiles with their metadata,
  statistics, and configuration.

  In Bonfire, Accounts map to Users with their Profile and Character data.
  """

  @doc """
  Returns the default values for a Mastodon Account.

  These defaults ensure all required fields have valid values.
  """
  def defaults do
    %{
      "id" => nil,
      "username" => "",
      "acct" => "",
      "url" => "",
      "display_name" => "",
      "note" => "",
      "avatar" => "",
      "avatar_static" => "",
      "header" => "",
      "header_static" => "",
      "locked" => false,
      "fields" => [],
      "emojis" => [],
      "bot" => false,
      "group" => false,
      "discoverable" => true,
      "noindex" => false,
      "suspended" => false,
      "limited" => false,
      "created_at" => nil,
      "last_status_at" => nil,
      "statuses_count" => 0,
      "followers_count" => 0,
      "following_count" => 0
    }
  end

  @doc """
  Creates a new Account map with defaults merged with provided attributes.
  """
  def new(attrs) when is_map(attrs) do
    Map.merge(defaults(), attrs)
  end

  @doc """
  Required fields for a valid Mastodon Account.

  Per the Mastodon API spec, these fields must be present and non-nil.
  """
  def required_fields, do: ["id", "username", "acct", "url"]

  @doc """
  Validates that an Account has all required fields.

  Returns `{:ok, account}` if valid, `{:error, {:missing_fields, fields}}` otherwise.
  """
  def validate(account) when is_map(account) do
    missing =
      required_fields()
      |> Enum.filter(fn field -> is_nil(account[field]) end)

    if missing == [] do
      {:ok, account}
    else
      {:error, {:missing_fields, missing}}
    end
  end

  def validate(_), do: {:error, {:invalid_input, "expected a map"}}
end
