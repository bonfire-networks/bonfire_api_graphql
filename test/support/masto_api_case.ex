# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApiCase do
  @moduledoc """
  Test case for Mastodon API endpoint testing.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Bonfire.ConnCase

      import Bonfire.API.MastoApiCase.Helpers

      alias Bonfire.API.MastoCompat.ApiSpec
    end
  end

  setup _tags do
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

    @doc """
    Categorize a response into implementation status.
    """
    def categorize_response(conn) do
      cond do
        # Route not found
        conn.status == 404 -> :not_found
        # Successful responses
        conn.status in [200, 201, 202, 204] -> :implemented
        # Auth/validation errors mean route exists
        conn.status in [400, 401, 403, 422] -> :implemented
        # Server errors
        conn.status >= 500 -> :error
        # Other responses
        true -> :unknown
      end
    end

    @doc """
    Replace path parameters with test values.
    """
    def substitute_path_params(path, user \\ nil) do
      user_id = if user, do: user.id, else: "test_user_id"

      path
      |> String.replace("{id}", "test_id_123")
      |> String.replace("{account_id}", user_id)
      |> String.replace("{status_id}", "test_status_id")
      |> String.replace("{list_id}", "test_list_id")
      |> String.replace("{tag}", "test_tag")
      |> String.replace("{hashtag}", "test_hashtag")
      |> String.replace("{domain}", "example.com")
      |> String.replace(~r/\{[^}]+\}/, "test_param")
    end
  end
end
