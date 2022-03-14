# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Cursor do
  defstruct data: nil, normalized: nil, raw: nil, errors: [], flags: %{}, open_ended: false

  use Absinthe.Schema.Notation
  alias Absinthe.Blueprint.Input

  @desc """
  An opaque position marker for pagination. Paginated queries return
  a PageInfo struct with start and end cursors (which are actually
  lists of Cursor for ...reasons...). You can then issue queries
  requesting results `before` the `start` or `after` the `end`
  cursors to request the previous or next page respectively.

  Is actually a string or integer, typically an ID.
  Can also be include encoded data describing how a query is ordered.
  May be extended in future.
  """
  scalar :cursor, name: "Cursor" do

    parse &decode/1
    serialize &encode/1
  end

  @spec decode(Input.String.t()) :: {:ok, binary}
  @spec decode(Input.Integer.t()) :: {:ok, integer}
  @spec decode(term) :: {:error, :bad_parse}
  defp decode(%Input.String{value: value}), do: {:ok, value}
  defp decode(%Input.Integer{value: value}), do: {:ok, value}
  defp decode(_alien), do: {:error, :bad_parse}

  defp encode(value), do: value
end
