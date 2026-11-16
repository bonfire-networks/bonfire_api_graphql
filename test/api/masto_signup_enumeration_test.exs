# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.GraphQL.MastoSignupEnumerationTest do
    @moduledoc """
    `POST /api/v1/accounts` (Mastodon signup) must not tell a client whether an email address already has an account: signing up with a taken address answers like signing up with a fresh one, and never says the address is taken.

    Run with: just test extensions/bonfire_api_graphql/test/api/masto_signup_enumeration_test.exs
    """

    use Bonfire.API.MastoApiCase, async: false

    alias Bonfire.OpenID.Provider.ClientApps
    alias Boruta.Ecto.AccessTokens, as: AccessTokensAdapter
    import Boruta.Ecto.OauthMapper, only: [to_oauth_schema: 1]

    @moduletag :masto_api

    setup do
      {:ok, ecto_client} =
        ClientApps.new(%{
          id: Faker.UUID.v4(),
          name: "test-signup-enumeration-app",
          redirect_uris: ["myapp://callback"]
        })

      {:ok, app_token} =
        AccessTokensAdapter.create(
          %{
            client: to_oauth_schema(ecto_client),
            sub: nil,
            scope: "read write follow push write:accounts"
          },
          []
        )

      conn =
        Phoenix.ConnTest.build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("authorization", "Bearer #{app_token.value}")

      {:ok, conn: conn}
    end

    defp signup_params(email) do
      suffix = System.unique_integer([:positive])

      %{
        "username" => "enumeration#{suffix}",
        "email" => email,
        "password" => "password123!",
        "agreement" => true
      }
    end

    test "same response for taken and other failures, without saying the address is taken", %{
      conn: conn
    } do
      address = "taken#{System.unique_integer([:positive])}@example.local"

      first = post(conn, "/api/v1/accounts", signup_params(address))

      # control: a fresh signup works
      assert first.status == 200
      assert %{"access_token" => _} = Jason.decode!(first.resp_body)

      taken = post(conn, "/api/v1/accounts", signup_params(address))

      # the same status and body as the answer to any signup failure that is not a validation error
      assert taken.status == 422
      refute taken.resp_body =~ ~r/taken|already|exists|in use/i
      assert Jason.decode!(taken.resp_body) == %{"error" => "Could not create account"}
    end

    test "any other invalid signup gets the same answer as a taken address", %{conn: conn} do
      params =
        signup_params("weak#{System.unique_integer([:positive])}@example.local")
        |> Map.put("password", "x")

      response = post(conn, "/api/v1/accounts", params)

      assert response.status == 422
      assert Jason.decode!(response.resp_body) == %{"error" => "Could not create account"}
    end

    test "a signup missing fields still names them", %{conn: conn} do
      response = post(conn, "/api/v1/accounts", %{"username" => "someone"})

      assert response.status == 422
      assert response.resp_body =~ "email"
    end
  end
end
