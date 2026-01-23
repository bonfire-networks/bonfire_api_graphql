if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Tag do
    @moduledoc """
    Maps Bonfire Hashtag objects to Mastodon Tag format.

    Per the Mastodon API spec, a Tag represents a hashtag used within a status.

    ## Required Fields

    - `name` (string) - The hashtag name (without #)
    - `url` (string, uri) - URL to the hashtag timeline

    ## Optional Fields

    - `history` (array) - Usage statistics (empty array - not implemented)
    - `following` (boolean) - Whether the authenticated user is following this hashtag
    """

    use Bonfire.Common.Utils

    alias Bonfire.API.MastoCompat.Schemas

    @doc """
    Transform a Bonfire Hashtag to a Mastodon Tag.

    ## Options

    - `:following` - Whether the current user is following this hashtag (default: false)
    """
    def from_hashtag(hashtag, opts \\ [])

    def from_hashtag(nil, _opts), do: nil

    def from_hashtag(hashtag, opts) when is_map(hashtag) do
      name = extract_name(hashtag)

      if name do
        Schemas.Tag.new(%{
          "name" => name,
          "url" => build_tag_url(name),
          "history" => [],
          "following" => Keyword.get(opts, :following, false),
          "id" => extract_id(hashtag)
        })
      else
        nil
      end
    end

    def from_hashtag(_, _opts), do: nil

    @doc """
    Transform a Bonfire Hashtag to a Mastodon FeaturedTag.

    FeaturedTag has additional fields:
    - `statuses_count` - Number of statuses with this hashtag by the user (not implemented)
    - `last_status_at` - Date of last status with this hashtag (not implemented)
    """
    def from_featured_hashtag(hashtag) when is_map(hashtag) do
      name = extract_name(hashtag)

      if name do
        %{
          "id" => extract_id(hashtag),
          "name" => name,
          "url" => build_tag_url(name),
          "statuses_count" => 0,
          "last_status_at" => nil
        }
      else
        nil
      end
    end

    def from_featured_hashtag(_), do: nil

    defp extract_name(hashtag) do
      e(hashtag, :named, :name, nil) ||
        e(hashtag, :name, nil)
    end

    defp extract_id(hashtag) do
      id = e(hashtag, :id, nil)
      if id, do: to_string(id), else: nil
    end

    defp build_tag_url(name) do
      base_url = Bonfire.Common.URIs.base_url()
      "#{base_url}/pub/tags/#{name}"
    end
  end
end
