# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.AltairHelpers do
  @moduledoc """
  Runtime helpers for AbsintheAltair configuration resolved per-request.
  """

  @doc "Returns the WebSocket subscription URL derived from the current request's host and scheme."
  def subscriptions_url(conn) do
    ws_scheme = if conn.scheme == :https, do: "wss", else: "ws"

    port_suffix =
      case {conn.scheme, conn.port} do
        {:https, 443} -> ""
        {:http, 80} -> ""
        {_, port} -> ":#{port}"
      end

    "#{ws_scheme}://#{conn.host}#{port_suffix}/socket/websocket"
  end
end
