# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.EnsureAuthorizedAPIClient do
  @moduledoc """
  Absinthe middleware that requires the request to be made by an authenticated user (session, Phoenix.Token bearer, or OAuth2 user token).

  A token with no user (a `client_credentials` token, which belongs to an app only) is a guest: it passes only the fields marked `meta public: true`.

  A request carrying an OAuth token also needs the `write` scope, or a `write:*` scope, for a mutation. Reads are unchanged, and so are session and Phoenix.Token requests, which carry no OAuth token.

  Applied automatically to all root query and mutation fields (see `middleware/3` below, called from the schema) except:
  - GraphQL introspection fields (`__schema`, `__type`, `__typename`)
  - Fields explicitly marked with `meta public: true` (the pre-login account flows, and what a guest can read in the web UI, which stays subject to boundaries)

  The Mastodon API adapters call the resolvers with a `current_user` in the context, so they pass as authenticated users.
  """

  @behaviour Absinthe.Middleware

  alias Boruta.Oauth.Scope

  @doc "Adds this middleware in front of a root query or mutation field's own middleware, unless the field is public or an introspection field."
  def middleware(middleware, field, %{identifier: root}) when root in [:query, :mutation] do
    if public_field?(field), do: middleware, else: [{__MODULE__, root: root} | middleware]
  end

  def middleware(middleware, _field, _object), do: middleware

  defp public_field?(%{identifier: identifier} = field) do
    String.starts_with?(to_string(identifier), "__") or Absinthe.Type.meta(field, :public) == true
  end

  # (no code sets `internal_call` for this middleware; a user-less token must not bypass the gate)
  # def call(%{context: %{internal_call: true}} = resolution, _), do: resolution

  # Authenticated user via session or bearer token
  def call(%{context: %{current_account_id: id}} = resolution, opts) when is_binary(id),
    do: check_scope(resolution, opts)

  def call(%{context: %{current_user: %{id: id}}} = resolution, opts) when is_binary(id),
    do: check_scope(resolution, opts)

  # A valid OAuth2 client with no user (client_credentials) is a guest
  # def call(%{context: %{current_token: %{client: %{id: id}}}} = resolution, _)
  #     when is_binary(id),
  #     do: resolution

  def call(resolution, _),
    do: Absinthe.Resolution.put_result(resolution, {:error, :needs_login})

  # A mutation made with an OAuth token needs `write` or a `write:*` scope
  defp check_scope(%{context: %{current_token: %{scope: scope}}} = resolution, opts)
       when is_binary(scope) do
    if opts[:root] != :mutation or write_scope?(scope) do
      resolution
    else
      Absinthe.Resolution.put_result(
        resolution,
        {:error, "This action is outside the authorized scopes."}
      )
    end
  end

  defp check_scope(%{context: %{current_token: %{}}} = resolution, opts) do
    if opts[:root] == :mutation do
      Absinthe.Resolution.put_result(
        resolution,
        {:error, "This action is outside the authorized scopes."}
      )
    else
      resolution
    end
  end

  defp check_scope(resolution, _opts), do: resolution

  defp write_scope?(scope) do
    scope
    |> Scope.split()
    |> Enum.any?(&(&1 == "write" or String.starts_with?(&1, "write:")))
  end
end
