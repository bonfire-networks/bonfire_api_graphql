defmodule Bonfire.API.GraphQL.Plugs.RequireMastoScope do
  @moduledoc """
  Enforces the OAuth scopes of an access token on the Mastodon-compatible write endpoints (every non-GET/HEAD request), so a token granted only `read` cannot change anything.

  Which scope an endpoint needs follows the Mastodon API documentation (`write:follows`, `write:favourites`, `write:statuses`, ...). The parent scope `write` always suffices. Requests without a bearer token (the session of the web UI) are left to the usual session checks, as in `Bonfire.OpenID.Plugs.Authorize.require_token_scope/2`.

  Use it in a pipeline after the authorization has been loaded.
  """
  import Bonfire.Common.Extend, only: [maybe_module: 1]

  def init(opts), do: opts

  # TODO: enforce `read` / `read:*` on reads too (a token without any read scope can still read)
  def call(%Plug.Conn{method: method} = conn, _opts) when method in ["GET", "HEAD", "OPTIONS"],
    do: conn

  def call(conn, _opts) do
    if authorize = maybe_module(Bonfire.OpenID.Plugs.Authorize) do
      authorize.require_token_scope(conn, required_scopes(conn.path_info))
    else
      conn
    end
  end

  # scopes of which any one allows the write request to the given path segments (e.g. `["api", "v1", "statuses", id, "favourite"]`)
  defp required_scopes([_api, _version | path]), do: specific_scopes(path) ++ ["write"]
  defp required_scopes(_), do: ["write"]

  defp specific_scopes(["accounts", _id, action]) when action in ["follow", "unfollow"],
    do: ["write:follows", "follow"]

  defp specific_scopes(["accounts", _id, action]) when action in ["mute", "unmute"],
    do: ["write:mutes", "follow"]

  defp specific_scopes(["accounts", _id, action]) when action in ["block", "unblock"],
    do: ["write:blocks", "follow"]

  defp specific_scopes(["accounts" | _]), do: ["write:accounts"]
  defp specific_scopes(["profile" | _]), do: ["write:accounts"]
  defp specific_scopes(["featured_tags" | _]), do: ["write:accounts"]
  defp specific_scopes(["tokens" | _]), do: ["write:accounts"]
  defp specific_scopes(["follow_requests" | _]), do: ["write:follows", "follow"]
  defp specific_scopes(["tags", _name, _action]), do: ["write:follows", "follow"]

  defp specific_scopes(["statuses", _id, action]) when action in ["favourite", "unfavourite"],
    do: ["write:favourites"]

  defp specific_scopes(["statuses", _id, action]) when action in ["bookmark", "unbookmark"],
    do: ["write:bookmarks"]

  defp specific_scopes(["statuses" | _]), do: ["write:statuses"]
  defp specific_scopes(["polls" | _]), do: ["write:statuses"]
  defp specific_scopes(["markers" | _]), do: ["write:statuses"]
  defp specific_scopes(["notifications" | _]), do: ["write:notifications"]
  defp specific_scopes(["conversations" | _]), do: ["write:conversations"]
  defp specific_scopes(["lists" | _]), do: ["write:lists"]
  defp specific_scopes(["media" | _]), do: ["write:media"]
  defp specific_scopes(["reports" | _]), do: ["write:reports"]
  defp specific_scopes(["push" | _]), do: ["push"]
  defp specific_scopes(_), do: []
end
