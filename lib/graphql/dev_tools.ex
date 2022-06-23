defmodule Bonfire.API.GraphQL.DevTools do
  use Bonfire.UI.Common.Web, :controller

  def schema(conn, _params) do
    text(conn, sdl())
  end

  def sdl do
    Absinthe.Schema.to_sdl(Bonfire.Common.Config.get!(:graphql_schema_module))
  end
end
