if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Suggestion do
    @moduledoc """
    Mastodon Suggestion schema - represents an account suggestion.

    See: https://docs.joinmastodon.org/entities/Suggestion/
    """

    @defaults %{
      "source" => "global",
      "sources" => [],
      "account" => nil
    }

    @doc "Returns the default values for a Suggestion"
    def defaults, do: @defaults

    @doc "Creates a new Suggestion by merging attrs with defaults"
    def new(attrs) when is_map(attrs) do
      @defaults
      |> Map.merge(attrs)
    end
  end
end
