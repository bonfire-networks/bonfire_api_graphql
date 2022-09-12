defmodule Bonfire.API.GraphQL.SchemaPipelines do
  alias Absinthe.Phase
  alias Absinthe.Pipeline
  alias Absinthe.Blueprint

  # Add this module to the pipeline of phases
  # to run on the schema
  def pipeline(pipeline) do
    pipeline

    # |> Pipeline.insert_after(Phase.Schema.TypeImports, __MODULE__)
    # |> Pipeline.insert_before(Phase.Document.Result, Bonfire.API.GraphQL.Phase.Debug)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Parse)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.insert_after(Phase.Document.Arguments.Parse, Arguments.Debug)
    # # |> Pipeline.replace(Phase.Document.Arguments.FlagInvalid, Arguments.FlagInvalid)
    # |> Pipeline.replace(Phase.Document.Arguments.Data, Arguments.Data)
  end

  # This receives (and should also return) the blueprint of the schema:
  def run(blueprint, _) do
    {:ok, IO.inspect(blueprint, label: "blueprint")}
  end
end
