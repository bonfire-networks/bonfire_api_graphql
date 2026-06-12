# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompatible.MarkersApiTest do
    @moduledoc "Run with: just test extensions/bonfire_api_graphql/test/api/masto_markers_api_test.exs"

    use Bonfire.API.MastoApiCase, async: false

    alias Bonfire.Me.Fake
    alias Bonfire.Social.{Boosts, Likes}
    alias Bonfire.Social.Graph.Follows

    @moduletag :masto_api

    setup %{conn: conn} do
      account = Fake.fake_account!()
      me = Fake.fake_user!(account)
      poster = Fake.fake_user!()

      {:ok, _} = Follows.follow(me, poster)

      # Poster creates a post that lands in me's home feed
      post = publish_post(poster, "A post for markers test")

      conn = masto_api_conn(conn, user: me, account: account)

      {:ok, conn: conn, me: me, account: account, poster: poster, post: post}
    end

    defp publish_post(user, body) do
      Bonfire.Posts.Fake.fake_post!(user, "public", %{post_content: %{html_body: body}})
    end

    defp post_marker(conn, timeline, last_read_id) do
      conn
      |> post("/api/v1/markers", %{timeline => %{"last_read_id" => last_read_id}})
      |> json_response(200)
    end

    defp get_markers(conn, timeline) do
      conn
      |> get("/api/v1/markers?timeline[]=#{timeline}")
      |> json_response(200)
    end

    defp activity_id_of(object) do
      import Ecto.Query

      Bonfire.Common.Repo.one(
        from(a in Bonfire.Data.Social.Activity,
          where: a.object_id == ^object.id,
          order_by: [desc: a.id],
          limit: 1,
          select: a.id
        )
      )
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
        post_marker(conn, "home", post.id)

        response = get_markers(conn, "home")

        assert response["home"]["last_read_id"] == post.id
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

      test "updated_at is stable across reads", %{conn: conn, post: post} do
        post_marker(conn, "home", post.id)

        first = get_markers(conn, "home")
        second = get_markers(conn, "home")

        assert first["home"]["updated_at"] == second["home"]["updated_at"]
        assert {:ok, _, _} = DateTime.from_iso8601(first["home"]["updated_at"])
      end
    end

    describe "web <-> API marker sync" do
      test "a web reading position (activity id cursor) is translated to a status id by the markers API",
           %{
             conn: conn,
             me: me,
             post: post
           } do
        # the web scroll tracker saves feed entry (activity) ids as cursors
        {:ok, _} = Bonfire.Social.Markers.save_reading_position(me, "my", activity_id_of(post))

        assert get_markers(conn, "home")["home"]["last_read_id"] == post.id
      end

      test "an API marker (status id) is stored as the activity id the web feed paginates by", %{
        conn: conn,
        me: me,
        post: post
      } do
        post_marker(conn, "home", post.id)

        assert Bonfire.Social.Markers.get_reading_position(me, "my") == activity_id_of(post)
      end
    end

    describe "notifications timeline round-trip" do
      test "POST then GET returns the same notification id", %{
        conn: conn,
        me: me,
        poster: poster
      } do
        my_post = publish_post(me, "A post that will get liked")
        {:ok, _} = Likes.like(poster, my_post)

        notifications =
          conn
          |> get("/api/v1/notifications")
          |> json_response(200)

        assert [%{"id" => notification_id} | _] = notifications

        post_marker(conn, "notifications", notification_id)

        assert get_markers(conn, "notifications")["notifications"]["last_read_id"] ==
                 notification_id
      end
    end

    describe "home timeline boost round-trip" do
      test "POST then GET returns the boost status id", %{
        conn: conn,
        poster: poster
      } do
        author = Fake.fake_user!()
        boosted_post = publish_post(author, "A post that will get boosted")
        {:ok, _} = Boosts.boost(poster, boosted_post)

        home =
          conn
          |> get("/api/v1/timelines/home")
          |> json_response(200)

        reblog_status = Enum.find(home, &(&1["reblog"] != nil))
        assert reblog_status, "expected a reblog status in the home timeline"
        boost_status_id = reblog_status["id"]

        post_marker(conn, "home", boost_status_id)

        assert get_markers(conn, "home")["home"]["last_read_id"] == boost_status_id
      end
    end

    describe "POST /api/v1/markers" do
      test "marks item as seen and returns marker", %{conn: conn, post: post} do
        response = post_marker(conn, "home", post.id)

        assert response["home"]["last_read_id"] == post.id
        assert response["home"]["version"] == 0
      end

      test "is last-write-wins: an older position saved later replaces a newer one", %{
        conn: conn,
        poster: poster,
        post: older_post
      } do
        newer_post = publish_post(poster, "A newer post for markers test")

        assert newer_post.id > older_post.id

        post_marker(conn, "home", newer_post.id)
        assert get_markers(conn, "home")["home"]["last_read_id"] == newer_post.id

        post_marker(conn, "home", older_post.id)

        # The marker is a position, not a high-water mark: cross-device resume
        # requires it to be able to move backward (Mastodon behaves the same).
        response = get_markers(conn, "home")
        assert response["home"]["last_read_id"] == older_post.id
        assert is_binary(response["home"]["updated_at"])
      end

      test "version increments when the position moves, not on identical saves", %{
        conn: conn,
        poster: poster,
        post: post
      } do
        second_post = publish_post(poster, "A second post for markers test")

        first = post_marker(conn, "home", post.id)
        moved = post_marker(conn, "home", second_post.id)
        unchanged = post_marker(conn, "home", second_post.id)

        assert first["home"]["version"] == 0
        assert moved["home"]["version"] == 1
        assert unchanged["home"]["version"] == 1
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
