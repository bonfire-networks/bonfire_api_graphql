# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.InstanceGuestTest do
  @moduledoc """
  Instance info without a token: apps read it before login (Ice Cubes shows the instance's name on its add-account screen), and Mastodon serves both endpoints publicly, as Bonfire already does for `/api/v2/instance` (live testing, masto-live-fixes step 1).

  Run with: just test extensions/bonfire_api_graphql/test/api/instance_guest_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  import Bonfire.API.MastoCompat.Test.MastoSchema

  @moduletag :masto_api

  test "a guest reads /api/v1/instance", %{conn: conn} do
    response = get_json(conn, "/api/v1/instance")

    assert is_binary(response["uri"])
    assert is_binary(response["version"])
  end

  # Phanpy streams only when instance info names a streaming URL
  test "/api/v1/instance advertises the instance's ws(s) origin as urls.streaming_api", %{
    conn: conn
  } do
    streaming = get_json(conn, "/api/v1/instance")["urls"]["streaming_api"]

    assert_streaming_origin(streaming)
  end

  test "/api/v2/instance advertises the same origin as configuration.urls.streaming, or none without the socket",
       %{conn: conn} do
    v1 = get_json(conn, "/api/v1/instance")["urls"]["streaming_api"]
    v2 = get_json(conn, "/api/v2/instance")["configuration"]["urls"]["streaming"]

    if Bonfire.API.MastoCompatible.InstanceAdapter.streaming_mounted?() do
      assert v2 == v1
    else
      assert v2 == nil
    end
  end

  test "/api/v1/instance passes the V1Instance client checks", %{conn: conn} do
    conn
    |> get_json("/api/v1/instance")
    |> assert_masto_entity("V1Instance")
  end

  # Ice Cubes calls it at start, and it answered 404 (live testing, masto-live-fixes step 3)
  test "a guest reads /api/v1/instance/peers: the known instances' domains", %{conn: conn} do
    host = "peer-#{System.unique_integer([:positive])}.example"
    Bonfire.Federate.ActivityPub.Instances.get_or_create("https://#{host}/users/someone")

    peers = get_json(conn, "/api/v1/instance/peers")

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
      Bonfire.Boundaries.Blocks.block(peer, type, scope: :instance_wide, skip_boundary_check: true)
    end

    peers = get_json(conn, "/api/v1/instance/peers")

    assert kept in peers
    refute ghosted in peers
    refute silenced in peers
  end

  test "a guest reads /api/v1/custom_emojis", %{conn: conn} do
    response = get_json(conn, "/api/v1/custom_emojis")

    assert is_list(response)
  end

  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> get(path)
    |> json_response(200)
  end

  defp assert_streaming_origin(url) do
    uri = URI.parse(url)

    assert uri.scheme in ["ws", "wss"]
    assert uri.host == Bonfire.Common.URIs.base_uri().host
    assert uri.port == Bonfire.Common.URIs.base_uri().port
    assert uri.path in [nil, ""]
  end
end
