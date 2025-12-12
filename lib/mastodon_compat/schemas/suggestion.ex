if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Suggestion do
    @moduledoc """
    Mastodon Suggestion schema - represents an account suggestion.

    See: https://docs.joinmastodon.org/entities/Suggestion/
    """

    @required_fields ["source", "account"]

    # Source values:
    # Deprecated (v3.4.0): staff, past_interactions, global
    # New (v4.3.0): featured, most_followed, most_interactions, similar_to_recently_followed, friends_of_friends
    @valid_sources ~w(staff past_interactions global featured most_followed most_interactions similar_to_recently_followed friends_of_friends)

    @defaults %{
      "source" => "global",
      "sources" => [],
      "account" => nil
    }

    @doc "Returns the default values for a Suggestion"
    def defaults, do: @defaults

    @doc "Returns valid source values"
    def valid_sources, do: @valid_sources

    @doc "Creates a new Suggestion by merging attrs with defaults"
    def new(attrs) when is_map(attrs) do
      @defaults
      |> Map.merge(attrs)
    end

    @doc "Validates that required fields are present and source is valid"
    def validate(suggestion) do
      missing = Enum.filter(@required_fields, &is_nil(suggestion[&1]))

      cond do
        not Enum.empty?(missing) ->
          {:error, {:missing_fields, missing}}

        not valid_source?(suggestion["source"]) ->
          {:error, {:invalid_source, suggestion["source"]}}

        true ->
          {:ok, suggestion}
      end
    end

    defp valid_source?(source), do: source in @valid_sources
  end
end
