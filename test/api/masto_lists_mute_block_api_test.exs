# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_boundaries, :modularity) != :disabled do
  defmodule Bonfire.Boundaries.Web.MastoListsMuteBlockApiTest do
    @moduledoc "Run with: just test extensions/bonfire_boundaries/test/api/masto_lists_mute_block_api_test.exs"

    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    setup %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)

      conn = masto_api_conn(conn, user: user, account: account)

      {:ok, conn: conn, user: user, account: account}
    end

    defp unauthenticated_conn do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    describe "GET /api/v1/lists" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/lists")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/lists")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/lists" do
      test "creates a list and returns it", %{conn: conn} do
        response =
          conn
          |> post("/api/v1/lists", %{"title" => "Test List"})
          |> json_response(200)

        assert response["title"] == "Test List"
        assert Map.has_key?(response, "id")
      end
    end

    describe "GET /api/v1/mutes" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/mutes")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/mutes")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/accounts/:id/mute" do
      test "does not return 500", %{conn: conn} do
        other_account = Bonfire.Me.Fake.fake_account!()
        other_user = Bonfire.Me.Fake.fake_user!(other_account)

        conn = post(conn, "/api/v1/accounts/#{other_user.id}/mute")
        assert conn.status in [200, 404, 422]
      end
    end

    describe "GET /api/v1/blocks" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/blocks")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/blocks")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/accounts/:id/block" do
      test "does not return 500", %{conn: conn} do
        other_account = Bonfire.Me.Fake.fake_account!()
        other_user = Bonfire.Me.Fake.fake_user!(other_account)

        conn = post(conn, "/api/v1/accounts/#{other_user.id}/block")
        assert conn.status in [200, 404, 422]
      end
    end

    # /mutes and /blocks answered the same body: a full block also silences (masto-live-fixes step 5, decisions 6.1-6.3)
    describe "mutes and blocks are separate lists" do
      test "a blocked account is in /blocks and not in /mutes", %{conn: conn, user: user} do
        blocked = restrict!(user, :block)

        assert blocked.id in account_ids(conn, "/api/v1/blocks")
        refute blocked.id in account_ids(conn, "/api/v1/mutes")
      end

      test "a muted account is in /mutes and not in /blocks", %{conn: conn, user: user} do
        muted = restrict!(user, :silence)

        assert muted.id in account_ids(conn, "/api/v1/mutes")
        refute muted.id in account_ids(conn, "/api/v1/blocks")
      end

      test "relationships of a blocked account: blocking true, muting false", %{
        conn: conn,
        user: user
      } do
        blocked = restrict!(user, :block)

        assert [relationship] =
                 conn
                 |> get("/api/v1/accounts/relationships", %{"id" => [blocked.id]})
                 |> json_response(200)

        assert relationship["blocking"] == true
        assert relationship["muting"] == false
      end
    end

    # both lists ignored `limit` and `max_id`: page 2 repeated page 1 (live testing, masto-live-fixes pagination bug 3, decisions 3.1, 3.2)
    describe "mutes and blocks are paged" do
      test "mutes honour limit and the next link", %{conn: conn, user: user} do
        muted = for _ <- 1..3, do: restrict!(user, :silence)
        assert_paged(conn, "/api/v1/mutes", muted)
      end

      test "blocks honour limit and the next link", %{conn: conn, user: user} do
        blocked = for _ <- 1..3, do: restrict!(user, :block)
        assert_paged(conn, "/api/v1/blocks", blocked)
      end
    end

    # code review of step 5: an id that is not a loadable user took a page slot and turned `next` off; a ghost-only account read as blocking; min_id skipped the closest account
    describe "mutes and blocks, edge cases" do
      test "a silenced group does not stop mutes paging", %{conn: conn, user: user} do
        muted = for _ <- 1..2, do: restrict!(user, :silence)
        group = Bonfire.Classify.Simulate.fake_category!(user)
        {:ok, _} = Bonfire.Boundaries.Blocks.block(group, :silence, current_user: user)

        assert_paged(conn, "/api/v1/mutes", muted)
      end

      test "a ghosted-only account is neither blocking nor muting", %{conn: conn, user: user} do
        ghosted = restrict!(user, :ghost)

        assert [relationship] =
                 conn
                 |> get("/api/v1/accounts/relationships", %{"id" => [ghosted.id]})
                 |> json_response(200)

        assert relationship["blocking"] == false
        assert relationship["muting"] == false
      end

      # the block response came from a second relationship builder that still read muting from silence alone (fresh review, finding 2)
      test "the block response says blocking, not muting", %{conn: conn} do
        other = Bonfire.Me.Fake.fake_user!()

        relationship = conn |> post("/api/v1/accounts/#{other.id}/block") |> json_response(200)

        assert relationship["blocking"] == true
        assert relationship["muting"] == false
      end

      # a cursor that is not an id reached the SQL cast (fresh review, finding 3)
      test "a malformed cursor answers 200", %{conn: conn, user: user} do
        restrict!(user, :silence)

        for params <- [%{"max_id" => "abc"}, %{"min_id" => "abc"}, %{"limit" => "-1"}] do
          assert is_list(conn |> get("/api/v1/mutes", params) |> json_response(200))
        end
      end

      test "min_id answers the closest newer account", %{conn: conn, user: user} do
        [oldest, middle, _newest] = for _ <- 1..3, do: restrict!(user, :block)

        assert account_ids(conn, "/api/v1/blocks", %{"min_id" => oldest.id, "limit" => "1"}) ==
                 [middle.id]
      end
    end

    # a mute is a :silence block, a Mastodon block is a full :block (silence and ghost)
    defp restrict!(user, type) do
      other = Bonfire.Me.Fake.fake_user!()
      {:ok, _} = Bonfire.Boundaries.Blocks.block(other, type, current_user: user)
      other
    end

    defp account_ids(conn, path, params \\ %{}),
      do: conn |> get(path, params) |> json_response(200) |> Enum.map(& &1["id"])

    # follows `rel="next"` with `limit=1`: one account per page, every one reached once, no `next` after the last
    defp assert_paged(conn, path, accounts) do
      {ids, pages} =
        Enum.reduce_while(1..5, {[], %{"limit" => "1"}}, fn _, {ids, params} ->
          resp = get(conn, path, params)
          page = resp |> json_response(200) |> Enum.map(& &1["id"])
          assert length(page) <= 1, "limit=1 gives at most one account"

          case next_params(resp) do
            nil -> {:halt, {ids ++ page, :done}}
            next -> {:cont, {ids ++ page, next}}
          end
        end)

      assert pages == :done, "the last page has no next link"
      assert Enum.sort(ids) == accounts |> Enum.map(& &1.id) |> Enum.sort()
    end

    defp next_params(resp) do
      with [link | _] <- get_resp_header(resp, "link"),
           [_, query] <- Regex.run(~r/<[^>]*\?([^>]*)>; rel="next"/, link) do
        URI.decode_query(query)
      else
        _ -> nil
      end
    end
  end
end
