defmodule Bonfire.API.GraphQL.UserSocket do
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket,
    schema: Bonfire.API.GraphQL.Schema

  # Deprecated in Phoenix v1.4
  transport(:websocket, Phoenix.Transports.WebSocket)

  def connect(params, socket) do
    socket =
      Absinthe.Phoenix.Socket.put_opts(socket,
        context: build_context_from_params(params, socket)
      )

    {:ok, socket}
  end

  def build_context_from_params(params, socket) do
    %{
      current_account_id: params["current_account_id"],
      current_username: params["current_username"],
      current_account: params["current_account"],
      current_user: params["current_user"]
    }
  end

  def id(_socket), do: nil
end
