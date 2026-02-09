# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompatible.MarkersApiTest do
    @moduledoc "Run with: just test extensions/bonfire_api_graphql/test/api/masto_markers_api_test.exs"

    use Bonfire.API.MastoApiCase, async: false

    alias Bonfire.Me.Fake
    alias Bonfire.Posts
    alias Bonfire.Social.Graph.Follows

    @moduletag :masto_api

    setup %{conn: conn} do
      account = Fake.fake_account!()
      me = Fake.fake_user!(account)
      poster = Fake.fake_user!()

      {:ok, _} = Follows.follow(me, poster)

      # Poster creates a post that lands in me's home feed
      {:ok, post} =
        Posts.publish(
          current_user: poster,
          post_attrs: %{post_content: %{html_body: "A post for markers test"}},
          boundary: "public"
        )

      conn = masto_api_conn(conn, user: me, account: account)

      {:ok, conn: conn, me: me, account: account, post: post}
    end

    describe "GET /api/v1/markers" do
      test "returns empty when no items seen", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/markers")
          |> json_response(200)

        assert response == %{}
      end

      test "returns marker after marking item as seen", %{conn: conn, post: post} do
        conn
        |> post("/api/v1/markers", %{
          "home" => %{"last_read_id" => post.id}
        })
        |> json_response(200)

        response =
          conn
          |> get("/api/v1/markers?timeline[]=home")
          |> json_response(200)

        assert response["home"]["last_read_id"]
        assert response["home"]["version"] == 0
        assert is_binary(response["home"]["updated_at"])
      end

      test "requires authentication" do
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> get("/api/v1/markers")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/markers" do
      test "marks item as seen and returns marker", %{conn: conn, post: post} do
        response =
          conn
          |> post("/api/v1/markers", %{
            "home" => %{"last_read_id" => post.id}
          })
          |> json_response(200)

        assert response["home"]["last_read_id"] == post.id
        assert response["home"]["version"] == 0
      end

      test "requires authentication" do
        response =
          Phoenix.ConnTest.build_conn()
          |> put_req_header("accept", "application/json")
          |> put_req_header("content-type", "application/json")
          |> post("/api/v1/markers", %{
            "home" => %{"last_read_id" => "01HZTEST000000000000000000"}
          })
          |> json_response(401)

        assert response["error"]
      end
    end
  end
end
