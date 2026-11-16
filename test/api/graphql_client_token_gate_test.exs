# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.ClientTokenGateTest do
  @moduledoc """
  A token that belongs to an app and no user (what anyone gets by registering an app at `/api/v1/apps` and asking `/oauth/token` for a `client_credentials` token) is a guest to the GraphQL log-in gate: a field that is not public gives it the log-in error and no data, exactly as with no token at all.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_client_token_gate_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false

  @moduletag :graphql

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(%{query: query}))
  end

  defp body(conn), do: Jason.decode!(conn.resp_body)

  defp error_messages(conn),
    do: conn |> body() |> Map.get("errors", []) |> Enum.map(&Map.get(&1, "message"))

  # `likersOf` is not a public field and its resolver returns the likers of a public post to a guest-level context
  defp likers_query(post), do: ~s|{ likersOf(id: "#{post.id}") { id } }|

  setup do
    # the real token endpoint, not the mock the test environment defaults to
    previous = Application.get_env(:bonfire_open_id, :oauth_module)
    Application.put_env(:bonfire_open_id, :oauth_module, Boruta.Oauth)
    on_exit(fn -> Application.put_env(:bonfire_open_id, :oauth_module, previous) end)

    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    liker = Bonfire.Me.Fake.fake_user!()

    post =
      Bonfire.Posts.Fake.fake_post!(user, "public", %{post_content: %{html_body: "a public post"}})

    {:ok, _like} = Bonfire.Social.Likes.like(liker, post)

    {:ok, account: account, user: user, liker: liker, post: post}
  end

  # the real path of an anonymous visitor: register an app, then ask for an app-only token
  defp app_only_token do
    app =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> post(
        "/api/v1/apps",
        Jason.encode!(%{
          "client_name" => "client token gate test #{Faker.UUID.v4()}",
          "redirect_uris" => "https://client.local/callback",
          "scopes" => "read"
        })
      )
      |> json_response(200)

    token =
      build_conn()
      |> post("/oauth/token", %{
        "grant_type" => "client_credentials",
        "client_id" => app["client_id"],
        "client_secret" => app["client_secret"],
        "scope" => "read"
      })
      |> json_response(200)

    token["access_token"]
  end

  test "control: a guest asking for a login-only field gets the log-in error and no data", %{
    conn: conn,
    post: post
  } do
    resp = graphql(conn, likers_query(post))

    assert Enum.any?(error_messages(resp), &String.contains?(&1, "log in"))
    assert get_in(body(resp), ["data", "likersOf"]) == nil
  end

  test "control: a signed-in user's token gets the data", %{
    conn: conn,
    account: account,
    user: user,
    liker: liker,
    post: post
  } do
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})

    resp =
      conn |> put_req_header("authorization", "Bearer #{token}") |> graphql(likers_query(post))

    refute Enum.any?(error_messages(resp), &String.contains?(&1, "log in"))
    assert [%{"id" => id}] = get_in(body(resp), ["data", "likersOf"])
    assert id == liker.id
  end

  test "a token with no user gets the log-in error and no data", %{conn: conn, post: post} do
    token = app_only_token()
    assert is_binary(token)

    resp =
      conn |> put_req_header("authorization", "Bearer #{token}") |> graphql(likers_query(post))

    assert Enum.any?(error_messages(resp), &String.contains?(&1, "log in"))
    assert get_in(body(resp), ["data", "likersOf"]) == nil
  end
end
