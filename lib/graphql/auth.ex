defmodule Bonfire.API.GraphQL.Auth do
  import Bonfire.Common.Config, only: [repo: 0]
  import Untangle
  use Bonfire.Common.Utils

  alias Bonfire.API.GraphQL
  alias Bonfire.Me.Accounts
  alias Bonfire.Me.Users

  @token_salt "bonfire_api_bearer_token_v1"

  @doc "Issues a bearer token for `{account_id, username}`. It carries when it was issued, so revoking the account's other sessions (password or email change, reset) ends it."
  def token_new({account_id, username}),
    do:
      Bonfire.Me.Auth.BearerToken.sign({account_id, username, System.system_time(:millisecond)},
        salt: @token_salt
      )

  @doc "Verifies a bearer token, returning `{:ok, {account_id, username}}`, or an error if it is invalid or was issued before the account's sessions were revoked. Costs one account lookup."
  def token_verify(token) do
    case Bonfire.Me.Auth.BearerToken.verify(token, salt: @token_salt) do
      {:ok, {account_id, username, issued_at}} ->
        verify_not_revoked(account_id, username, issued_at)

      # a token issued before tokens carried when they were issued
      {:ok, {account_id, username}} ->
        verify_not_revoked(account_id, username, nil)

      other ->
        other
    end
  end

  defp verify_not_revoked(account_id, username, issued_at) do
    account = Utils.maybe_apply(Accounts, :get_current, [account_id])

    if Utils.maybe_apply(Accounts, :session_revoked?, [account, issued_at],
         fallback_return: false
       ),
       do: {:error, :revoked},
       else: {:ok, {account_id, username}}
  end

  @doc """
  Resolver for login mutation for Bonfire.API.GraphQL.CommonSchema
  """
  def login(
        _,
        %{email_or_username: email_or_username, password: password} = attrs,
        _
      ) do
    if module_enabled?(Accounts) do
      with {:ok, account, user} <- Utils.maybe_apply(Accounts, :login, attrs) do
        account_id = Map.get(account, :id)
        username = username(user)

        {:ok,
         Map.merge(user || %{}, %{
           current_account: account,
           current_account_id: account_id,
           current_user: user,
           current_username: username,
           token: token_new({account_id, username})
         })}
      else
        e ->
          {:error, e}
      end
    else
      {:error, "Your app's authentication is not integrated with this GraphQL mutation."}
    end
  end

  def select_user(_, %{username: username} = attrs, info) do
    account = GraphQL.current_account(info)

    if account do
      with %{} = user <- user_by(username, account) do
        {:ok,
         Map.merge(user, %{
           current_account: account,
           current_account_id: Map.get(account, :id),
           current_user: user,
           current_username: username(user)
         })}
      end
    else
      {:error, "Not authenticated"}
    end
  end

  @doc """
  Puts the account/user data in Absinthe context (runs after on `login/3` resolver)
  """
  def set_context_from_resolution(
        %{
          value: %{
            current_account: current_account,
            current_user: current_user,
            current_account_id: current_account_id,
            current_username: current_username
          }
        } = resolution,
        _
      ) do
    Map.update!(
      resolution,
      :context,
      &Map.merge(&1, %{
        current_account: current_account,
        current_user: current_user,
        current_account_id: current_account_id,
        current_username: current_username
      })
    )
  end

  def set_context_from_resolution(
        %{
          value: %{
            current_account: current_account,
            current_account_id: current_account_id
          }
        } = resolution,
        _
      ) do
    Map.update!(
      resolution,
      :context,
      &Map.merge(&1, %{
        current_account: current_account,
        current_user: nil,
        current_account_id: current_account_id,
        current_username: nil
      })
    )
  end

  def set_context_from_resolution(resolution, _) do
    debug("Auth.set_context_from_resolution: no matching pattern")
    resolution
  end

  @doc """
  Sets session cookie based on the Absinthe context set in `set_context_from_resolution/2` (called from router's `absinthe_before_send/2` )
  """
  def set_session_from_context(conn, %Absinthe.Blueprint{
        execution: %{
          context: %{current_account_id: current_account_id} = context
        }
      })
      when not is_nil(current_account_id) do
    # IO.inspect(absinthe_before_send_set_session: context)
    conn
    |> maybe_start_new_session(current_account_id, context)
    |> Plug.Conn.put_session(:current_account_id, current_account_id)
    |> Plug.Conn.put_session(
      :current_username,
      Map.get(context, :current_username)
    )
  end

  def set_session_from_context(conn, _), do: conn

  @doc "Absinthe middleware for a field that signs someone in: marks the request's session as one to start afresh (see `set_session_from_context/2`)."
  def mark_new_session(
        %{value: %{current_account_id: account_id}, context: context} = resolution,
        _
      )
      when not is_nil(account_id),
      do: %{resolution | context: Map.put(context, :new_session, true)}

  # a login that failed signs no one in, so a session already there is left alone
  def mark_new_session(resolution, _), do: resolution

  # a login starts a session the way the web login does, so nothing that was in the session before it counts (a sibling subdomain can plant cookies) and the session can later be told apart from older ones, which a password change ends
  defp maybe_start_new_session(conn, current_account_id, %{new_session: true}) do
    conn = Bonfire.UI.Common.Web.renew_session(conn)

    Bonfire.Common.Utils.maybe_apply(
      Bonfire.UI.Me.Sudo,
      :renew_session_for,
      [conn, current_account_id],
      fallback_return: conn
    )
  end

  defp maybe_start_new_session(conn, _current_account_id, _context), do: conn

  def build_context(conn) do
    cond do
      # load_authorization plug already verified an OAuth2/OpenID bearer token,
      # or LoadCurrentUser populated current_user from session
      conn.assigns[:current_user] || conn.assigns[:current_token] ->
        build_context_from_assigns(conn)

      # Fall back to Phoenix.Token bearer (e.g. issued by login mutation or embed)
      match?([_ | _], Plug.Conn.get_req_header(conn, "authorization")) ->
        [val | _] = Plug.Conn.get_req_header(conn, "authorization")
        build_context_from_token(conn, val)

      true ->
        %{}
    end
  end

  defp build_context_from_assigns(conn) do
    user = conn.assigns[:current_user]
    token = conn.assigns[:current_token]

    %{
      current_user: user,
      current_username: username(user),
      current_account: user && GraphQL.current_account(user),
      current_account_id: (user && uid(user)) || (token && token.sub),
      current_token: token
    }
  end

  defp build_context_from_token(conn, val) do
    with [scheme, token] <- String.split(val, " ", parts: 2),
         "bearer" <- String.downcase(scheme, :ascii),
         {:ok, ids} <- token_verify(token),
         %{} = user <- user_by(ids),
         %{} = account <- GraphQL.current_account(user) |> debug() do
      %{
        current_user: user,
        current_username: username(user),
        current_account: account,
        current_account_id: uid(account)
      }
    else
      _ -> %{}
    end
  end

  def user_by({account, username}) do
    user_by(username, account)
    # `character: [:peered]` too, as boundary queries ask whether the user is local (on 25 October a post created through the API over HTTP failed to resolve its `activity`, as the token's user lacked it)
    |> repo().maybe_preload(accounted: :account, character: [:peered])
    |> debug("attempted to load account from user")
  end

  def user_by(username_or_user_id, account)
      when (is_binary(username_or_user_id) and is_binary(account)) or is_map(account) do
    with {:ok, u} <-
           Utils.maybe_apply(Users, :by_user_and_account, [
             username_or_user_id,
             account
           ]) do
      u
    end
  end

  def user_by(username, _) when is_binary(username) do
    with {:ok, u} <- Utils.maybe_apply(Users, :by_username, [username]) do
      u
    end
  end

  def user_by(_, account) when is_binary(account) or is_map(account) do
    with %{} = account <- account_by(account) do
      account
      |> repo().maybe_preload(accounted: [user: [:character, profile: [:icon, :image]]])
      |> Map.get(:accounted, [])
      |> List.first(%{})
      |> Map.get(:user, %{})
      |> Map.merge(%{accounted: %{account: account}})
      |> debug("attempted to get user from account")
    end
  end

  def account_by(account) when is_binary(account) or is_map(account) do
    with {:ok, account} <-
           Utils.maybe_apply(Accounts, :get_current, uid(account)) do
      account
    end
  end

  def username(%{current_user: current_user}) do
    username(current_user)
  end

  def username(user) do
    e(user, :character, :username, nil)
  end
end
