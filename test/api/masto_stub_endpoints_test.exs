# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.StubEndpointsTest do
  @moduledoc """
  Endpoints Phanpy and Elk call at start, for features Bonfire does not have yet: they answered an HTML 404 without CORS headers, which a browser client cannot read (live testing, masto-live-fixes step 3).

  Run with: just test extensions/bonfire_api_graphql/test/api/masto_stub_endpoints_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :masto_api

  setup %{conn: conn} do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)

    {:ok, api_conn: masto_api_conn(conn, user: user, account: account)}
  end

  test "GET /api/v2/filters answers no filters", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v2/filters") |> json_response(200) == []
  end

  test "GET /api/v1/announcements answers no announcements", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v1/announcements") |> json_response(200) == []
  end
end
