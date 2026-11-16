# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.IntrospectionProdTest do
  @moduledoc """
  With public introspection switched off (the default in prod), the schema (`__schema` queries and `GET /api/schema`) is only for signed-in users. Ordinary public queries still work for guests.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_introspection_prod_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :graphql

  @introspection "{ __schema { queryType { name } } }"

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(%{query: query}))
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  setup do
    Process.put([:bonfire_api_graphql, :public_introspection], false)

    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})
    {:ok, token: token}
  end

  test "a public query still works for a guest", %{conn: conn} do
    assert get_in(body(graphql(conn, "{ __typename }")), ["data", "__typename"]) ==
             "RootQueryType"
  end

  test "a signed-in client can introspect", %{conn: conn, token: token} do
    resp = conn |> put_req_header("authorization", "Bearer #{token}") |> graphql(@introspection)

    assert get_in(body(resp), ["data", "__schema", "queryType", "name"]) == "RootQueryType"
  end

  test "a guest's __schema query is refused", %{conn: conn} do
    resp = graphql(conn, @introspection)

    assert get_in(body(resp), ["data", "__schema"]) == nil
    assert body(resp)["errors"] not in [nil, []]
  end

  test "GET /api/schema is refused to a guest and served to a signed-in client", %{
    conn: conn,
    token: token
  } do
    signed_in = conn |> put_req_header("authorization", "Bearer #{token}") |> get("/api/schema")

    # control: the SDL is served when allowed
    assert signed_in.status == 200
    assert signed_in.resp_body =~ "type RootQueryType"

    guest = get(conn, "/api/schema")

    assert guest.status in [401, 403]
    refute guest.resp_body =~ "type RootQueryType"
  end
end
