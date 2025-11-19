defmodule Bonfire.API.GraphQL.QueryHelper do
  @moduledoc """
  Helpful functions for preparing to query or test Absinthe applications.

  These functions make it trivially easy to generate very large, comprehensive queries for our types in Absinthe that will resolve every field in that type (and any number of subtypes as well to a given level of depth)

  Adapted from https://github.com/devonestes/assertions (MIT license)
  """

  import Untangle

  @spec run_query_id(
          any(),
          module(),
          atom(),
          non_neg_integer(),
          Keyword.t(),
          boolean()
        ) ::
          String.t()
  def run_query_id(
        id,
        schema,
        type,
        nesting \\ 1,
        override_fun \\ nil,
        debug \\ nil
      ) do
    q = query_with_id(schema, type, nesting, override_fun)

    with {:ok, go} <- Absinthe.run(q, schema, variables: %{"id" => id}) do
      maybe_debug_api(q, go, debug)

      go |> Map.get(:data) |> Map.get(Atom.to_string(type))
    else
      e ->
        error("The GraphQL query failed")
        maybe_debug_api(q, e, true, "Query failed")
        e
    end
  end

  @spec query_with_id(module(), atom(), non_neg_integer(), Keyword.t()) ::
          String.t()
  def query_with_id(schema, type, nesting \\ 1, override_fun \\ nil) do
    document = document_for(schema, type, nesting, override_fun)

    """
     query ($id: ID) {
       #{type}(id: $id) {
         #{document}
       }
     }
    """
  end

  @doc """
  Returns a document containing the fields in a type and any sub-types down to a limited depth of
  nesting (default `3`).

  This is helpful for generating a document to use for testing your GraphQL API. This function
  will always return all fields in the given type, ensuring that there aren't any accidental
  fields with resolver functions that aren't tested in at least some fashion.

  ## Example

      iex> document_for(:user, 2)

      ```
      name
      age
      posts {
        title
        subtitle
      }
      comments {
        body
      }
      ```

  """
  @spec document_for(module(), atom(), non_neg_integer(), Keyword.t()) ::
          String.t()
  def document_for(schema, type, nesting \\ 1, override_fun \\ nil) do
    schema
    |> fields_for(type, nesting)
    |> apply_overrides(override_fun)
    |> format_fields(type, 10, schema)
    |> List.to_string()
  end

  @doc """
  Returns all fields in a type and any sub-types down to a limited depth of nesting (default `3`).

  This is helpful for converting a struct or map into an expected response that is a bare map
  and which can be used in some of the other assertions below.
  """
  @spec fields_for(module(), atom(), non_neg_integer()) :: list(fields) | atom()
        when fields: atom() | {atom(), list(fields)}
  def fields_for(schema, %{of_type: type}, nesting) do
    # We need to unwrap non_null and list sub-fields
    fields_for(schema, type, nesting)
  end

  def fields_for(schema, type, nesting) do
    type
    |> schema.__absinthe_type__()
    |> get_fields(schema, nesting)
  end

  # At maximum nesting depth, only include the id field if present
  # This prevents infinite nesting while keeping a reference to the object
  def get_fields(%{fields: %{id: _}}, _schema, 0) do
    [:id]
  end

  # At maximum depth without an id field, return empty list to signal
  # this field should not be included (would create invalid GraphQL)
  def get_fields(%{fields: _}, _schema, 0) do
    []
  end

  # Process object types with fields - recursively build field list
  def get_fields(%{fields: fields}, schema, depth) when is_map(fields) do
    fields
    |> Enum.reduce([], fn {_key, field}, acc ->
      field_name = String.to_atom(field.name)

      case fields_for(schema, field.type, depth - 1) do
        # Empty result - skip this field
        [] ->
          acc

        # Scalar field - include just the field name
        :scalar ->
          [field_name | acc]

        # Nested object - include field name with sub-fields
        nested when is_list(nested) ->
          [{field_name, nested} | acc]
      end
    end)
    |> Enum.reverse()
  end

  # Scalar types or anything without fields - terminal value
  def get_fields(_type_def, _schema, _depth) do
    :scalar
  end

  def format_fields(fields, _, 10, schema) do
    fields =
      fields
      |> Enum.reduce({[], 12}, &do_format_fields(&1, &2, schema))
      |> elem(0)

    Enum.reverse(fields)
  end

  def format_fields(fields, type, left_pad, schema) do
    fields =
      fields
      |> Enum.reduce(
        {["#{camelize(type)} {\n"], left_pad + 2},
        &do_format_fields(&1, &2, schema)
      )
      |> elem(0)

    Enum.reverse(["}\n", padding(left_pad) | fields])
  end

  def do_format_fields({type, sub_fields}, {acc, left_pad}, schema) do
    {[
       format_fields(sub_fields, type, left_pad, schema),
       padding(left_pad) | acc
     ], left_pad}
  end

  def do_format_fields(type, {acc, left_pad}, _) do
    {["\n", camelize(type), padding(left_pad) | acc], left_pad}
  end

  def apply_overrides(fields, override_fun) when is_function(override_fun) do
    for n <- fields, do: override_fun.(n)
  end

  def apply_overrides(fields, _) do
    fields
  end

  # utils - TODO: move to generic module
  def padding(0), do: ""
  def padding(left_pad), do: Enum.map(1..left_pad, fn _ -> " " end)

  def camelize(type), do: Absinthe.Utils.camelize(to_string(type), lower: true)

  def maybe_debug_api(
        q,
        %{errors: errors} = obj,
        _,
        msg \\ "The below GraphQL query had some errors in the response"
      ) do
    warn(errors, msg)
    maybe_debug_api(q, Map.get(obj, :data), true)
  end

  def maybe_debug_api(q, obj, debug, msg) do
    # || Bonfire.Common.Config.get([:logging, :tests_output_graphql]) do
    if debug do
      info(q, "GraphQL query")
      info(obj, "GraphQL response")
    end
  end
end
