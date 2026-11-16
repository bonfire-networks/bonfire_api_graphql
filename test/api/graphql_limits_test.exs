# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.LimitsTest do
  @moduledoc """
  The GraphQL endpoint refuses abusive requests: queries nested deeper than the maximum depth (15 by default), JSON batches of more than the maximum number of queries (10 by default), and too many requests from one IP.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_limits_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false

  @moduletag :graphql

  defp post_json(conn, payload) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(payload))
  end

  defp nested(depth), do: String.duplicate("a{", depth) <> "id" <> String.duplicate("}", depth)

  describe "depth" do
    test "a shallow query is answered", %{conn: conn} do
      resp = post_json(conn, %{query: "{ __typename }"})

      assert resp.status == 200
      assert get_in(Jason.decode!(resp.resp_body), ["data", "__typename"]) == "RootQueryType"
    end

    test "a query nested deeper than the maximum is refused for its depth", %{conn: conn} do
      resp = post_json(conn, %{query: "{ " <> nested(30) <> " }"})

      assert resp.resp_body =~ ~r/depth/i
    end

    test "the maximum depth can be set in config", %{conn: conn} do
      Process.put([:bonfire_api_graphql, :max_depth], 3)

      resp = post_json(conn, %{query: "{ " <> nested(5) <> " }"})

      assert resp.resp_body =~ ~r/depth/i
    end
  end

  describe "batching" do
    test "a batch of two queries is answered with two results", %{conn: conn} do
      resp = post_json(conn, List.duplicate(%{query: "{ __typename }"}, 2))

      assert resp.status == 200
      assert [%{}, %{}] = Jason.decode!(resp.resp_body)
    end

    test "a batch of fifty queries is refused", %{conn: conn} do
      resp = post_json(conn, List.duplicate(%{query: "{ __typename }"}, 50))

      assert resp.status in 400..499
      refute match?(list when is_list(list) and length(list) == 50, Jason.decode!(resp.resp_body))
    end
  end

  describe "rate limit" do
    setup do
      Process.put([:bonfire_api_graphql, :rate_limit_in_test], true)
      Process.put([:bonfire, :rate_limit, :disabled], false)
      Process.put([:bonfire, :rate_limit, :graphql], scale_ms: 60_000, limit: 3)
      :ok
    end

    defp from_ip(conn, n), do: %{conn | remote_ip: {203, 0, 113, n}}

    test "requests over the cap from one IP get 429, and another IP is unaffected", %{conn: conn} do
      n = :rand.uniform(200)

      statuses =
        for _ <- 1..8 do
          conn |> from_ip(n) |> post_json(%{query: "{ __typename }"}) |> Map.fetch!(:status)
        end

      # control: the first requests got through
      assert hd(statuses) == 200
      assert 429 in statuses

      other = conn |> from_ip(n + 50) |> post_json(%{query: "{ __typename }"})
      assert other.status == 200
    end
  end
end
