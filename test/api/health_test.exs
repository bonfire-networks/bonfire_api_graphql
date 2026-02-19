# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.HealthTest do
  @moduledoc """
  Tests for Kubernetes-style health check endpoints.

  Covers:
  - GET /livez - Liveness probe
  - GET /readyz - Readiness probe

  Run with: just test extensions/bonfire_api_graphql/test/rest/masto_api/health_test.exs
  """

  use Bonfire.API.MastoApiCase, async: true

  @moduletag :masto_api

  describe "GET /livez" do
    test "returns 200 when app is running", %{conn: conn} do
      conn
      |> get("/livez")
      |> response(200)
    end

    test "works without authentication", %{conn: conn} do
      conn
      |> get("/livez")
      |> response(200)
    end
  end

  describe "GET /readyz" do
    test "returns 200 when app is ready", %{conn: conn} do
      conn
      |> get("/readyz")
      |> response(200)
    end

    test "works without authentication", %{conn: conn} do
      conn
      |> get("/readyz")
      |> response(200)
    end
  end
end
