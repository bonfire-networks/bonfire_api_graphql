# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.EnsureAuthorizedAPIClient do
  @moduledoc """
  Absinthe middleware that requires the request to be authorized by either:
  - An authenticated user (session, Phoenix.Token bearer, or OAuth2 user token)
  - A valid OAuth2 API client (client_credentials token, no user)

  Applied automatically to all query and mutation fields except:
  - GraphQL introspection fields (`__schema`, `__type`, `__typename`)
  - Fields explicitly marked with `meta public: true`
  """

  @behaviour Absinthe.Middleware

  # Authenticated user via session or bearer token
  def call(%{context: %{current_account_id: id}} = resolution, _) when is_binary(id),
    do: resolution

  def call(%{context: %{current_user: %{id: id}}} = resolution, _) when is_binary(id),
    do: resolution

  # Valid OAuth2 client (client_credentials — no user, but verified client)
  def call(%{context: %{current_token: %{client: %{id: id}}}} = resolution, _)
      when is_binary(id),
      do: resolution

  def call(resolution, _),
    do: Absinthe.Resolution.put_result(resolution, {:error, :needs_login})
end
