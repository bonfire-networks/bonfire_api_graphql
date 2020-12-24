defmodule Bonfire.GraphQL.Auth do

  @doc """
  Resolver for login mutation for Bonfire.GraphQL.CommonSchema
  """
  def login(_, %{email_or_username: email_or_username, password: password} = attrs, _) do
    if Code.ensure_loaded?(Bonfire.Me.Identity.Accounts) do
      with {:ok, account} <- Bonfire.Me.Identity.Accounts.login(attrs) do
        user = account |> Map.get(:accounted, []) |> hd() |> Map.get(:user, nil)
        {:ok, %{current_account: account, current_user: user}}
      else e ->
        {:error, e}
      end
    else
      {:error, "Your app's authentication is not integrated with this GraphQL mutation."}
    end
  end

  @doc """
  Puts the account/user data in Absinthe context (runs after on `login/3` resolver)
  """
  def set_context_from_resolution(%{value: %{current_user: current_user, current_account: current_account}} = resolution, _) do
    Map.update!(
      resolution,
      :context,
      &Map.merge(&1, %{current_account: current_account, current_user: current_user})
    )
  end

  def set_context_from_resolution(resolution, _) do
    resolution
  end

  @doc """
  Sets session cookie based on the Absinthe context set in `set_context_from_resolution/2` (called from router's `absinthe_before_send/2` )
  """
  def set_session_from_context(conn, %Absinthe.Blueprint{execution: %{context: %{current_account: %{id: current_account_id}} = context}}) when not is_nil(current_account_id) do
    IO.inspect(absinthe_before_send_set_session: context)
      conn
      |>
      Plug.Conn.put_session(:current_account_id, current_account_id)
      |>
      Plug.Conn.put_session(:current_username, Bonfire.Common.Utils.e(context, :current_user, :character, :username, nil))
  end

  def set_session_from_context(conn, _) do
    conn
  end

  @doc """
  Once authenticated, load the context based on session (called from `Bonfire.GraphQL.Plugs.GraphQLContext`)
  """
  def build_context_from_session(conn) do
    IO.inspect(session: Plug.Conn.get_session(conn))
    IO.inspect(assigns: conn.assigns)
    %{
      current_account_id: conn.assigns[:current_account_id] || Plug.Conn.get_session(conn, :current_account_id),
      current_username: conn.assigns[:current_username] || Plug.Conn.get_session(conn, :current_username),
      current_account: conn.assigns[:current_account],
      current_user: conn.assigns[:current_user]
    }
  end

  def user_by(username, account_id) when is_binary(username) and is_binary(account_id) do
    if Code.ensure_loaded?(Bonfire.Me.Identity.Users) do
        with {:ok, user} = Bonfire.Me.Identity.Users.for_switch_user(username, account_id) do
          user
        end
    # else {:error, "Your app's account/user modules are not integrated with GraphQL."}
    end
  end

end


# Temporary hack to allow encoding user data as JSON scalar
defimpl Jason.Encoder, for: [Bonfire.Data.Identity.Accounted, Bonfire.Data.Identity.Account, Bonfire.Data.Identity.User, Bonfire.Data.Identity.Character, Bonfire.Data.Social.Profile] do
  def encode(struct, opts) do
    # IO.inspect(input: struct)

    Map.from_struct(struct)
    |>
    Map.drop([:__meta__])
    |>
    Enum.reduce(%{}, fn
      ({k, %Ecto.Association.NotLoaded{}}, acc) -> acc
      # ({__meta__, _}, acc) -> acc
      ({k, %Bonfire.Data.Social.Profile{} = v}, acc) -> Map.put(acc, k, v)
      ({k, %Bonfire.Data.Identity.Character{} = v}, acc) -> Map.put(acc, k, v)
      ({k, %{__struct__: _} = sub_struct}, acc) -> acc #Map.put(acc, k, Jason.encode!(sub_struct))
      ({k, v}, acc) ->
        Map.put(acc, k, v)
      (_, acc) ->
       acc
    end)
    # |> IO.inspect()
    |> Jason.Encode.map(opts)
  end
end
