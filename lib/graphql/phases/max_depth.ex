# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Phase.MaxDepth do
  @moduledoc """
  Absinthe phase that refuses a document whose fields nest deeper than `:max_depth` (counting through fragments), before it is validated or resolved. Runs on the parsed document, so a hostile query is never expanded.
  """

  use Absinthe.Phase

  alias Absinthe.Language

  @impl Absinthe.Phase
  def run(
        %Absinthe.Blueprint{input: %Language.Document{definitions: definitions}} = blueprint,
        opts
      ) do
    max = Keyword.fetch!(opts, :max_depth)
    fragments = for %Language.Fragment{name: name} = f <- definitions, into: %{}, do: {name, f}

    deepest =
      definitions
      |> Enum.filter(&match?(%Language.OperationDefinition{}, &1))
      |> Enum.map(&depth(&1.selection_set, fragments, []))
      |> Enum.max(fn -> 0 end)

    if deepest > max do
      error = %Absinthe.Phase.Error{
        message:
          "Query is too deep: its fields nest #{deepest} levels, the maximum depth is #{max}",
        phase: __MODULE__
      }

      {:jump, put_in(blueprint.execution.validation_errors, [error]),
       Absinthe.Phase.Document.Result}
    else
      {:ok, blueprint}
    end
  end

  def run(blueprint, _opts), do: {:ok, blueprint}

  # `visiting` holds the fragments being expanded, so a fragment spreading itself does not loop (validation refuses it later)
  defp depth(nil, _fragments, _visiting), do: 0

  defp depth(%Language.SelectionSet{selections: selections}, fragments, visiting) do
    selections
    |> Enum.map(&selection_depth(&1, fragments, visiting))
    |> Enum.max(fn -> 0 end)
  end

  defp selection_depth(%Language.Field{selection_set: set}, fragments, visiting),
    do: 1 + depth(set, fragments, visiting)

  defp selection_depth(%Language.InlineFragment{selection_set: set}, fragments, visiting),
    do: depth(set, fragments, visiting)

  defp selection_depth(%Language.FragmentSpread{name: name}, fragments, visiting) do
    case fragments do
      %{^name => fragment} ->
        if name in visiting,
          do: 0,
          else: depth(fragment.selection_set, fragments, [name | visiting])

      _ ->
        0
    end
  end

  defp selection_depth(_, _fragments, _visiting), do: 0
end
