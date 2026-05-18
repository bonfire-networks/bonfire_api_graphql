# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.RateLimit do
  @moduledoc """
  Absinthe middleware that applies rate limiting to specific fields/mutations.

  The bucket atom (e.g. `:forms`, `:api`) is passed as middleware opts and must
  match a key under `:bonfire, :rate_limit` config.

  Skips automatically when the call originates from an internal AbsintheClient
  call (e.g. Masto API adapters), so the Masto API pipeline's own rate limit
  is the only one that counts for those requests.

  # TODO: consider per-operation or complexity-based budgets in the future
  """

  @behaviour Absinthe.Middleware

  # Internal AbsintheClient calls (e.g. from Masto API adapters) — skip
  def call(%{context: %{internal_call: true}} = resolution, _bucket), do: resolution

  def call(resolution, false), do: resolution

  def call(resolution, true), do: call(resolution, :api)

  def call(%{context: %{ip: ip}} = resolution, bucket) when is_atom(bucket) do
    case Bonfire.UI.Common.RateLimit.check(bucket, ip) do
      :ok ->
        resolution

      {:error, retry_after_seconds} ->
        Absinthe.Resolution.put_result(
          resolution,
          {:error,
           %{
             message: "Too many requests",
             extensions: %{retry_after: retry_after_seconds}
           }}
        )
    end
  end

  # No IP in context — skip (should not happen for external HTTP calls)
  def call(resolution, _bucket), do: resolution
end
