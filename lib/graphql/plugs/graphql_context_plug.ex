# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Plugs.GraphQLContext do
  @moduledoc """
  GraphQL Plug to add current user to the context
  """

  def init(opts), do: opts

  def call(conn, _) do
    context = Bonfire.API.GraphQL.Auth.build_context(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end
end
