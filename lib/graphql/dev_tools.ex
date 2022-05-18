defmodule Bonfire.API.GraphQL.DevTools do
  use Bonfire.UI.Common.Web, :controller

  def schema(conn, _params) do
    sdl = Absinthe.Schema.to_sdl(Bonfire.Common.Config.get!(:graphql_schema_module))
    # "schema {
    #   query {...}
    # }"

    text(conn, sdl)
  end
end
