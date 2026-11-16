defmodule Bonfire.API.GraphQL.UserSocket do
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket,
    schema: Bonfire.API.GraphQL.Schema

  # Deprecated in Phoenix v1.4
  transport(:websocket, Phoenix.Transports.WebSocket)

  alias Bonfire.API.GraphQL.Auth

  def connect(params, socket, connect_info \\ %{}) do
    socket =
      Absinthe.Phoenix.Socket.put_opts(socket,
        context: build_context(params, connect_info)
      )

    {:ok, socket}
  end

  @doc """
  Builds the Absinthe context only from a verified bearer token (the `token` connect param, or an `Authorization: Bearer` header), exactly like the HTTP GraphQL endpoint. Identity claimed in plain connect params is never trusted: without a valid token the socket is a guest (empty context).
  """
  def build_context(params, connect_info) do
    with token when is_binary(token) <- bearer_token(params, connect_info),
         {:ok, ids} <- Auth.token_verify(token),
         %{} = user <- Auth.user_by(ids),
         %{} = account <- Bonfire.API.GraphQL.current_account(user) do
      %{
        current_user: user,
        current_username: Auth.username(user),
        current_account: account,
        current_account_id: Bonfire.Common.Enums.id(account)
      }
    else
      _ -> %{}
    end
  end

  defp bearer_token(params, connect_info) do
    header =
      connect_info
      |> Map.get(:x_headers, [])
      |> Enum.find_value(fn {k, v} -> String.downcase(k) == "authorization" && v end)

    strip_bearer(header) || strip_bearer(params["token"])
  end

  defp strip_bearer(value) when is_binary(value) do
    case String.split(value, " ", parts: 2) do
      [scheme, token] -> if String.downcase(scheme) == "bearer", do: token
      [token] when token != "" -> token
      _ -> nil
    end
  end

  defp strip_bearer(_), do: nil

  def id(_socket), do: nil
end
