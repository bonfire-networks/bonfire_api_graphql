# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.CollapseErrors do
  @behaviour Absinthe.Middleware

  alias AbsintheErrorPayload.ChangesetParser

  def call(resolution, _) do
    %{resolution | errors: collapse(resolution.errors)}
  end

  def collapse(list) when is_list(list), do: List.flatten(Enum.map(list, &collapse/1))

  def collapse(%Ecto.Changeset{} = changeset),
    do: extract_messages(changeset)

  def collapse(%{__struct__: _} = struct), do: Map.from_struct(struct)

  def collapse(other), do: Bonfire.Fail.fail(other) |> collapse()
  def collapse(other, extra), do: Bonfire.Fail.fail(other, extra) |> Map.from_struct()

  defp extract_messages(changeset) do
    # IO.inspect(changeset: changeset)
    messages = ChangesetParser.extract_messages(changeset)

    for message <- messages do
      message
      |> Map.take([:code, :message, :field])
      |> Map.put_new(:status, 200)
    end
  end
end
