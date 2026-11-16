# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.ScopeTest do
  @moduledoc """
  An OAuth token granted only the `read` scope cannot change anything through `/api/graphql`, just as it cannot through the Mastodon-compatible `/api/v1` writes: a mutation needs `write` (or a `write:*` scope).

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_scope_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false

  import Ecto.Query

  alias Bonfire.OpenID.Provider.ClientApps
  alias Boruta.Ecto.AccessTokens, as: AccessTokensAdapter
  import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

  @moduletag :graphql

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)

    {:ok, client} =
      ClientApps.new(%{
        id: Faker.UUID.v4(),
        name: "graphql-scope-#{Faker.UUID.v4()}",
        redirect_uris: ["http://localhost:4000/oauth/callback"]
      })

    {:ok, user: user, client: client}
  end

  defp token_for(user, client, scope) do
    {:ok, token} =
      AccessTokensAdapter.create(
        %{client: to_oauth_schema(client), sub: user.id, scope: scope},
        []
      )

    token.value
  end

  defp bearer(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp create_post(conn, text) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(
      "/api/graphql",
      Jason.encode!(%{
        query:
          ~s|mutation { createPost(postContent: {htmlBody: "#{text}"}, boundary: "public") { id } }|
      })
    )
  end

  defp stored?(text) do
    like = "%" <> text <> "%"

    Bonfire.Common.Repo.exists?(
      from(p in Bonfire.Data.Social.PostContent, where: like(p.html_body, ^like))
    )
  end

  test "control: the same read token is refused the equivalent write on /api/v1", %{
    conn: conn,
    user: user,
    client: client
  } do
    text = "rest-read-#{System.unique_integer([:positive])}"

    resp =
      conn
      |> bearer(token_for(user, client, "read"))
      |> put_req_header("accept", "application/json")
      |> post("/api/v1/statuses", %{"status" => text, "visibility" => "public"})

    assert resp.status == 403
    refute stored?(text)
  end

  test "control: a write token can create a post through GraphQL", %{
    conn: conn,
    user: user,
    client: client
  } do
    text = "gql-write-#{System.unique_integer([:positive])}"

    resp = conn |> bearer(token_for(user, client, "write")) |> create_post(text)

    assert get_in(Jason.decode!(resp.resp_body), ["data", "createPost", "id"])
    assert stored?(text)
  end

  test "a read-only token is refused a GraphQL mutation and nothing is written", %{
    conn: conn,
    user: user,
    client: client
  } do
    text = "gql-read-#{System.unique_integer([:positive])}"

    resp = conn |> bearer(token_for(user, client, "read")) |> create_post(text)

    body = Jason.decode!(resp.resp_body)
    assert resp.status in [401, 403] or is_list(body["errors"])
    assert get_in(body, ["data", "createPost"]) == nil
    refute stored?(text)
  end
end
