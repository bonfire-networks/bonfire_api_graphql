# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.AuthGateTest do
  @moduledoc """
  A field that has not been marked public needs a signed-in user (or an authorised API client), whatever its resolver does. A guest asking for one gets the log-in error rather than data.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_auth_gate_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :graphql

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(%{query: query}))
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  defp error_messages(conn),
    do: conn |> body() |> Map.get("errors", []) |> Enum.map(&Map.get(&1, "message"))

  defp user_query(user),
    do: ~s|{ user(filter: {username: "#{user.character.username}"}) { id } }|

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})
    {:ok, account: account, user: user, token: token}
  end

  test "a signed-in client can look a user up", %{conn: conn, user: user, token: token} do
    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> graphql(user_query(user))

    assert get_in(body(resp), ["data", "user", "id"]) == user.id
  end

  test "a guest can read a public profile, as in the web UI", %{conn: conn, user: user} do
    resp = graphql(conn, user_query(user))

    refute Enum.any?(error_messages(resp), &String.contains?(&1, "log in"))
    assert get_in(body(resp), ["data", "user", "id"]) == user.id
  end

  test "a guest asking for a login-only field gets the log-in error and no data", %{conn: conn} do
    resp = graphql(conn, ~s|{ searchUsers(filter: {query: "a"}) { id } }|)

    assert Enum.any?(error_messages(resp), &String.contains?(&1, "log in"))
    assert get_in(body(resp), ["data", "searchUsers"]) == nil
  end

  test "fields meant for guests stay open", %{conn: conn} do
    resp =
      graphql(
        conn,
        ~s|mutation { login(emailOrUsername: "nobody@example.local", password: "wrong") { token } }|
      )

    refute Enum.any?(error_messages(resp), &String.contains?(&1, "log in first"))
    assert resp.status == 200
  end
end
