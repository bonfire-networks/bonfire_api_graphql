defmodule Bonfire.API.GraphQL.DevTools do
  use Bonfire.UI.Common.Web, :controller

  alias Bonfire.API.GraphQL.Plugs.Limits

  def schema(conn, _params) do
    if Limits.public_introspection?() or Limits.signed_in?(conn) do
      text(conn, sdl())
    else
      conn
      |> put_status(401)
      |> json(%{errors: [%{message: "You need to log in to read the schema"}]})
    end
  end

  def sdl do
    Absinthe.Schema.to_sdl(Bonfire.Common.Config.get!(:graphql_schema_module))
  end
end
