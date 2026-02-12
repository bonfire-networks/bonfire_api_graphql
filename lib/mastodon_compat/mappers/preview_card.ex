if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.PreviewCard do
    @moduledoc """
    Maps Bonfire Media objects (trending links) to Mastodon PreviewCard format.

    Per the Mastodon API spec, a PreviewCard represents a rich preview card
    generated from a link included in a status.

    ## Required Fields

    - `url` (string) - Location of linked resource
    - `title` (string) - Title of linked resource
    - `description` (string) - Description of preview
    - `type` (string) - Type of preview card: "link", "photo", "video", "rich"

    ## Optional Fields

    - `author_name` (string) - Author of the original resource
    - `author_url` (string) - Link to the author
    - `provider_name` (string) - Provider of the original resource
    - `provider_url` (string) - Link to the provider
    - `html` (string) - HTML to be used for generating preview card
    - `width` (integer) - Width of preview in pixels
    - `height` (integer) - Height of preview in pixels
    - `image` (string, nullable) - Preview thumbnail URL
    - `embed_url` (string) - Used for photo embeds
    - `blurhash` (string, nullable) - Blurhash for the image
    - `history` (array) - Usage statistics for trending links
    """

    use Bonfire.Common.Utils
    alias Bonfire.Files.Media

    @doc """
    Transform a Bonfire Media struct (from trending links) to a Mastodon PreviewCard.
    """
    def from_media(nil), do: nil

    def from_media(%{path: path} = media) when is_binary(path) do
      metadata = Map.get(media, :metadata) || %{}

      %{
        "url" => path,
        "title" => Media.media_label(media) || "",
        "description" => Media.description(media) || "",
        "type" => card_type(metadata),
        "author_name" => extract_author_name(metadata),
        "author_url" => extract_author_url(metadata),
        "provider_name" => extract_provider_name(metadata),
        "provider_url" => extract_provider_url(metadata),
        "html" => "",
        "width" => extract_dimension(metadata, "width"),
        "height" => extract_dimension(metadata, "height"),
        "image" => extract_preview_image(media),
        "embed_url" => "",
        "blurhash" => nil,
        "history" => build_history(media)
      }
    end

    def from_media(_), do: nil

    defp card_type(metadata) do
      cond do
        e(metadata, "oembed", "type", nil) == "video" -> "video"
        e(metadata, "oembed", "type", nil) == "photo" -> "photo"
        e(metadata, "oembed", "type", nil) == "rich" -> "rich"
        true -> "link"
      end
    end

    defp extract_author_name(metadata) do
      (e(metadata, "oembed", "author_name", nil) ||
         e(metadata, "twitter", "creator", nil) ||
         e(metadata, "facebook", "article:author", nil))
      |> unwrap_value()
    end

    defp extract_author_url(metadata) do
      (e(metadata, "oembed", "author_url", nil) ||
         e(metadata, "twitter", "creator_url", nil))
      |> unwrap_value()
    end

    defp extract_provider_name(metadata) do
      (e(metadata, "facebook", "site_name", nil) ||
         e(metadata, "oembed", "provider_name", nil))
      |> unwrap_value()
    end

    defp extract_provider_url(metadata) do
      e(metadata, "oembed", "provider_url", nil)
      |> unwrap_value()
    end

    defp extract_dimension(metadata, key) do
      case e(metadata, "oembed", key, nil) || e(metadata, "facebook", "image:" <> key, nil) do
        n when is_integer(n) -> n
        s when is_binary(s) ->
          case Integer.parse(s) do
            {n, _} -> n
            _ -> 0
          end
        _ -> 0
      end
    end

    defp extract_preview_image(media) do
      metadata = Map.get(media, :metadata) || %{}

      e(metadata, "oembed", "thumbnail_url", nil) ||
        e(metadata, "twitter", "image", nil) ||
        e(metadata, "facebook", "image", "url", nil) ||
        e(metadata, "facebook", "image", nil) ||
        e(metadata, "image", "url", nil) ||
        e(metadata, "image", nil)
      |> unwrap_value()
    end

    defp build_history(media) do
      object_count = Map.get(media, :object_count) || 0

      [
        %{
          "day" => to_string(DateTime.utc_now() |> DateTime.to_unix()),
          "accounts" => to_string(object_count),
          "uses" => to_string(object_count)
        }
      ]
    end

    defp unwrap_value(list) when is_list(list), do: List.first(list)
    defp unwrap_value(value), do: value
  end
end
