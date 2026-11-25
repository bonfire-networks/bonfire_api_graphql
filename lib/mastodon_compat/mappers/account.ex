if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Account do
    @moduledoc """
    Maps an account as GraphQL returns it (atom keys) to a Mastodon Account. Runs no query:
    counts and `follow_requests_count` are what the query selected, 0 when none.
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.Common.Text

    @doc """
    Transform a GraphQL account into a Mastodon Account.

    Returns nil if the input is nil, has no username, or is a struct (select the account in
    GraphQL instead).

    ## Options

    - `:include_source` - Add the reader's own `source` (with `follow_requests_count`)
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

    # structs are not read; warn only for an account struct (a post can arrive as a subject)
    def from_user(user, opts) when is_struct(user) do
      if Bonfire.API.MastoCompat.Accounts.account?(user),
        do:
          warn(
            Types.object_type(user),
            "Mappers.Account reads GraphQL output, not structs: select the account in GraphQL"
          )

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

    defp build_account(user, opts) do
      profile = extract_nested(user, :profile)
      character = extract_nested(user, :character)
      username = get_field(character, [:username])

      if is_nil(username) or username == "" do
        nil
      else
        peered = extract_nested(character, :peered)
        user_id = extract_id(user, character, profile)
        acct = get_field(character, [:acct]) || username
        display_name = get_field(profile, [:display_name, :name])
        note_raw = get_field(profile, [:note, :summary])
        note_html = Text.maybe_markdown_to_html(note_raw) || ""

        url =
          get_field(character, [:url, :canonical_uri]) ||
            get_field(peered, [:canonical_uri])

        avatar = resolve_avatar_url(user, profile)
        header = resolve_header_url(user, profile)

        created_at = extract_created_at(user)
        statuses_count = count_from(user, :statuses_count)
        followers_count = count_from(user, :followers_count)
        following_count = count_from(user, :following_count)
        indexable = Bonfire.Common.Extend.module_enabled?(Bonfire.Search.Indexer, user)

        # true when not selected (groups)
        discoverable = Map.get(user, :discoverable) != false

        account = %{
          "id" => to_string(user_id),
          "username" => username |> String.split("@", parts: 2) |> hd(),
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
          # Mastodon sends a date, not a datetime (`REST::AccountSerializer#last_status_at`): the date of the newest post, from `last_post_at`; nil when not selected or never posted (masto-live-fixes step 4)
          "last_status_at" => last_status_date(Map.get(user, :last_post_at))
        }

        if Keyword.get(opts, :include_source, false) do
          Map.put(account, "source", build_source(note_raw, user, indexable, discoverable))
        else
          account
        end
      end
    end

    defp extract_id(user, character, profile) do
      get_field(user, [:id]) ||
        get_field(character, [:id]) ||
        get_field(profile, [:id])
    end

    # Differs from Helpers.get_field/2: also treats "" as nil for account field extraction
    defp get_field(nil, _keys), do: nil
    defp get_field(_map, []), do: nil

    defp get_field(map, keys) when is_map(map) and is_list(keys) do
      Enum.find_value(keys, fn key ->
        case Map.get(map, key) do
          "" -> nil
          value -> value
        end
      end)
    end

    defp get_field(_, _), do: nil

    defp extract_nested(nil, _key), do: %{}
    defp extract_nested(%{} = map, key) when map_size(map) == 0, do: %{}

    defp extract_nested(parent, key) when is_atom(key) and is_map(parent) do
      case Map.get(parent, key) do
        data when is_map(data) -> data
        _ -> %{}
      end
    end

    defp extract_nested(_, _), do: %{}

    defp resolve_avatar_url(user, profile) do
      case get_field(profile, [:avatar]) do
        url when is_binary(url) and url != "" ->
          Bonfire.Common.URIs.based_url(url)

        _ ->
          Bonfire.Common.Media.avatar_url(user)
          |> Bonfire.Common.URIs.based_url()
      end
    end

    defp resolve_header_url(user, profile) do
      case get_field(profile, [:header]) do
        url when is_binary(url) and url != "" ->
          Bonfire.Common.URIs.based_url(url)

        _ ->
          # Use banner_url (not image_url which can return icon/avatar for federated users)
          case Bonfire.Common.Media.banner_url(user) do
            url when is_binary(url) and url != "" ->
              Bonfire.Common.URIs.based_url(url)

            _ ->
              Bonfire.Common.URIs.base_url() <> "/images/bonfire-icon.png"
          end
      end
    end

    defp extract_created_at(user) do
      case get_field(user, [:created_at]) do
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

    defp last_status_date(%DateTime{} = at), do: at |> DateTime.to_date() |> Date.to_iso8601()
    defp last_status_date(at) when is_binary(at), do: String.slice(at, 0, 10)
    defp last_status_date(_), do: nil

    defp count_from(user, key) do
      case Map.get(user, key) do
        count when is_integer(count) -> count
        _ -> 0
      end
    end

    defp build_source(note_raw, user, indexable, discoverable) do
      %{
        "indexable" => indexable,
        "discoverable" => discoverable,
        "note" => note_raw || "",
        "follow_requests_count" => count_from(user, :follow_requests_count),
        "hide_collections" => false,
        "attribution_domains" => [],
        # the reader's default visibility, put on the input by the adapter (`default_privacy`), as `follow_requests_count` is
        "privacy" => Map.get(user, :default_privacy) || "public",
        "sensitive" => false,
        "language" => "",
        "fields" => []
      }
    end
  end
end
