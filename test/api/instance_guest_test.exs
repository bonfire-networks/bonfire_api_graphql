# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.InstanceGuestTest do
  @moduledoc """
  Instance info without a token: apps read it before login (Ice Cubes shows the instance's name on its add-account screen), and Mastodon serves both endpoints publicly, as Bonfire already does for `/api/v2/instance` (live testing, masto-live-fixes step 1).

  Run with: just test extensions/bonfire_api_graphql/test/api/instance_guest_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :masto_api

  test "a guest reads /api/v1/instance", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/instance")
      |> json_response(200)

    assert is_binary(response["uri"])
    assert is_binary(response["version"])
  end

  # Ice Cubes calls it at start, and it answered 404 (live testing, masto-live-fixes step 3)
  test "a guest reads /api/v1/instance/peers: the known instances' domains", %{conn: conn} do
    host = "peer-#{System.unique_integer([:positive])}.example"
    Bonfire.Federate.ActivityPub.Instances.get_or_create("https://#{host}/users/someone")

    peers =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/instance/peers")
      |> json_response(200)

    assert Enum.all?(peers, &is_binary/1)
    assert host in peers
  end

  # Mastodon leaves suspended domains out of peers; the list showed instances the admin had blocked (code review of masto-live-fixes)
  test "a ghosted or silenced instance is not among the peers", %{conn: conn} do
    suffix = System.unique_integer([:positive])
    kept = "kept-#{suffix}.example"
    ghosted = "ghosted-#{suffix}.example"
    silenced = "silenced-#{suffix}.example"

    Bonfire.Federate.ActivityPub.Instances.get_or_create("https://#{kept}/users/someone")

    for {host, type} <- [{ghosted, :ghost}, {silenced, :silence}] do
      {:ok, peer} =
        Bonfire.Federate.ActivityPub.Instances.get_or_create("https://#{host}/users/someone")

      # as instance_ghost_feeds_instance_wide_test.exs blocks an instance
      Bonfire.Boundaries.Blocks.block(peer, type,
        scope: :instance_wide,
        skip_boundary_check: true
      )
    end

    peers =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/instance/peers")
      |> json_response(200)

    assert kept in peers
    refute ghosted in peers
    refute silenced in peers
  end

  test "a guest reads /api/v1/custom_emojis", %{conn: conn} do
    response =
      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/v1/custom_emojis")
      |> json_response(200)

    assert is_list(response)
  end
end
