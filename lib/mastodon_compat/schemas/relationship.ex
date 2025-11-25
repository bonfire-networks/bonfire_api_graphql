if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Relationship do
    @moduledoc "Mastodon Relationship schema - represents relationship between two accounts"

    @required_fields ["id"]

    @defaults %{
      "following" => false,
      "showing_reblogs" => true,
      "notifying" => false,
      "followed_by" => false,
      "blocking" => false,
      "blocked_by" => false,
      "muting" => false,
      "muting_notifications" => false,
      "requested" => false,
      "domain_blocking" => false,
      "endorsed" => false,
      "note" => ""
    }

    @doc "Returns the default values for a Relationship"
    def defaults, do: @defaults

    @doc "Creates a new Relationship by merging attrs with defaults"
    def new(attrs) when is_map(attrs) do
      @defaults
      |> Map.merge(attrs)
    end

    @doc "Validates that required fields are present"
    def validate(relationship) do
      missing = Enum.filter(@required_fields, &is_nil(relationship[&1]))

      if Enum.empty?(missing),
        do: {:ok, relationship},
        else: {:error, {:missing_fields, missing}}
    end
  end
end
