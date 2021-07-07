# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.GraphQL.Plugs.GraphQLContext do
  @moduledoc """
  GraphQL Plug to add current user to the context
  """

  def init(opts), do: opts

  def call(conn, _) do
    context = Bonfire.GraphQL.Auth.build_context_from_session(conn)
    Absinthe.Plug.put_options(conn, context: context)
  end

end
