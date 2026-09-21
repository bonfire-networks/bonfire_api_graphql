if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.MediaAttachment do
    @moduledoc """
    Maps Bonfire Media objects to Mastodon MediaAttachment format.
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.Helpers

    import Helpers, only: [get_field: 2, get_fields: 2]

    def from_media_list(media_list, opts \\ [])
    def from_media_list(nil, _opts), do: []
    def from_media_list([], _opts), do: []

    def from_media_list(media_list, opts) when is_list(media_list) do
      media_list
      |> Enum.map(&from_media(&1, opts))
      |> Enum.reject(&is_nil/1)
    end

    def from_media_list(_other, _opts), do: []

    def from_media(media, opts \\ [])
    def from_media(nil, _opts), do: nil

    def from_media(media, _opts) when is_map(media) do
      media_type = get_field(media, :media_type) || "unknown"
      type = categorize_media_type(media_type)
      url = build_url(media)

      %{
        "id" => to_string(get_field(media, :id) || ""),
        "type" => type,
        "url" => url || "",
        "preview_url" => build_preview_url(media, type, url),
        "remote_url" => get_field(media, :remote_url),
        "text_url" => nil,
        "meta" => build_meta(media, type),
        "description" => extract_description(media),
        "blurhash" => get_field(media, :blurhash) || extract_blurhash(media)
      }
    end

    def from_media(_, _opts), do: nil

    defp categorize_media_type(mime) when is_binary(mime) do
      cond do
        String.starts_with?(mime, "image/") -> "image"
        String.starts_with?(mime, "video/") -> "video"
        String.starts_with?(mime, "audio/") -> "audio"
        true -> "unknown"
      end
    end

    defp categorize_media_type(_), do: "unknown"

    defp build_url(media) do
      (get_fields(media, [:url, :path]) || build_url_from_file(media))
      |> Bonfire.Common.URIs.based_url()
    end

    defp build_preview_url(_media, "image", url), do: url

    defp build_preview_url(media, _type, _url) do
      (get_field(media, :preview_url) || Bonfire.Common.Media.thumbnail_url(media))
      |> Bonfire.Common.URIs.based_url()
    end

    defp build_url_from_file(media) do
      case get_field(media, :file) do
        %{file_name: name} when is_binary(name) ->
          Bonfire.Files.remote_url(media)

        _ ->
          nil
      end
    end

    defp build_meta(media, type) do
      metadata = get_field(media, :metadata) || %{}
      width = metadata["width"] || get_field(media, :width)
      height = metadata["height"] || get_field(media, :height)

      original =
        if width && height do
          %{
            "width" => width,
            "height" => height,
            "size" => "#{width}x#{height}",
            "aspect" => calculate_aspect(width, height)
          }
        else
          %{}
        end

      focus = metadata["focus"] || get_field(media, :focus)
      focus_meta = if focus, do: %{"focus" => parse_focus(focus)}, else: %{}

      duration_meta =
        if type in ["video", "audio", "gifv"] do
          duration =
            (metadata["duration"] || get_field(media, :duration))
            |> normalize_duration()

          if duration, do: %{"duration" => duration}, else: %{}
        else
          %{}
        end

      %{}
      |> Map.merge(if map_size(original) > 0, do: %{"original" => original}, else: %{})
      |> Map.merge(focus_meta)
      |> Map.merge(duration_meta)
    end

    @doc """
    Converts media durations to numeric seconds for Mastodon clients. Unknown or invalid durations are omitted rather than exposed as strings.

    Calendar years and months are not accepted because their duration in seconds is ambiguous.

    ## Examples

        iex> normalize_duration("PT253.47S")
        253.47

        iex> normalize_duration("PT1H2M3S")
        3723.0

        iex> normalize_duration("12.5")
        12.5

        iex> normalize_duration("unknown")
        nil
    """
    def normalize_duration(duration) when is_number(duration) and duration >= 0, do: duration

    def normalize_duration("P" <> _ = duration) do
      captures =
        Regex.named_captures(
          ~r/^P(?:(?<days>\d+(?:\.\d+)?)D)?(?:T(?:(?<hours>\d+(?:\.\d+)?)H)?(?:(?<minutes>\d+(?:\.\d+)?)M)?(?:(?<seconds>\d+(?:\.\d+)?)S)?)$/,
          duration
        )

      if captures && Enum.any?(Map.values(captures), &(&1 != "")) &&
           not String.ends_with?(duration, "T") do
        Enum.reduce([{"days", 86_400}, {"hours", 3600}, {"minutes", 60}, {"seconds", 1}], 0.0, fn
          {unit, multiplier}, total ->
            case Float.parse(captures[unit]) do
              {value, ""} -> total + value * multiplier
              _ -> total
            end
        end)
      end
    end

    def normalize_duration(duration) when is_binary(duration) do
      case Float.parse(duration) do
        {value, ""} when value >= 0 -> value
        _ -> nil
      end
    end

    def normalize_duration(_), do: nil

    defp calculate_aspect(width, height)
         when is_number(width) and is_number(height) and height > 0 do
      Float.round(width / height, 6)
    end

    defp calculate_aspect(_, _), do: nil

    defp parse_focus(focus) when is_binary(focus) do
      case String.split(focus, ",") do
        [x, y] -> %{"x" => parse_float(x), "y" => parse_float(y)}
        _ -> %{"x" => 0.0, "y" => 0.0}
      end
    end

    defp parse_focus(%{"x" => x, "y" => y}), do: %{"x" => x, "y" => y}
    defp parse_focus(%{x: x, y: y}), do: %{"x" => x, "y" => y}
    defp parse_focus(_), do: nil

    defp parse_float(str) when is_binary(str) do
      case Float.parse(str) do
        {f, _} -> f
        :error -> 0.0
      end
    end

    defp parse_float(num) when is_number(num), do: num
    defp parse_float(_), do: 0.0

    defp extract_description(media) do
      case get_fields(media, [:description, :label]) do
        nil ->
          metadata = get_field(media, :metadata) || %{}
          metadata["description"] || metadata["label"] || ""

        value ->
          value
      end
    end

    defp extract_blurhash(media) do
      metadata = get_field(media, :metadata) || %{}
      metadata["blurhash"]
    end
  end
end
