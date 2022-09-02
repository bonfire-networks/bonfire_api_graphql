# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.JSON do
  @moduledoc """
  The Json scalar type allows arbitrary JSON values to be passed in and out.
  Requires `{ :jason, "~> 1.1" }` package: https://github.com/michalmuskala/jason
  """
  defstruct data: nil, normalized: nil, raw: nil, errors: [], flags: %{}, open_ended: false
  import Untangle
  alias Absinthe.Blueprint.Input
  use Absinthe.Schema.Notation
  require Protocol

  scalar :json, name: "Json" do
    description("Arbitrary json stored as a string")
    serialize(&encode/1)
    parse(&decode/1)
  end

  @spec decode(Input.String.t()) :: {:ok, term} | {:error, term}
  @spec decode(Input.Null.t()) :: {:ok, nil}
  defp decode(%Input.String{value: value}) do
    try do
      {:ok, Jason.decode!(value)}
    rescue e ->
      error(e)
      :error
    end
  end
  defp decode(%Input.Null{}), do: {:ok, nil}
  defp decode(_), do: :error

  defp encode(%Geo.Point{} = geo) do
    with {:ok, geo_json} <- Geo.JSON.encode(geo) do
      geo_json
    end
  end

  defp encode(value) when is_struct(value) do
    value
  end

  defp encode(value), do: value
end
