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
      test "populated conversations expose valid participant URLs and remain private", %{
        conn: conn,
        user: user
      } do
        sender = Bonfire.Me.Fake.fake_user!()

        assert {:ok, message} =
                 Bonfire.Messages.send(sender, %{
                   to_circles: [user.id],
                   post_content: %{html_body: "Private conversation URL regression"}
                 })

        conversations = conn |> get("/api/v1/conversations") |> json_response(200)
        conversation = Enum.find(conversations, &(&1["last_status"]["id"] == message.id))
        assert conversation
        assert conversation["last_status"]["visibility"] == "direct"
        assert sender.id in Enum.map(conversation["accounts"], & &1["id"])

        for participant <- conversation["accounts"] ++ [conversation["last_status"]["account"]] do
          assert is_binary(participant["url"])
          assert %URI{scheme: scheme, host: host} = URI.parse(participant["url"])
          assert scheme in ["http", "https"]
          assert is_binary(host) and host != ""
        end

        outsider_account = Bonfire.Me.Fake.fake_account!()
        outsider = Bonfire.Me.Fake.fake_user!(outsider_account)

        outsider_conversations =
          Phoenix.ConnTest.build_conn()
          |> masto_api_conn(user: outsider, account: outsider_account)
          |> get("/api/v1/conversations")
          |> json_response(200)

        refute Enum.any?(outsider_conversations, &(&1["last_status"]["id"] == message.id))
      end

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
