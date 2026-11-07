if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Test.ValidateResponseTest do
    @moduledoc """
    The test-only plug in the `:masto_api` pipeline that checks every 200 JSON response against the Mastodon spec when `MASTO_VALIDATE` is set.
    """
    use Bonfire.API.MastoApiCase, async: true

    @moduletag :masto_api

    alias Bonfire.API.MastoCompat.Test.ValidateResponse

    setup %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)

      {:ok, post} =
        Bonfire.Posts.publish(
          current_user: user,
          post_attrs: %{post_content: %{html_body: "Hello"}},
          boundary: "public"
        )

      {:ok, conn: masto_api_conn(conn, user: user, account: account), post: post}
    end

    test "with checking on, a valid response passes", %{conn: conn, post: post} do
      Process.put([:bonfire_api_graphql, ValidateResponse, :enabled], true)

      assert %{"id" => id} = conn |> get("/api/v1/statuses/#{post.id}") |> json_response(200)
      assert id == post.id
    end

    test "with checking on, an invalid 200 body on a Mastodon route fails", %{
      conn: conn,
      post: post
    } do
      Process.put([:bonfire_api_graphql, ValidateResponse, :enabled], true)

      error =
        assert_raise ExUnit.AssertionError, fn ->
          invalid_status_response(conn, post)
        end

      assert error.message =~ "account"
    end

    test "with checking off, an invalid 200 body passes through", %{conn: conn, post: post} do
      assert invalid_status_response(conn, post).status == 200
    end

    # the router a real request went through, then the plug on a request to the same route, answered with a Status that has no account
    defp invalid_status_response(conn, post) do
      router = (conn |> get("/api/v1/statuses/#{post.id}")).private.phoenix_router

      build_conn(:get, "/api/v1/statuses/#{post.id}")
      |> Plug.Conn.put_private(:phoenix_router, router)
      |> Plug.Conn.put_resp_content_type("application/json")
      |> ValidateResponse.call(ValidateResponse.init([]))
      |> Plug.Conn.send_resp(200, Jason.encode!(%{"id" => post.id}))
    end
  end
end
