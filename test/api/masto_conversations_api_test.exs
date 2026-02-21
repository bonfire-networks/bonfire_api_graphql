# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_messages, :modularity) != :disabled do
  defmodule Bonfire.Messages.Web.MastoConversationsApiTest do
    @moduledoc "Run with: just test extensions/bonfire_messages/test/api/masto_conversations_api_test.exs"

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

    describe "GET /api/v1/conversations" do
      test "returns 200 with empty list when no conversations", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/conversations")
          |> json_response(200)

        assert is_list(response)
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/conversations")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "DELETE /api/v1/conversations/:id" do
      test "returns 200 for valid request", %{conn: conn} do
        response =
          conn
          |> delete("/api/v1/conversations/#{Needle.ULID.generate()}")
          |> json_response(200)

        assert response == %{}
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> delete("/api/v1/conversations/#{Needle.ULID.generate()}")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "POST /api/v1/conversations/:id/read" do
      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> post("/api/v1/conversations/#{Needle.ULID.generate()}/read")
          |> json_response(401)

        assert response["error"]
      end
    end
  end
end
