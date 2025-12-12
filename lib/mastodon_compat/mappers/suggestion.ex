if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Suggestion do
    @moduledoc """
    Maps Bonfire User objects to Mastodon Suggestion format.

    Suggestions represent accounts that are recommended for the user to follow.
    See: https://docs.joinmastodon.org/entities/Suggestion/
    """

    use Bonfire.Common.Utils

    alias Bonfire.API.MastoCompat.Schemas.Suggestion
    alias Bonfire.API.MastoCompat.Mappers.Account

    @doc """
    Transform a Bonfire User into a Mastodon Suggestion.

    ## Options

    - `:source` - The suggestion source (default: "global")
    - `:sources` - List of suggestion sources (default: ["global"])
    - All other options are passed to Account.from_user/2

    ## Examples

        iex> from_user(%{id: "123", character: %{username: "alice"}})
        %{"source" => "global", "sources" => ["global"], "account" => %{...}}

        iex> from_user(nil)
        nil
    """
    def from_user(user, opts \\ [])

    def from_user(nil, _opts), do: nil

    def from_user(user, opts) when is_map(user) do
      source = Keyword.get(opts, :source, "global")
      sources = Keyword.get(opts, :sources, [source])

      # Pass remaining options to Account mapper (e.g., skip_expensive_stats)
      account_opts = Keyword.drop(opts, [:source, :sources])

      case Account.from_user(user, account_opts) do
        nil ->
          nil

        account ->
          Suggestion.new(%{
            "source" => source,
            "sources" => sources,
            "account" => account
          })
      end
    end

    def from_user(_, _opts), do: nil

    @doc """
    Transform a list of Bonfire Users into Mastodon Suggestions.

    ## Options

    Same as from_user/2, applied to all users.

    ## Examples

        iex> from_users([%{id: "1"}, %{id: "2"}])
        [%{"source" => "global", ...}, %{"source" => "global", ...}]
    """
    def from_users(users, opts \\ []) when is_list(users) do
      users
      |> Enum.map(&from_user(&1, opts))
      |> Enum.reject(&is_nil/1)
    end
  end
end
