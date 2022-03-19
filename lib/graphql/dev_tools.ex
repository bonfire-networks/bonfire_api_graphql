defmodule Bonfire.API.GraphQL.DevTools do
  use Bonfire.Web, :controller

  @schema Bonfire.Common.Config.get!(:graphql_schema_module)

  def schema(conn, _params) do
    sdl = Absinthe.Schema.to_sdl(@schema)
    # "schema {
    #   query {...}
    # }"

    text(conn, sdl)
  end
end
