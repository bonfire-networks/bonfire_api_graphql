# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.LoginSessionTest do
  @moduledoc """
  A GraphQL cookie login starts a new session the way the web login does: values already in the session (planted by a sibling subdomain, say) are dropped, and the session is stamped with when it started, which is what lets a later password change end the account's other sessions but not this one.

  Run with: just test extensions/bonfire_api_graphql/test/api/graphql_login_session_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false

  @moduletag :graphql

  @password "a-long-enough-password-7"

  setup do
    account =
      Bonfire.Me.Fake.fake_account!(%{credential: %{password: @password}})
      |> Bonfire.Common.Repo.preload([:email])

    user = Bonfire.Me.Fake.fake_user!(account)
    {:ok, account: account, user: user}
  end

  defp graphql(conn, query) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post("/api/graphql", Jason.encode!(%{query: query}))
  end

  defp login_mutation(account, password) do
    """
    mutation {
      login(emailOrUsername: "#{account.email.email_address}", password: "#{password}") {
        token
      }
    }
    """
  end

  defp login(conn, account), do: graphql(conn, login_mutation(account, @password))

  # an account-required page that renders for a signed-in account and bounces guests to /login
  defp signed_in?(conn), do: get(conn, "/account/password/change").status == 200

  test "control: a login with the right password signs the account in", %{
    conn: conn,
    account: account
  } do
    conn = login(conn, account)

    assert get_session(conn, :current_account_id) == account.id
  end

  test "a login drops the keys already in the session", %{conn: conn, account: account} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> put_session(:planted_before_login, "from a sibling subdomain")
      |> login(account)

    assert get_session(conn, :current_account_id) == account.id
    assert get_session(conn, :planted_before_login) == nil
  end

  test "a login stamps the session with when it started", %{conn: conn, account: account} do
    before_login = System.system_time(:millisecond)

    conn = login(conn, account)

    assert started = get_session(conn, :session_started_at)
    assert is_integer(started) and started >= before_login
  end

  test "ending the account's other sessions leaves the GraphQL session made after it", %{
    conn: conn,
    account: account
  } do
    older = conn |> login(account) |> recycle()
    assert signed_in?(older), "control: the session works before the change"

    Process.sleep(5)
    assert {:ok, _} = Bonfire.Me.Accounts.revoke_other_sessions(account)
    Process.sleep(5)

    newer = build_conn() |> login(account) |> recycle()

    refute signed_in?(older)
    assert signed_in?(newer)
  end
end
