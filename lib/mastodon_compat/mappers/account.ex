if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Account do
    @moduledoc """
    Maps Bonfire User objects to Mastodon Account format.

    This module is the single source of truth for transforming Bonfire users
    into Mastodon-compatible account objects. It handles:
    - Field extraction from both GraphQL responses (aliased names) and Ecto structs (schema names)
    - Stats computation (with options to skip or use preloaded values)
    - Building the final flat Mastodon account structure

    ## Usage

        # Basic account transformation
        Mappers.Account.from_user(user)

        # Skip expensive stats for list endpoints
        Mappers.Account.from_user(user, skip_expensive_stats: true)

        # Use preloaded stats (batch loading optimization)
        Mappers.Account.from_user(user, follow_counts: %{followers: 10, following: 5}, status_count: 42)
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.Common.Text

    @doc """
    Transform a Bonfire User into a Mastodon Account.

    Returns nil if the user is nil or invalid.

    ## Options

    - `:skip_expensive_stats` - Skip computing expensive stats (statuses_count,
      followers_count, following_count, follow_requests_count). Use for list endpoints
      where these counts are not displayed. Default: false
    - `:follow_counts` - Pre-loaded follow counts map with :followers and :following keys
    - `:status_count` - Pre-loaded status count integer
    - `:current_user` - Current user context (for settings lookups)
    - `:fallback_return` - Value to return on error (default: nil)

    ## Examples

        iex> from_user(%{id: "123", character: %{username: "alice"}})
        %{"id" => "123", "username" => "alice", ...}

        iex> from_user(nil)
        nil
    """
    def from_user(user, opts \\ [])

    def from_user(nil, _opts), do: nil

    def from_user(user, opts) when is_map(user) and map_size(user) == 0 do
      Keyword.get(opts, :fallback_return, nil)
    end

    def from_user(user, opts) when is_map(user) do
      case build_account(user, opts) do
        %{"id" => id} = account when not is_nil(id) ->
          account

        _ ->
          warn(user, "Failed to build valid account - missing id")
          Keyword.get(opts, :fallback_return, nil)
      end
    end

    def from_user(_, opts), do: Keyword.get(opts, :fallback_return, nil)

    @doc """
    Same as from_user/2 but raises on invalid input.
    """
    def from_user!(user, opts \\ []) do
      case from_user(user, opts) do
        nil -> raise Bonfire.Fail, :not_found
        account -> account
      end
    end

    @doc """
    Checks if an account object is valid (non-nil and has ID).
    """
    def valid?(account) do
      is_map(account) && (Map.has_key?(account, :id) || Map.has_key?(account, "id"))
    end

    defp build_account(user, opts) do
      profile = extract_nested(user, :profile)
      character = extract_nested(user, :character)
      username = get_field(character, [:username, "username"])

      # Return nil for users without username (BatchLoader will filter these out)
      if is_nil(username) or username == "" do
        nil
      else
        peered = extract_nested(character, :peered) || extract_nested(user, :peered)
        user_id = extract_id(user, character, profile)
        acct = get_field(character, [:acct, "acct"]) || username
        display_name = get_field(profile, [:display_name, "display_name", :name, "name"])
        note_raw = get_field(profile, [:note, "note", :summary, "summary", :bio, "bio"])
        note_html = Text.maybe_markdown_to_html(note_raw) || ""

        url =
          get_field(character, [:url, "url", :canonical_uri, "canonical_uri"]) ||
            get_field(peered, [:canonical_uri, "canonical_uri"]) ||
            compute_canonical_url(user, character)

        avatar = extract_media_url(profile, [:avatar, "avatar", :icon, "icon"]) || default_avatar()
        header = extract_media_url(profile, [:header, "header", :image, "image"]) || default_header()
        created_at = extract_created_at(user)
        {statuses_count, followers_count, following_count} = compute_stats(user, opts)
        indexable = Bonfire.Common.Extend.module_enabled?(Bonfire.Search.Indexer, user)

        discoverable =
          Bonfire.Common.Settings.get([Bonfire.Me.Users, :undiscoverable], nil,
            current_user: user
          ) !=
            true

        %{
          "id" => to_string(user_id),
          "username" => username || "",
          "acct" => acct || "",
          "display_name" => display_name || "",
          "note" => note_html,
          "url" => url || "",
          "uri" => url,
          "avatar" => avatar,
          "avatar_static" => avatar,
          "header" => header,
          "header_static" => header,
          "created_at" => created_at,
          "statuses_count" => statuses_count,
          "followers_count" => followers_count,
          "following_count" => following_count,
          "indexable" => indexable,
          "discoverable" => discoverable,
          "source" => build_source(note_raw, user, opts, indexable, discoverable),
          "locked" => false,
          "bot" => false,
          "group" => false,
          "noindex" => not indexable,
          "suspended" => false,
          "limited" => false,
          "moved" => nil,
          "memorial" => nil,
          "fields" => [],
          "emojis" => [],
          "roles" => [],
          "hide_collections" => false,
          "last_status_at" => created_at
        }
      end
    end

    defp extract_id(user, character, profile) do
      get_field(user, [:id, "id"]) ||
        get_field(character, [:id, "id"]) ||
        get_field(profile, [:id, "id"])
    end

    defp get_field(nil, _keys), do: nil
    defp get_field(_map, []), do: nil

    defp get_field(map, keys) when is_map(map) and is_list(keys) do
      Enum.find_value(keys, fn key ->
        case Map.get(map, key) do
          %Ecto.Association.NotLoaded{} -> nil
          "" -> nil
          value -> value
        end
      end)
    end

    defp get_field(_, _), do: nil

    defp extract_nested(nil, _key), do: %{}
    defp extract_nested(%{} = map, key) when map_size(map) == 0, do: %{}

    defp extract_nested(parent, key) when is_atom(key) and is_map(parent) do
      value = Map.get(parent, key) || Map.get(parent, Atom.to_string(key))

      case value do
        %Ecto.Association.NotLoaded{} -> %{}
        nil -> %{}
        data when is_struct(data) -> Map.from_struct(data)
        data when is_map(data) -> data
        _ -> %{}
      end
    end

    defp extract_nested(_, _), do: %{}

    defp extract_media_url(map, keys) do
      media = get_field(map, keys)
      do_extract_media_url(media)
    end

    defp do_extract_media_url(nil), do: nil
    defp do_extract_media_url(%Ecto.Association.NotLoaded{}), do: nil
    defp do_extract_media_url(url) when is_binary(url), do: url

    defp do_extract_media_url(media) when is_struct(media) do
      Map.get(media, :path) || Map.get(media, :url)
    end

    defp do_extract_media_url(media) when is_map(media) do
      Map.get(media, :path) || Map.get(media, :url) ||
        Map.get(media, "path") || Map.get(media, "url")
    end

    defp do_extract_media_url(_), do: nil

    defp extract_created_at(user) do
      case get_field(user, [:created_at, "created_at"]) do
        %DateTime{} = dt ->
          DateTime.to_iso8601(dt)

        iso when is_binary(iso) ->
          iso

        _ ->
          DatesTimes.date_from_pointer(user)
          |> case do
            %DateTime{} = dt -> DateTime.to_iso8601(dt)
            _ -> DateTime.utc_now() |> DateTime.to_iso8601()
          end
      end
    end

    defp compute_canonical_url(user, character) do
      # Compute URL using URIs.canonical_url when not found in stored data
      Bonfire.Common.URIs.canonical_url(character, preload_if_needed: false) ||
        Bonfire.Common.URIs.canonical_url(user, preload_if_needed: false)
    rescue
      _ -> nil
    end

    defp compute_stats(user, opts) do
      skip = Keyword.get(opts, :skip_expensive_stats, false)
      preloaded_follows = Keyword.get(opts, :follow_counts)
      preloaded_status = Keyword.get(opts, :status_count)

      cond do
        skip ->
          {0, 0, 0}

        preloaded_follows && preloaded_status != nil ->
          {
            preloaded_status,
            Map.get(preloaded_follows, :followers, 0),
            Map.get(preloaded_follows, :following, 0)
          }

        preloaded_follows ->
          {
            get_statuses_count(user),
            Map.get(preloaded_follows, :followers, 0),
            Map.get(preloaded_follows, :following, 0)
          }

        true ->
          {get_statuses_count(user), get_followers_count(user), get_following_count(user)}
      end
    end

    defp get_followers_count(user) do
      user_id = Bonfire.Common.Types.uid(user)

      if user_id do
        user
        |> Bonfire.Common.Repo.maybe_preload(:follow_count, follow_pointers: false)
        |> e(:follow_count, :object_count, 0)
      else
        0
      end
    end

    defp get_following_count(user) do
      user_id = Bonfire.Common.Types.uid(user)

      if user_id do
        user
        |> Bonfire.Common.Repo.maybe_preload(:follow_count, follow_pointers: false)
        |> e(:follow_count, :subject_count, 0)
      else
        0
      end
    end

    defp get_statuses_count(user) do
      user_id = Bonfire.Common.Types.uid(user)

      if user_id do
        import Ecto.Query

        Bonfire.Common.Repo.one(
          from(c in Bonfire.Data.Social.Created,
            join: p in Bonfire.Data.Social.Post,
            on: c.id == p.id,
            where: c.creator_id == ^user_id,
            select: count(c.id)
          )
        ) || 0
      else
        0
      end
    end

    defp get_follow_requests_count(user) do
      user_id = Bonfire.Common.Types.uid(user)

      if user_id do
        import Ecto.Query
        alias Bonfire.Data.Social.Request
        alias Bonfire.Data.Social.Follow

        Bonfire.Common.Repo.one(
          from(r in Request,
            join: e in assoc(r, :edge),
            where: e.object_id == ^user_id,
            where: e.table_id == ^Needle.Tables.id!(Follow),
            where: is_nil(r.ignored_at),
            select: count(r.id)
          )
        ) || 0
      else
        0
      end
    end

    defp build_source(note_raw, user, opts, indexable, discoverable) do
      skip_expensive = Keyword.get(opts, :skip_expensive_stats, false)

      %{
        "indexable" => indexable,
        "discoverable" => discoverable,
        "note" => note_raw || "",
        "follow_requests_count" =>
          if(skip_expensive, do: 0, else: get_follow_requests_count(user)),
        "hide_collections" => false,
        "attribution_domains" => [],
        "privacy" => "public",
        "sensitive" => false,
        "language" => "",
        "fields" => []
      }
    end

    defp default_avatar do
      Bonfire.Common.URIs.base_url() <> "/images/avatar.png"
    end

    defp default_header do
      Bonfire.Common.URIs.base_url() <> "/images/bonfire-icon.png"
    end
  end
end
