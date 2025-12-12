if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Tag do
    @moduledoc "Mastodon Tag schema - represents a hashtag"

    @required_fields ["name", "url"]

    @defaults %{
      "name" => nil,
      "url" => nil,
      "history" => [],
      "following" => false,
      "id" => nil
    }

    def defaults, do: @defaults

    def new(attrs) when is_map(attrs), do: Map.merge(@defaults, attrs)

    @doc "Validates that required fields are present"
    def validate(tag) do
      missing = Enum.filter(@required_fields, &is_nil(tag[&1]))

      if Enum.empty?(missing) do
        {:ok, tag}
      else
        {:error, {:missing_fields, missing}}
      end
    end
  end
end
