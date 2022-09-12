defmodule Bonfire.API.GraphQL.PlugPipelines do
  # alias Bonfire.API.GraphQL.Phase.Arguments
  alias Absinthe.Phase
  alias Absinthe.Pipeline

  def default_pipeline(config, opts) do
    Absinthe.Plug.default_pipeline(config, opts)

    # |> Pipeline.replace( # FIXME: this breaks triggering subscription notifications
    #   Phase.Document.Execution.Resolution,
    #   Bonfire.API.GraphQL.Phase.ExecutionResolution
    # )

    # |> Pipeline.insert_after(Phase.Schema.TypeImports, __MODULE__)
    # |> Pipeline.insert_before(Phase.Document.Result, Bonfire.API.GraphQL.Phase.Debug)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Parse)
    # |> Pipeline.insert_before(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.insert_after(Phase.Document.Arguments.Parse, Arguments.Debug)
    # |> Pipeline.replace(Phase.Document.Arguments.FlagInvalid, Arguments.FlagInvalid)
    # |> Pipeline.replace(Phase.Document.Arguments.Data, Arguments.Data)
  end

  # This receives (and should also return) the blueprint of the schema:
  def run(blueprint, _) do
    {
      :ok,
      blueprint

      # |> IO.inspect(label: "blueprint")
    }
  end
end
