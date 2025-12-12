if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Poll do
    @moduledoc """
    Mastodon Poll schema - represents a poll attached to a status.

    See: https://docs.joinmastodon.org/entities/Poll/
    """

    @required_fields ["id", "options"]

    @defaults %{
      "id" => nil,
      "expires_at" => nil,
      "expired" => false,
      "multiple" => false,
      "votes_count" => 0,
      "voters_count" => nil,
      "voted" => false,
      "own_votes" => [],
      "options" => [],
      "emojis" => []
    }

    @doc "Returns the default values for a Poll"
    def defaults, do: @defaults

    @doc "Creates a new Poll by merging attrs with defaults"
    def new(attrs) when is_map(attrs) do
      @defaults
      |> Map.merge(attrs)
    end

    @doc "Validates that required fields are present"
    def validate(poll) do
      missing = Enum.filter(@required_fields, &is_nil(poll[&1]))

      if Enum.empty?(missing),
        do: {:ok, poll},
        else: {:error, {:missing_fields, missing}}
    end
  end
end
