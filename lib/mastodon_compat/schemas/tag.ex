if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Tag do
    @moduledoc "Mastodon Tag schema - represents a hashtag"

    @defaults %{
      "name" => nil,
      "url" => nil,
      "history" => [],
      "following" => false,
      "id" => nil
    }

    def defaults, do: @defaults

    def new(attrs) when is_map(attrs), do: Map.merge(@defaults, attrs)
  end
end
