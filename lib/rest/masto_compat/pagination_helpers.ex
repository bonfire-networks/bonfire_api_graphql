if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.PaginationHelpers do
    @moduledoc """
    Shared pagination utilities for Mastodon-compatible REST API adapters.

    Provides consistent pagination handling across all Mastodon API endpoints:
    - Limit validation with configurable defaults and maximums
    - Cursor-based pagination parameter handling (max_id, since_id, min_id)
    - Link header generation for Mastodon-compatible pagination
    """

    alias Bonfire.Common.Enums

    @doc """
    Validate and normalize pagination limit.

    ## Options
    - `:default` - Default limit when nil or invalid (default: 40)
    - `:max` - Maximum allowed limit (default: 80)

    ## Examples

        iex> validate_limit(nil)
        40

        iex> validate_limit("20")
        20

        iex> validate_limit(100)
        80

        iex> validate_limit(nil, default: 20, max: 40)
        20
    """
    def validate_limit(limit, opts \\ [])

    def validate_limit(nil, opts), do: Keyword.get(opts, :default, 40)

    def validate_limit(limit, opts) when is_binary(limit) do
      case Integer.parse(limit) do
        {n, _} -> validate_limit(n, opts)
        :error -> Keyword.get(opts, :default, 40)
      end
    end

    def validate_limit(limit, opts) when is_integer(limit) do
      max = Keyword.get(opts, :max, 80)
      default = Keyword.get(opts, :default, 40)

      cond do
        limit > 0 and limit <= max -> limit
        limit > max -> max
        true -> default
      end
    end

    def validate_limit(_, opts), do: Keyword.get(opts, :default, 40)

    @doc """
    Build pagination opts from Mastodon-style params (max_id, since_id, min_id).

    Converts Mastodon cursor params to keyword list format for Bonfire queries.

    ## Examples

        iex> build_pagination_opts(%{"max_id" => "abc123"}, 20)
        [limit: 20, after: "abc123"]

        iex> build_pagination_opts(%{}, 40)
        [limit: 40]
    """
    def build_pagination_opts(params, limit) do
      [limit: limit]
      |> maybe_add_cursor(params, "max_id", :after)
      |> maybe_add_cursor(params, "since_id", :before)
      |> maybe_add_cursor(params, "min_id", :before)
    end

    @doc """
    Add cursor to opts if present in params.

    Works with both keyword list opts and map opts.

    ## Examples

        iex> maybe_add_cursor([limit: 20], %{"max_id" => "abc"}, "max_id", :after)
        [after: "abc", limit: 20]

        iex> maybe_add_cursor(%{limit: 20}, %{"max_id" => "abc"}, "max_id", :after)
        %{limit: 20, after: "abc"}
    """
    def maybe_add_cursor(opts, params, param_name, cursor_key) when is_list(opts) do
      case params[param_name] do
        cursor when is_binary(cursor) and cursor != "" ->
          Keyword.put(opts, cursor_key, cursor)

        _ ->
          opts
      end
    end

    def maybe_add_cursor(opts, params, param_name, cursor_key) when is_map(opts) do
      case params[param_name] do
        cursor when is_binary(cursor) and cursor != "" ->
          Map.put(opts, cursor_key, cursor)

        _ ->
          opts
      end
    end

    @doc """
    Add Mastodon-compatible Link headers for pagination.

    Generates RFC 5988 Link headers with `next` and `prev` relations
    using the page_info cursors from GraphQL responses.

    ## Options
    - `:cursor_field` - Field format for cursor encoding (default: {:activity, :id})

    ## Examples

        conn
        |> add_link_headers(%{}, page_info, items)
        # Sets Link header: <url?max_id=xyz>; rel="next", <url?min_id=abc>; rel="prev"
    """
    def add_link_headers(conn, _params, page_info, items, opts \\ []) do
      base_url = build_base_url(conn)
      base_params = Map.take(conn.params, ["limit"])

      cursor_field = Keyword.get(opts, :cursor_field) || extract_cursor_field(page_info)
      cursor_for_record_fun = get_field(page_info, :cursor_for_record_fun) || (&Enums.id/1)

      start_cursor =
        (get_field(page_info, :start_cursor) ||
           items |> List.first() |> then(&if &1, do: cursor_for_record_fun.(&1)))
        |> encode_cursor_for_link_header(cursor_field)

      end_cursor =
        (get_field(page_info, :end_cursor) ||
           items |> List.last() |> then(&if &1, do: cursor_for_record_fun.(&1)))
        |> encode_cursor_for_link_header(cursor_field)

      # Check if we're on the last page
      is_last_page = get_field(page_info, :final_cursor) != nil

      links = []

      # Add "next" link (older posts) using end_cursor
      links =
        if end_cursor && !is_last_page do
          query_params = base_params |> Map.put("max_id", end_cursor) |> URI.encode_query()
          next_link = "<#{base_url}?#{query_params}>; rel=\"next\""
          links ++ [next_link]
        else
          links
        end

      # Add "prev" link (newer posts) using start_cursor
      links =
        if start_cursor do
          query_params = base_params |> Map.put("min_id", start_cursor) |> URI.encode_query()
          prev_link = "<#{base_url}?#{query_params}>; rel=\"prev\""
          links ++ [prev_link]
        else
          links
        end

      if links != [] do
        conn
        |> Plug.Conn.put_resp_header("link", Enum.join(links, ", "))
        |> Plug.Conn.put_resp_header("access-control-expose-headers", "Link")
      else
        conn
      end
    end

    @doc """
    Simplified Link headers for adapters that use item IDs as cursors.

    Use this when cursors are simply object IDs rather than encoded Paginator cursors.
    """
    def add_simple_link_headers(conn, _params, page_info, items) do
      base_url = build_base_url(conn)
      base_params = Map.take(conn.params, ["limit"])

      start_cursor = get_simple_cursor(page_info, :start_cursor, items, :first)
      end_cursor = get_simple_cursor(page_info, :end_cursor, items, :last)

      links = []

      links =
        if end_cursor do
          query_params = base_params |> Map.put("max_id", end_cursor) |> URI.encode_query()
          next_link = "<#{base_url}?#{query_params}>; rel=\"next\""
          links ++ [next_link]
        else
          links
        end

      links =
        if start_cursor do
          query_params = base_params |> Map.put("min_id", start_cursor) |> URI.encode_query()
          prev_link = "<#{base_url}?#{query_params}>; rel=\"prev\""
          links ++ [prev_link]
        else
          links
        end

      if links != [] do
        conn
        |> Plug.Conn.put_resp_header("link", Enum.join(links, ", "))
        |> Plug.Conn.put_resp_header("access-control-expose-headers", "Link")
      else
        conn
      end
    end

    # ==========================================
    # Cursor Encoding Helpers
    # ==========================================

    @doc """
    Encode a cursor for use in Link headers.

    Handles:
    - nil cursors (returns nil)
    - Already-encoded base64 cursors (pass through)
    - Plain IDs (encode with cursor field format)
    - Map cursors (encode to base64)
    """
    def encode_cursor_for_link_header(nil, _cursor_field), do: nil

    def encode_cursor_for_link_header(cursor, _cursor_field) when is_map(cursor) do
      cursor
      |> :erlang.term_to_binary()
      |> Base.url_encode64()
    end

    def encode_cursor_for_link_header(cursor, cursor_field) when is_binary(cursor) do
      # Check if already base64 encoded (Paginator format starts with "g3")
      if String.match?(cursor, ~r/^g3[A-Za-z0-9_-]+=*$/) do
        cursor
      else
        # Plain ID - encode with specified cursor field format
        %{cursor_field => cursor}
        |> :erlang.term_to_binary()
        |> Base.url_encode64()
      end
    end

    @doc """
    Encode a plain ID as a cursor with a given field map.

    ## Examples

        iex> encode_cursor("abc123", %{id: "abc123"})
        {:ok, "base64_encoded_string"}
    """
    def encode_cursor(id, cursor_map) when is_binary(id) and is_map(cursor_map) do
      # Check if already encoded
      if String.match?(id, ~r/^g3[A-Za-z0-9_-]+=*$/) do
        {:ok, id}
      else
        try do
          cursor =
            cursor_map
            |> :erlang.term_to_binary()
            |> Base.url_encode64()

          {:ok, cursor}
        rescue
          _ -> {:error, :encoding_failed}
        end
      end
    end

    def encode_cursor(_, _), do: {:error, :invalid_id}

    # ==========================================
    # Feed Pagination Helpers (for Timeline endpoints)
    # ==========================================

    @doc """
    Build feed parameters from Mastodon-style params.

    Converts Mastodon timeline parameters to Bonfire GraphQL format:
    - Extracts and encodes pagination cursors (max_id, since_id, min_id)
    - Determines limit with first/last based on cursor direction
    - Atomizes pagination keys for GraphQL compatibility

    ## Options
    - `:default_limit` - Default limit when not specified (default: 20)
    - `:max_limit` - Maximum allowed limit (default: 40)

    ## Examples

        iex> build_feed_params(%{"limit" => "10", "max_id" => "abc"}, %{"feed_name" => "my"})
        %{filter: %{"feed_name" => "my", "time_limit" => 0}, after: "encoded...", first: 10}
    """
    def build_feed_params(params, filter, opts \\ []) do
      default_limit = Keyword.get(opts, :default_limit, 20)
      max_limit = Keyword.get(opts, :max_limit, 40)

      # Build filter without pagination cursors (cursors are top-level GraphQL args, not filters)
      filter_without_pagination =
        filter
        # Disable Bonfire's default 1-month time limit for Mastodon API
        |> Map.put("time_limit", 0)

      # Extract pagination cursors first to determine direction
      cursors = extract_pagination_cursors(params)

      # Atomize pagination keys because pagination_args_filter expects atom keys
      %{"filter" => filter_without_pagination}
      # Merge cursors at top level
      |> Map.merge(cursors)
      # Pass cursors to determine first vs last
      |> Map.merge(
        extract_limit_with_direction(params, cursors, default: default_limit, max: max_limit)
      )
      |> atomize_pagination_keys()
    end

    @doc """
    Extract pagination cursors from Mastodon-style params.

    Maps Mastodon pagination IDs to Relay cursor params:
    - max_id → after (items AFTER cursor in descending list = older/lower IDs)
    - since_id/min_id → before (items BEFORE cursor in descending list = newer/higher IDs)

    Cursors are encoded as base64 for GraphQL compatibility.
    """
    def extract_pagination_cursors(params) do
      params
      |> Map.take(["max_id", "since_id", "min_id"])
      |> Enum.reduce(%{}, fn
        {"max_id", id}, acc when is_binary(id) and id != "" ->
          # max_id: get older posts (items after cursor in descending list)
          case encode_cursor_for_graphql(id) do
            {:ok, cursor} -> Map.put(acc, "after", cursor)
            {:error, _reason} -> acc
          end

        {"min_id", id}, acc when is_binary(id) and id != "" ->
          # min_id: get newer posts (items before cursor in descending list)
          # min_id takes precedence over since_id
          case encode_cursor_for_graphql(id) do
            {:ok, cursor} -> Map.put(acc, "before", cursor)
            {:error, _reason} -> acc
          end

        {"since_id", id}, acc when is_binary(id) and id != "" ->
          # since_id: get newer posts (items before cursor in descending list)
          # Only use since_id if min_id not already set
          if Map.has_key?(acc, "before") do
            acc
          else
            case encode_cursor_for_graphql(id) do
              {:ok, cursor} -> Map.put(acc, "before", cursor)
              {:error, _reason} -> acc
            end
          end

        _, acc ->
          acc
      end)
    end

    @doc """
    Encode a cursor for GraphQL query parameters.

    Handles both already-encoded cursors and plain IDs:
    - Already base64 encoded (from Link headers) → validate and pass through
    - Plain ID (ULID) → create proper cursor map and encode

    Returns `{:ok, cursor}` or `{:error, reason}`.
    """
    def encode_cursor_for_graphql(id) when is_binary(id) do
      # Check if already base64 encoded (starts with "g3" from Erlang term format)
      if String.match?(id, ~r/^g3[A-Za-z0-9_-]+=*$/) do
        # Already encoded - validate it can be decoded
        validate_encoded_cursor(id)
      else
        # Plain ID - create cursor map matching Bonfire's cursor_fields format
        # cursor_fields: [{{:activity, :id}, :desc}]
        # cursor must be: %{{:activity, :id} => id}
        encode_plain_id_cursor(id)
      end
    end

    def encode_cursor_for_graphql(_), do: {:error, :invalid_cursor_format}

    @doc """
    Validate that an already-encoded cursor can be decoded properly.
    """
    def validate_encoded_cursor(cursor) do
      case Base.url_decode64(cursor) do
        {:ok, binary} ->
          # Try to decode the Erlang term to ensure it's valid
          try do
            _term = :erlang.binary_to_term(binary, [:safe])
            {:ok, cursor}
          rescue
            ArgumentError -> {:error, :invalid_erlang_term}
          end

        :error ->
          {:error, :invalid_base64}
      end
    end

    @doc """
    Encode a plain ULID as a cursor.

    Creates a cursor map matching Bonfire's cursor_fields format:
    `%{{:activity, :id} => id}`
    """
    def encode_plain_id_cursor(id) do
      try do
        cursor =
          %{{:activity, :id} => id}
          |> :erlang.term_to_binary()
          |> Base.url_encode64()

        {:ok, cursor}
      rescue
        e ->
          require Logger
          Logger.warning("Failed to encode cursor for ID #{inspect(id)}: #{inspect(e)}")
          {:error, :cursor_encoding_failed}
      end
    end

    @doc """
    Extract limit and determine pagination direction (first vs last).

    Relay pagination: "first" with "after", "last" with "before"
    With descending sort:
    - "after" + "first" = older posts (max_id)
    - "before" + "last" = newer posts (min_id/since_id)
    """
    def extract_limit_with_direction(params, cursors, opts \\ []) do
      default = Keyword.get(opts, :default, 20)
      max = Keyword.get(opts, :max, 40)

      limit = validate_limit(params["limit"], default: default, max: max)

      cond do
        Map.has_key?(cursors, "after") ->
          # Forward through descending list (older posts) - use "first"
          %{"first" => limit}

        Map.has_key?(cursors, "before") ->
          # Backward through descending list (newer posts) - use "last"
          %{"last" => limit}

        true ->
          # No cursor (initial page) - use "first" (start from newest)
          %{"first" => limit}
      end
    end

    @doc """
    Convert pagination param keys from strings to atoms.

    Pagination module expects atom keys for :after, :before, :first, :last.
    """
    def atomize_pagination_keys(params) do
      params
      |> Enum.map(fn
        {"after", val} -> {:after, val}
        {"before", val} -> {:before, val}
        {"first", val} -> {:first, val}
        {"last", val} -> {:last, val}
        # Keep other keys as-is
        {key, val} -> {key, val}
      end)
      |> Enum.into(%{})
    end

    # ==========================================
    # Private Helpers
    # ==========================================

    defp build_base_url(conn) do
      # Omit standard ports (80 for HTTP, 443 for HTTPS)
      port_part =
        case {conn.scheme, conn.port} do
          {"https", 443} -> ""
          {"http", 80} -> ""
          {_, port} -> ":#{port}"
        end

      "#{conn.scheme}://#{conn.host}#{port_part}#{conn.request_path}"
    end

    defp extract_cursor_field(page_info) when is_map(page_info) do
      case get_field(page_info, :cursor_fields) do
        [{field, _direction} | _] -> field
        [field | _] when is_atom(field) or is_tuple(field) -> field
        _ -> {:activity, :id}
      end
    end

    defp extract_cursor_field(_), do: {:activity, :id}

    defp get_field(map, key) when is_map(map) do
      Map.get(map, key) || Map.get(map, to_string(key))
    end

    defp get_field(_, _), do: nil

    defp get_simple_cursor(page_info, key, items, position) when is_map(page_info) do
      case Map.get(page_info, key) do
        nil ->
          item =
            case position do
              :first -> List.first(items)
              :last -> List.last(items)
            end

          if item, do: Map.get(item, "id") || Map.get(item, :id), else: nil

        cursor ->
          cursor
      end
    end

    defp get_simple_cursor(_, _, _, _), do: nil
  end
end
