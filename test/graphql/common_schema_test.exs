defmodule Bonfire.API.GraphQL.CommonSchemaTest do
  use Bonfire.API.MastoApiCase, async: true

  alias Bonfire.API.GraphQL.Schema

  @moduletag :graphql

  test "Subject type has id and label fields" do
    {:ok, result} = Absinthe.run(~S|{ __type(name: "Subject") { fields { name } } }|, Schema)
    names = get_in(result, [:data, "__type", "fields"]) |> Enum.map(& &1["name"])
    assert "id" in names
    assert "label" in names
    refute result[:errors]
  end

  test "KeyValueEntry type has key and value fields" do
    {:ok, result} =
      Absinthe.run(~S|{ __type(name: "KeyValueEntry") { fields { name } } }|, Schema)

    names = get_in(result, [:data, "__type", "fields"]) |> Enum.map(& &1["name"])
    assert "key" in names
    assert "value" in names
    refute result[:errors]
  end

  test "KeyBooleanEntry type has key and value fields" do
    {:ok, result} =
      Absinthe.run(~S|{ __type(name: "KeyBooleanEntry") { fields { name } } }|, Schema)

    names = get_in(result, [:data, "__type", "fields"]) |> Enum.map(& &1["name"])
    assert "key" in names
    assert "value" in names
    refute result[:errors]
  end
end
