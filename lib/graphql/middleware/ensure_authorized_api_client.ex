# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.EnsureAuthorizedAPIClient do
  @moduledoc """
  Absinthe middleware that requires the request to be authorized by either:
  - An authenticated user (session, Phoenix.Token bearer, or OAuth2 user token)
  - A valid OAuth2 API client (client_credentials token, no user)

  Applied automatically to all root query and mutation fields (see `middleware/3` below, called from the schema) except:
  - GraphQL introspection fields (`__schema`, `__type`, `__typename`)
  - Fields explicitly marked with `meta public: true` (the pre-login account flows, and what a guest can read in the web UI, which stays subject to boundaries)
  - Internal calls (`internal_call: true` in the context), such as those made by the Mastodon API adapters, which do their own authorisation
  """

  @behaviour Absinthe.Middleware

  @doc "Adds this middleware in front of a root query or mutation field's own middleware, unless the field is public or an introspection field."
  def middleware(middleware, field, %{identifier: root}) when root in [:query, :mutation] do
    if public_field?(field), do: middleware, else: [{__MODULE__, []} | middleware]
  end

  def middleware(middleware, _field, _object), do: middleware

  defp public_field?(%{identifier: identifier} = field) do
    String.starts_with?(to_string(identifier), "__") or Absinthe.Type.meta(field, :public) == true
  end

  # Internal calls (e.g. from the Masto API adapters) are authorised by the caller
  def call(%{context: %{internal_call: true}} = resolution, _), do: resolution

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
