# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Plugs.Limits do
  @moduledoc """
  Refuses abusive requests to the GraphQL endpoint before Absinthe sees them: too many requests from one IP (429), too many queries in one JSON batch (400), and schema introspection by a guest when public introspection is off (401).

  Use after `Bonfire.API.GraphQL.Plugs.GraphQLContext`, so the signed-in user is known.

  Tunables (see `Bonfire.API.GraphQL.RuntimeConfig` and the `:graphql` entry of `:bonfire, :rate_limit`):
  - `config :bonfire_api_graphql, :max_batch` (default 10 queries per request)
  - `config :bonfire_api_graphql, :public_introspection` (default: on, except in prod)
  """

  import Plug.Conn
  require Bonfire.Common.Config
  alias Bonfire.Common.Config

  @default_max_batch 10

  # the per-minute cap on requests from one IP, when `:bonfire, :rate_limit, :graphql` does not set one
  @default_rate_scale_ms 60_000
  @default_rate_limit 60

  def init(opts), do: opts

  def call(conn, _opts) do
    with :ok <- check_rate(conn),
         :ok <- check_batch(conn),
         :ok <- check_introspection(conn) do
      conn
    else
      {:refuse, status, message, headers} ->
        conn
        |> then(&Enum.reduce(headers, &1, fn {k, v}, c -> put_resp_header(c, k, v) end))
        |> put_resp_content_type("application/json")
        |> send_resp(status, Jason.encode!(%{errors: [%{message: message}]}))
        |> halt()
    end
  end

  # Tests share one IP and hit this endpoint far more often than any client would, so the cap only applies in the test env when asked for with `:rate_limit_in_test`.
  defp check_rate(conn) do
    if Config.env() == :test and
         not Config.get([:bonfire_api_graphql, :rate_limit_in_test], false),
       do: :ok,
       else: do_check_rate(conn)
  end

  defp do_check_rate(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Bonfire.UI.Common.RateLimit.check(
           :graphql,
           ip,
           @default_rate_scale_ms,
           @default_rate_limit
         ) do
      :ok ->
        :ok

      {:error, retry_after} ->
        {:refuse, 429, "Too many requests", [{"retry-after", to_string(retry_after)}]}
    end
  end

  defp check_batch(%{params: %{"_json" => queries}}) when is_list(queries) do
    max = Config.get([:bonfire_api_graphql, :max_batch], @default_max_batch)

    if length(queries) > max,
      do: {:refuse, 400, "Too many queries in one request, the maximum is #{max}", []},
      else: :ok
  end

  defp check_batch(_), do: :ok

  defp check_introspection(conn) do
    if public_introspection?() or signed_in?(conn) or not introspects?(conn) do
      :ok
    else
      {:refuse, 401, "You need to log in to query the schema", []}
    end
  end

  @doc "Whether guests may read the schema (`__schema`/`__type` queries and `GET /api/schema`)."
  def public_introspection?,
    do: Config.get([:bonfire_api_graphql, :public_introspection], true) == true

  @doc "Whether the request was made by a signed-in user or an authorised API client."
  def signed_in?(conn) do
    case conn.private[:absinthe] do
      %{context: %{} = context} ->
        not is_nil(context[:current_user]) or not is_nil(context[:current_account_id]) or
          not is_nil(context[:current_token])

      _ ->
        false
    end
  end

  defp introspects?(%{params: params}) do
    params
    |> queries()
    |> Enum.any?(&Regex.match?(~r/\b__(schema|type)\b/, &1))
  end

  defp queries(%{"_json" => list}) when is_list(list), do: Enum.flat_map(list, &queries/1)
  defp queries(%{"query" => query}) when is_binary(query), do: [query]
  defp queries(_), do: []
end
