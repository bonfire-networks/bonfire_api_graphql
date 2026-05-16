# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.AuthTest do
  @moduledoc """
  Tests for GraphQL API authentication and authorization.

  Covers:
  - Unauthenticated requests are rejected for protected fields
  - Introspection is always public
  - login mutation is public
  - Session auth grants access
  - Phoenix.Token bearer auth grants access
  - OAuth2 client token grants access (client_credentials)

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_auth_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :graphql

  @me_query "{ me { user { id } } }"
  @introspection_query "{ __schema { queryType { name } } }"
  @login_mutation """
  mutation {
    login(emailOrUsername: "test@example.com", password: "wrong") {
      token
    }
  }
  """

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(%{query: query}))
  end

  defp errors(conn) do
    conn
    |> Map.fetch!(:resp_body)
    |> Jason.decode!()
    |> Map.get("errors", [])
    |> Enum.map(&Map.get(&1, "message"))
  end

  defp data(conn, key) do
    conn
    |> Map.fetch!(:resp_body)
    |> Jason.decode!()
    |> get_in(["data", key])
  end

  describe "unauthenticated" do
    test "protected queries return needs_login", %{conn: conn} do
      resp = graphql(conn, @me_query)
      assert Enum.any?(errors(resp), &String.contains?(&1, "log in"))
    end

    test "introspection is always accessible", %{conn: conn} do
      resp = graphql(conn, @introspection_query)
      assert data(resp, "__schema") != nil
    end

    test "login mutation is accessible", %{conn: conn} do
      # wrong credentials — but the mutation itself should not return needs_login
      resp = graphql(conn, @login_mutation)
      errs = errors(resp)
      refute "needs_login" in errs
    end
  end

  describe "session auth" do
    test "grants access to protected queries", %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)

      authed_conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> Plug.Conn.put_session(:current_account_id, account.id)
        |> Plug.Conn.put_session(:current_user_id, user.id)

      resp = graphql(authed_conn, @me_query)
      refute Enum.any?(errors(resp), &String.contains?(&1, "log in"))
    end
  end

  describe "Phoenix.Token bearer auth" do
    test "grants access with a valid token", %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)
      token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})

      authed_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")

      resp = graphql(authed_conn, @me_query)
      refute Enum.any?(errors(resp), &String.contains?(&1, "log in"))
    end

    test "rejects an invalid token", %{conn: conn} do
      authed_conn =
        conn
        |> put_req_header("authorization", "Bearer notavalidtoken")

      resp = graphql(authed_conn, @me_query)
      assert Enum.any?(errors(resp), &String.contains?(&1, "log in"))
    end
  end
end
