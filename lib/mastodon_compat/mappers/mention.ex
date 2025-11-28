if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Mention do
    @moduledoc """
    Maps Bonfire Tag objects (with character associations) to Mastodon Mention format.

    Per the Mastodon OpenAPI spec (mastodon-openapi.yaml lines 1862-1895), a Mention
    represents a mention of a user within the content of a status.

    ## Required Fields (all required per spec)

    - `id` (string) - The account id of the mentioned user
    - `username` (string) - The username of the mentioned user
    - `acct` (string) - The webfinger acct: URI (username for local, username@domain for remote)
    - `url` (string, uri) - The location of the mentioned user's profile

    ## Usage

        # Transform a single tag to mention
        Mappers.Mention.from_tag(tag)

        # Transform a list of tags to mentions (filters out non-mentions)
        Mappers.Mention.from_tags(tags, current_user: user)
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.Helpers

    import Helpers, only: [get_field: 2]

    @doc """
    Transform a list of Bonfire tags to Mastodon Mention objects.

    Filters to only include tags that represent user mentions (have a character association).
    Excludes the current user from mentions if provided in opts.

    ## Options

    - `:current_user` - The current user to exclude from mentions (optional)

    ## Examples

        iex> from_tags(tags, current_user: user)
        [%{"id" => "123", "username" => "alice", ...}]
    """
    def from_tags(tags, opts \\ [])

    def from_tags(nil, _opts), do: []
    def from_tags([], _opts), do: []

    def from_tags(tags, opts) when is_list(tags) do
      current_user = Keyword.get(opts, :current_user)
      current_user_id = if current_user, do: id(current_user), else: nil

      tags
      |> Enum.flat_map(fn tag ->
        # Only process tags that have character data (mentions)
        if is_mention_tag?(tag) do
          # Exclude current user from mentions
          tag_id = get_tag_user_id(tag)

          if tag_id && tag_id != current_user_id do
            case from_tag(tag) do
              nil -> []
              mention -> [mention]
            end
          else
            []
          end
        else
          []
        end
      end)
    end

    def from_tags(_, _opts), do: []

    @doc """
    Transform a single Bonfire tag (with character) to a Mastodon Mention.

    Returns nil if the tag doesn't represent a user mention or is missing required data.

    ## Examples

        iex> from_tag(tag_with_character)
        %{"id" => "123", "username" => "alice", "acct" => "alice", "url" => "https://..."}

        iex> from_tag(hashtag)
        nil
    """
    def from_tag(nil), do: nil

    def from_tag(tag) when is_map(tag) do
      # Extract character data from the tag
      # Tags can have character data in different places depending on how they were loaded
      character = extract_character(tag)

      if character do
        build_mention(tag, character)
      else
        nil
      end
    end

    def from_tag(_), do: nil

    # Private functions

    # Check if a tag represents a user mention (has character association)
    defp is_mention_tag?(tag) do
      character = extract_character(tag)
      not is_nil(character) && map_size(character) > 0
    end

    # Get the user ID from a tag (for filtering out current user)
    defp get_tag_user_id(tag) do
      # The tag_id points to the mentioned user
      get_field(tag, :tag_id) ||
        get_field(tag, :id) ||
        extract_character(tag) |> get_field(:id)
    end

    # Extract character data from tag structure
    # Handles different loading scenarios (preloaded vs nested)
    defp extract_character(tag) do
      # Try direct character association first
      char = get_field(tag, :character)

      case char do
        %Ecto.Association.NotLoaded{} ->
          # Not preloaded - try to get from the tag pointer itself
          extract_from_pointer(tag)

        nil ->
          # Try alternative paths
          extract_from_pointer(tag)

        char when is_map(char) and map_size(char) > 0 ->
          char

        _ ->
          nil
      end
    end

    # Extract character-like data from the tag's pointer/profile
    defp extract_from_pointer(tag) do
      # The tag itself might point to a user with character data
      # Try to get username/canonical_uri from nested structures
      profile = get_field(tag, :profile)
      pointer = get_field(tag, :tag) || get_field(tag, :pointer)

      cond do
        # Check if pointer has character data
        pointer && get_field(pointer, :character) ->
          get_field(pointer, :character)

        # Check if pointer itself has username (is a character)
        pointer && get_field(pointer, :username) ->
          pointer

        # Check profile for character-like data
        profile && get_field(profile, :username) ->
          profile

        # Tag itself might have the data we need
        get_field(tag, :username) ->
          tag

        true ->
          nil
      end
    end

    # Build the Mention map from tag and character data
    defp build_mention(tag, character) do
      # Extract required fields
      user_id = get_field(tag, :tag_id) || get_field(character, :id) || get_field(tag, :id)
      username = get_field(character, :username)
      canonical_uri = get_field(character, :canonical_uri)

      # Validate we have minimum required data
      if user_id && username do
        # Build acct - username for local, username@domain for remote
        acct = build_acct(username, canonical_uri)

        # Build URL - use canonical_uri or construct from username
        url = canonical_uri || build_profile_url(username)

        %{
          "id" => to_string(user_id),
          "username" => username,
          "acct" => acct,
          "url" => url
        }
      else
        warn(
          %{tag_id: get_field(tag, :id), has_username: !is_nil(username)},
          "Mention tag missing required data"
        )

        nil
      end
    end

    # Build the acct field (username for local, username@domain for remote)
    defp build_acct(username, canonical_uri) when is_binary(canonical_uri) do
      # Try to extract domain from canonical_uri
      case URI.parse(canonical_uri) do
        %URI{host: host} when is_binary(host) ->
          # Check if this is a local user by comparing to instance domain
          local_host = Bonfire.Common.URIs.base_domain()

          if host == local_host do
            username
          else
            "#{username}@#{host}"
          end

        _ ->
          username
      end
    end

    defp build_acct(username, _), do: username

    # Build a profile URL from username (fallback for local users)
    defp build_profile_url(username) do
      base_url = Bonfire.Common.URIs.base_url()
      "#{base_url}/@#{username}"
    end
  end
end
