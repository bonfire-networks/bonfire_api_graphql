# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoCompat.Test.ValidateResponse do
  @moduledoc """
  A plug for tests, in the `:masto_api` pipeline in the test env only: when enabled, each 200 JSON response of a Mastodon API route is checked against the response schema the Mastodon spec gives for that route (see `Bonfire.API.MastoCompat.Test.MastoSchema.assert_masto_response/3`), and the test making the request fails on any problem. So every test that calls the API checks the shape of what it gets back.

  Enabled with `MASTO_VALIDATE=1` (read by `Bonfire.API.GraphQL.RuntimeConfig`), or in a test with `Process.put([:bonfire_api_graphql, #{inspect(__MODULE__)}, :enabled], true)`.
  """

  @behaviour Plug

  require Bonfire.Common.Config
  alias Bonfire.API.MastoCompat.Test.MastoSchema

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if Bonfire.Common.Config.get([__MODULE__, :enabled], false) do
      Plug.Conn.register_before_send(conn, &validate/1)
    else
      conn
    end
  end

  defp validate(%Plug.Conn{status: 200} = conn) do
    with true <- json?(conn),
         %{route: route} <-
           Phoenix.Router.route_info(
             conn.private.phoenix_router,
             conn.method,
             conn.request_path,
             conn.host
           ) do
      conn.resp_body
      |> IO.iodata_to_binary()
      |> Jason.decode!()
      |> MastoSchema.assert_masto_response(conn.method, route)
    end

    conn
  end

  defp validate(conn), do: conn

  defp json?(conn) do
    conn
    |> Plug.Conn.get_resp_header("content-type")
    |> Enum.any?(&String.starts_with?(&1, "application/json"))
  end
end
