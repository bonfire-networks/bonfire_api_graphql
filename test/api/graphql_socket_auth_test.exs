# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.SocketAuthTest do
  @moduledoc """
  The GraphQL websocket (`/api/socket`) must not take identity from unauthenticated connect params.

  A client that merely knows (or guesses) an account id and username must not be able to run queries as that user. Such a socket must be treated as not logged in.

  The socket has no token or session auth path of its own, so the control uses the authenticated HTTP `/api/graphql` endpoint (bearer token) with the same query.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_socket_auth_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true
  require Phoenix.ChannelTest
  import Phoenix.ChannelTest, only: [assert_reply: 4]

  @moduletag :graphql

  @socket Bonfire.API.GraphQL.UserSocket
  @me_query "{ me { user { id } } }"

  defp socket_me(params, connect_info \\ %{}) do
    {:ok, socket} = Phoenix.ChannelTest.connect(@socket, params, connect_info: connect_info)

    {:ok, _reply, socket} =
      Phoenix.ChannelTest.subscribe_and_join(socket, "__absinthe__:control", %{})

    ref = Phoenix.ChannelTest.push(socket, "doc", %{"query" => @me_query})
    assert_reply ref, _status, payload, 5_000
    payload
  end

  defp payload_errors(payload) do
    payload |> Map.get(:errors, []) |> Enum.map(&to_string(Map.get(&1, :message)))
  end

  defp payload_user_id(payload), do: get_in(payload, [:data, "me", "user", "id"])

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    {:ok, account: account, user: user}
  end

  test "socket with only victim account id and username in connect params is not logged in", %{
    account: account,
    user: user
  } do
    payload =
      socket_me(%{
        "current_account_id" => account.id,
        "current_username" => user.character.username
      })

    refute payload_user_id(payload) == user.id
    assert Enum.any?(payload_errors(payload), &String.contains?(&1, "log in"))
  end

  test "socket with only victim account id in connect params is not logged in", %{
    account: account,
    user: user
  } do
    payload = socket_me(%{"current_account_id" => account.id})

    refute payload_user_id(payload) == user.id
    assert Enum.any?(payload_errors(payload), &String.contains?(&1, "log in"))
  end

  test "socket with a valid bearer token as `token` connect param gets the user", %{
    account: account,
    user: user
  } do
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})

    assert payload_user_id(socket_me(%{"token" => token})) == user.id
  end

  test "socket with a valid bearer token in the Authorization header gets the user", %{
    account: account,
    user: user
  } do
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})

    payload =
      socket_me(%{}, %{x_headers: [{"authorization", "Bearer #{token}"}]})

    assert payload_user_id(payload) == user.id
  end

  test "socket with an invalid token is not logged in, even with victim ids in params", %{
    account: account,
    user: user
  } do
    payload =
      socket_me(%{
        "token" => "garbage",
        "current_account_id" => account.id,
        "current_username" => user.character.username
      })

    refute payload_user_id(payload) == user.id
    assert Enum.any?(payload_errors(payload), &String.contains?(&1, "log in"))
  end

  test "control: bearer-authenticated HTTP graphql returns the user", %{
    conn: conn,
    account: account,
    user: user
  } do
    token = Bonfire.API.GraphQL.Auth.token_new({account.id, user.character.username})

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> post("/api/graphql", Jason.encode!(%{query: @me_query}))

    assert get_in(Jason.decode!(resp.resp_body), ["data", "me", "user", "id"]) == user.id
  end
end
