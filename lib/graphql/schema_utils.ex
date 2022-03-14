defmodule Bonfire.API.GraphQL.SchemaUtils do
  def hydrations_merge(hydrators) do
    Enum.reduce(hydrators, %{}, fn mod,
    hydrated ->
      hydrate_merge(hydrated, maybe_hydrate(mod))
    end)
  end

  defp hydrate_merge(a, b) do
    Map.merge(a, b, fn _, a, b -> Map.merge(a, b) end)
  end

  defp maybe_hydrate(mod) do
    if Bonfire.Common.Utils.module_enabled?(mod), do: mod.hydrate(), else: %{}
  end

  def context_types() do
    schemas = Bonfire.Common.Pointers.Tables.list_schemas()

    Enum.reduce(schemas, [], fn schema, acc ->
      if Bonfire.Common.Utils.module_enabled?(schema) and function_exported?(schema, :type, 0) and
           !is_nil(apply(schema, :type, [])) do
        Enum.concat(acc, [apply(schema, :type, [])])
      else
        acc
      end
    end)
  end


  # defmacro import_many_types(types) do # TODO / doesn't work with Absinthe
  #   quote do
  #     Enum.map(unquote(types), fn(schema_module) ->
  #       import_types(schema_module)
  #     end)
  #   end
  # end

end
