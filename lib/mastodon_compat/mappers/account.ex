if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Account do
    @moduledoc """
    Maps Bonfire User objects to Mastodon Account format.

    This module provides a consistent wrapper around the Me adapter's prepare_user/1
    function with standardized validation and nil handling.

    Previously, account preparation was done inline in 5 different places with
    slightly different validation logic. This consolidates that into one place.

    ## Usage

        # Basic account transformation
        Mappers.Account.from_user(user)

        # With options (e.g., include source field for /verify_credentials)
        Mappers.Account.from_user(user, include_source: true)
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.Common.Utils
    alias Bonfire.API.MastoCompat.Helpers
    alias Bonfire.Me.API.GraphQLMasto.Adapter, as: MeAdapter

    @doc """
    Transform a Bonfire User into a Mastodon Account.

    Returns nil if the user is nil or invalid.

    ## Options

    - `:include_source` - Include source field (for /verify_credentials endpoint)
    - `:fallback_return` - Value to return on error (default: nil)

    ## Examples

        iex> from_user(user)
        %{"id" => "123", "username" => "alice", ...}

        iex> from_user(nil)
        nil

        iex> from_user(%{}, fallback_return: %{})
        %{}
    """
    def from_user(user, opts \\ [])

    # Handle nil user
    def from_user(nil, _opts), do: nil

    # Handle empty map
    def from_user(user, opts) when is_map(user) and map_size(user) == 0 do
      Keyword.get(opts, :fallback_return, nil)
    end

    # Handle valid user
    def from_user(user, opts) when is_map(user) do
      fallback = Keyword.get(opts, :fallback_return, user)

      # Pre-process user to extract nested struct fields (profile, character)
      # MeAdapter.prepare_user expects flattened data but Enums.maybe_flatten
      # doesn't flatten nested structs, causing missing username/avatar/etc.
      user = normalize_user_data(user)

      # Call the Me adapter's prepare_user function
      prepared = Utils.maybe_apply(MeAdapter, :prepare_user, user, fallback_return: fallback)

      # Validate the result
      validate_account(prepared, opts)
    end

    # Handle non-map input
    def from_user(_, opts) do
      Keyword.get(opts, :fallback_return, nil)
    end

    # Normalize user data by extracting fields from nested Ecto structs
    # This ensures profile/character fields are accessible to MeAdapter.prepare_user
    defp normalize_user_data(user) when is_map(user) do
      profile = extract_nested(user, :profile)
      character = extract_nested(user, :character)

      # If we have nested profile/character data, normalize it for MeAdapter
      if has_nested_data?(profile) || has_nested_data?(character) do
        # Extract user ID (from user or nested structures)
        user_id =
          Map.get(user, :id) ||
            Map.get(user, "id") ||
            Map.get(character, :id) ||
            Map.get(profile, :id)

        # Build normalized user map with extracted nested fields
        # Field names MUST match GraphQL aliases used in MeAdapter.@user_profile
        # (display_name, avatar, avatar_static, header, header_static, note, acct, url)
        # so that after maybe_flatten(), keys match Mastodon API spec
        username = Map.get(character, :username)
        canonical_uri = Map.get(character, :canonical_uri)
        avatar_url = extract_media_url(Map.get(profile, :icon))
        header_url = extract_media_url(Map.get(profile, :image))

        %{
          id: user_id,
          # Profile fields - use Mastodon field names (matching GraphQL aliases)
          profile: %{
            display_name: Map.get(profile, :name),
            note: Map.get(profile, :summary) || Map.get(profile, :bio),
            # Mastodon requires both avatar and avatar_static
            avatar: avatar_url,
            avatar_static: avatar_url,
            # Mastodon requires both header and header_static
            header: header_url,
            header_static: header_url
          },
          # Character fields - use Mastodon field names (matching GraphQL aliases)
          character: %{
            username: username,
            # acct is required by Mastodon API (same as username for local users)
            acct: username,
            # url is required by Mastodon API
            url: canonical_uri
          },
          # Preserve created_at if available
          created_at: Map.get(user, :created_at)
        }
      else
        # Already normalized (e.g., from GraphQL) - pass through
        user
      end
    end

    defp normalize_user_data(other), do: other

    # Extract nested association, handling NotLoaded
    defp extract_nested(user, key) do
      case Map.get(user, key) do
        %Ecto.Association.NotLoaded{} -> %{}
        nil -> %{}
        data when is_struct(data) -> Map.from_struct(data)
        data when is_map(data) -> data
        _ -> %{}
      end
    end

    # Check if we have actual data (not empty map)
    defp has_nested_data?(data) when is_map(data), do: map_size(data) > 0
    defp has_nested_data?(_), do: false

    # Extract URL from media field (handles both struct and map)
    defp extract_media_url(nil), do: nil
    defp extract_media_url(%Ecto.Association.NotLoaded{}), do: nil

    defp extract_media_url(media) when is_struct(media) do
      Map.get(media, :path) || Map.get(media, :url)
    end

    defp extract_media_url(media) when is_map(media) do
      Map.get(media, :path) || Map.get(media, :url) ||
        Map.get(media, "path") || Map.get(media, "url")
    end

    defp extract_media_url(url) when is_binary(url), do: url
    defp extract_media_url(_), do: nil

    @doc """
    Validates that an account has the minimum required fields.

    An account must have at least an `id` field to be valid.
    Returns the account if valid, nil otherwise.
    """
    def validate_account(account, opts \\ [])

    def validate_account(nil, _opts), do: nil

    def validate_account(account, opts) when is_map(account) do
      has_id = Map.has_key?(account, :id) || Map.has_key?(account, "id")

      if has_id do
        account
      else
        # Log warning in development
        warn(
          %{account_keys: Map.keys(account)},
          "Account missing required 'id' field"
        )

        Keyword.get(opts, :fallback_return, nil)
      end
    end

    def validate_account(_, opts) do
      Keyword.get(opts, :fallback_return, nil)
    end

    @doc """
    Checks if an account object is valid (non-nil and has ID).
    """
    def valid?(account) do
      is_map(account) &&
        (Map.has_key?(account, :id) || Map.has_key?(account, "id"))
    end

    @doc """
    Validates account and raises if invalid.
    Useful for cases where account is required and shouldn't be nil.
    """
    def from_user!(user, opts \\ []) do
      case from_user(user, opts) do
        nil ->
          raise Bonfire.Fail, :not_found

        account ->
          account
      end
    end
  end
end
