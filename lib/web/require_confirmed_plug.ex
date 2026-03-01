defmodule Bonfire.API.GraphQL.Plugs.RequireConfirmed do
  @moduledoc """
  Returns 403 if user email is not confirmed.

  This plug enforces email confirmation for API endpoints. When a user has
  a valid token but hasn't confirmed their email, this returns a 403 response with "Your login is missing a confirmed e-mail address".

  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]
  import Untangle
  import Bonfire.Common.Utils
  use Bonfire.Common.E
  use Bonfire.Common.Repo

  def init(opts), do: opts

  def call(conn, _opts) do
    me = current_account(conn) || current_user(conn)
    # Only block authenticated users with explicitly unconfirmed email
    if !me || !email_confirmed?(me) do
      conn
      |> put_status(403)
      |> json(%{"error" => "Your login is missing a confirmed e-mail address"})
      |> halt()
    else
      conn
    end
  end

  defp email_confirmed?(%{email: %{confirmed_at: confirmed_at}}) when not is_nil(confirmed_at) do
    true
  end

  defp email_confirmed?(%{account: %{email: %{confirmed_at: confirmed_at}}})
       when not is_nil(confirmed_at) do
    true
  end

  defp email_confirmed?(%{accounted: %{account: %{email: %{confirmed_at: confirmed_at}}}})
       when not is_nil(confirmed_at) do
    true
  end

  defp email_confirmed?(%{email: %Ecto.Association.NotLoaded{}} = account) do
    account
    |> repo().maybe_preload(:email)
    |> e(:email, :confirmed_at, nil)
  end

  defp email_confirmed?(%{account: %{email: %Ecto.Association.NotLoaded{}} = account}) do
    account
    |> repo().maybe_preload(:email)
    |> e(:email, :confirmed_at, nil)
  end

  defp email_confirmed?(%{
         accounted: %{account: %{email: %Ecto.Association.NotLoaded{}} = account}
       }) do
    account
    |> repo().maybe_preload(:email)
    |> e(:email, :confirmed_at, nil)
  end

  # defp email_confirmed?(user) do
  #   with account_id when is_binary(account_id) <-
  #          e(user, :account, :id, nil) || e(user, :accounted, :account_id, nil),
  #        %{email: %{confirmed_at: confirmed_at}} when not is_nil(confirmed_at) <-
  #          Bonfire.Me.Accounts.Queries.login_by_account_id(account_id)
  #          |> Bonfire.Common.Repo.maybe_one()
  #          |> debug("queried account") do
  #     true
  #   else
  #     _ -> false
  #   end
  # end
  defp email_confirmed?(me) do
    err(me, "Could not determine email confirmation status for account/user")
    false
  end
end
