# defmodule Bonfire.GraphQL.DevTools do
#   use ActivityPubWeb, :controller

#   @schema Bonfire.Common.Config.get!(:graphql_schema_module)

#   def schema(conn, _params) do
#     sdl = Absinthe.Schema.to_sdl(@schema)
#     # "schema {
#     #   query {...}
#     # }"

#     html(conn, sdl)
#   end
# end
