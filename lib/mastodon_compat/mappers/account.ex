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
    alias Bonfire.Common.Utils
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

      # Call the Me adapter's prepare_user function
      prepared = Utils.maybe_apply(MeAdapter, :prepare_user, user, fallback_return: fallback)

      # Validate the result
      validate_account(prepared, opts)
    end

    # Handle non-map input
    def from_user(_, opts) do
      Keyword.get(opts, :fallback_return, nil)
    end

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
