defmodule Bonfire.GraphQL.PlugPipelines do
  # alias Bonfire.GraphQL.Phase.Arguments
  alias Absinthe.{Phase, Pipeline}

  def default_pipeline(config, opts) do
    Absinthe.Plug.default_pipeline(config, opts)
    |> Pipeline.replace(
      Phase.Document.Execution.Resolution,
      Bonfire.GraphQL.Phase.ExecutionResolution
    )
    # |> Pipeline.insert_after(Phase.Schema.TypeImports, __MODULE__)
    # |> Pipeline.insert_before(Phase.Document.Result, Bonfire.GraphQL.Phase.Debug)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Parse)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.insert_after(Phase.Document.Arguments.Parse, Arguments.Debug)
    # # |> Pipeline.replace(Phase.Document.Arguments.FlagInvalid, Arguments.FlagInvalid)
    # |> Pipeline.replace(Phase.Document.Arguments.Data, Arguments.Data)
  end

  # This receives (and should also return) the blueprint of the schema:
  def run(blueprint, _) do
    {:ok, blueprint |> IO.inspect(label: "blueprint")}
  end

end
