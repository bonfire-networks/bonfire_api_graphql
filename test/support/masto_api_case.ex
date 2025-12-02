# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApiCase do
  @moduledoc """
  Test case for Mastodon API endpoint testing.

  Self-contained test case that doesn't depend on Bonfire.ConnCase
  to avoid missing module issues when running tests from extension context.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest

      import Bonfire.UI.Common.Testing.Helpers
      import Bonfire.Me.Fake

      import Bonfire.API.MastoApiCase.Helpers

      alias Bonfire.API.MastoCompat.ApiSpec

      # The default endpoint for testing
      @endpoint Application.compile_env!(:bonfire, :endpoint_module)
    end
  end

  setup tags do
    Bonfire.Common.Test.Interactive.setup_test_repo(tags)

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  defmodule Helpers do
    @moduledoc """
    Helper functions for Mastodon API testing.
    """

    import Plug.Conn
    import Phoenix.ConnTest

    @endpoint Application.compile_env!(:bonfire, :endpoint_module)

    @doc """
    Build a connection configured for Mastodon API requests.
    Optionally authenticates with a user via session (for testing routes).
    """
    def masto_api_conn(conn, opts \\ []) do
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
      |> maybe_authenticate(opts[:user], opts[:account])
    end

    defp maybe_authenticate(conn, nil, _account), do: conn

    defp maybe_authenticate(conn, user, account) do
      # For API testing, we set up the user in the session
      # The load_current_auth plug will pick this up
      conn = Plug.Test.init_test_session(conn, %{})

      conn =
        if account do
          Plug.Conn.put_session(conn, :current_account_id, account.id)
        else
          conn
        end

      Plug.Conn.put_session(conn, :current_user_id, user.id)
    end

    @doc "Categorize a response into implementation status."
    def categorize_response(conn) do
      cond do
        conn.status in [200, 201, 202, 204] -> :implemented
        conn.status in [400, 401, 403, 422] -> :implemented
        conn.status >= 500 -> :error
        conn.status == 404 -> categorize_404(conn)
        true -> :unknown
      end
    end

    defp categorize_404(conn) do
      body = conn.resp_body || ""
      has_controller_action? = Map.has_key?(conn.private, :phoenix_action)

      router_404_patterns = [
        "no route found",
        "No route found",
        "Phoenix.Router.NoRouteError",
        "<title>404</title>",
        "Page not found"
      ]

      is_router_404_body? = Enum.any?(router_404_patterns, &String.contains?(body, &1))

      cond do
        has_controller_action? -> :implemented
        is_router_404_body? -> :not_found
        true -> :not_found
      end
    end

    @test_ulid "01HZTEST000000000000000000"
    @test_status_ulid "01HZSTATUS0000000000000000"
    @test_list_ulid "01HZLIST00000000000000000"
    @test_user_ulid "01HZUSER00000000000000000"

    @doc "Replace path parameters with test values."
    def substitute_path_params(path, user \\ nil) do
      user_id = if user, do: user.id, else: @test_user_ulid

      path
      |> String.replace("{id}", @test_ulid)
      |> String.replace("{account_id}", user_id)
      |> String.replace("{status_id}", @test_status_ulid)
      |> String.replace("{list_id}", @test_list_ulid)
      |> String.replace("{tag}", "test_tag")
      |> String.replace("{hashtag}", "test_hashtag")
      |> String.replace("{domain}", "example.com")
      |> String.replace(~r/\{[^}]+\}/, @test_ulid)
    end
  end
end
