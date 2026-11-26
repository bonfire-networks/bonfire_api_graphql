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

    {:ok, api_conn: masto_api_conn(conn, user: user, account: account), user: user}
  end

  test "GET /api/v2/filters answers no filters", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v2/filters") |> json_response(200) == []
  end

  test "GET /api/v1/announcements answers no announcements", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v1/announcements") |> json_response(200) == []
  end

  test "GET /api/v1/trends answers as /api/v1/trends/tags", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v1/trends") |> json_response(200) ==
             api_conn |> get("/api/v1/trends/tags") |> json_response(200)
  end

  test "GET /api/v1/accounts/:id/endorsements answers no featured accounts", %{
    api_conn: api_conn,
    user: user
  } do
    assert api_conn |> get("/api/v1/accounts/#{user.id}/endorsements") |> json_response(200) ==
             []
  end

  test "GET /api/v1/endorsements answers no featured accounts", %{api_conn: api_conn} do
    assert api_conn |> get("/api/v1/endorsements") |> json_response(200) == []
  end

  # Mastodon iOS asks this at launch and decodes it as `[String: [String]]`, so the empty answer is an object, not a list
  test "GET /api/v1/instance/translation_languages answers no languages", %{api_conn: api_conn} do
    assert api_conn
           |> delete_req_header("accept")
           |> get("/api/v1/instance/translation_languages")
           |> json_response(200) == %{}
  end

  # Mastodon iOS and Ice Cubes send no Accept header, so an unknown path answered the HTML error page, which an app cannot read as an error (bonfire.cafe, 2026-11-26)
  describe "an unknown /api path with no Accept header" do
    test "answers a JSON 404", %{api_conn: api_conn} do
      assert %{"error" => _} =
               api_conn
               |> delete_req_header("accept")
               |> get("/api/v1/no_such_endpoint")
               |> json_response(404)
    end

    # Bonfire keeps per-user instance blocks, so an empty-list stub would tell a user who blocked instances that they have none (masto-api-json-404 decision 3)
    test "covers /api/v1/domain_blocks, which is not stubbed", %{api_conn: api_conn} do
      assert %{"error" => _} =
               api_conn
               |> delete_req_header("accept")
               |> get("/api/v1/domain_blocks")
               |> json_response(404)
    end
  end
end
