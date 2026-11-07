# SPDX-License-Identifier: AGPL-3.0-only
# Always defined, like `Bonfire.API.GraphQL.Test.GraphQLFields`: `jsv` is a dev/test-only dependency, so JSV is only called remotely (no `import`/`alias` needing it at compile time), and nothing calls this module in prod
defmodule Bonfire.API.MastoCompat.Test.MastoSchema do
  @moduledoc """
  Checks a Mastodon API response entity the way clients read it, for use in tests.

  `assert_masto_entity/2` checks two things and flunks with every problem it finds:

  - the entity matches its schema (eg. `"Status"`, `"Account"`) in the vendored Mastodon OpenAPI spec (`priv/specs/mastodon-openapi-abraham.json`, see the README there): required fields present, JSON types right, formats (`date-time`, `uri`) valid;
  - the fields that clients decode without a default are not null, even where the spec allows null (see `@client_required`). This also checks the entities nested in it (a Status's account and reblog).
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @spec_file "specs/mastodon-openapi-abraham.json"

  # Fields that clients decode without a default, so a null or missing value fails the whole entity (and often the whole timeline page)
  @client_required %{
    # Tusky https://codeberg.org/tusky/Tusky/src/branch/main/app/src/main/java/com/keylesspalace/tusky/entity/Status.kt
    "Status" =>
      ~w(id account content created_at emojis reblogs_count favourites_count replies_count sensitive spoiler_text visibility media_attachments mentions),
    # Tusky https://codeberg.org/tusky/Tusky/src/branch/main/app/src/main/java/com/keylesspalace/tusky/entity/Account.kt and Mastodon for iOS https://github.com/mastodon/mastodon-ios/blob/develop/MastodonSDK/Sources/MastodonSDK/Entity/Mastodon+Entity+Account.swift
    "Account" =>
      ~w(id username acct url display_name note avatar header locked emojis created_at followers_count following_count statuses_count)
  }

  # Corrections to the vendored spec, applied before it's built: {path in the spec, replacement, why}. The spec is generated from Mastodon's docs, so where Mastodon's serializers send something else, the serializer wins; and a few fields Bonfire can't match exactly
  @spec_corrections [
    {~w(components schemas NotificationGroup properties most_recent_notification_id type),
     "string",
     "Mastodon sends it as a string: `object.most_recent_notification_id.to_s` in `REST::NotificationGroupSerializer`"},
    {~w(components schemas WebPushSubscription properties id type), ["integer", "string"],
     "Mastodon sends its integer database id; Bonfire's ids are ULID strings, and clients only send it back"}
  ]

  # Entities nested in an entity whose client-required fields are checked too: {field, entity}
  @client_nested %{
    "Status" => [{"account", "Account"}, {"reblog", "Status"}]
  }

  @doc """
  Flunks unless `json` (a decoded response entity) matches the `entity` schema of the Mastodon spec and has no null client-required fields. Returns `json`, so it can sit in a pipeline.
  """
  def assert_masto_entity(json, entity) when is_binary(entity) do
    flunk_on_problems(json, entity_problems(json, entity, ""), "Not a valid Mastodon #{entity}")
  end

  @doc """
  Flunks unless `json` (a decoded response body) matches the 200 response schema the Mastodon spec gives for `method` and `route` (a Phoenix route template, eg. `"/api/v1/statuses/:id"`, matched against the spec's paths whatever its parameters are named). A list response has each item checked. Returns `json`, or `:no_schema` when the spec has no such route, or no 200 JSON schema for it, or one that isn't an entity or a list of entities.
  """
  def assert_masto_response(json, method, route) do
    {_root, _keys, responses} = built()

    case Map.get(responses, response_key(method, route, ":")) do
      nil ->
        :no_schema

      {:entity, entity} ->
        assert_masto_entity(json, entity)

      {:list, entity} when is_list(json) ->
        problems =
          json
          |> Enum.with_index()
          |> Enum.flat_map(fn {item, index} -> entity_problems(item, entity, "#{index}.") end)

        flunk_on_problems(json, problems, "Not a valid list of Mastodon #{entity}")

      {:list, entity} ->
        flunk("Expected a list of Mastodon #{entity}, got: " <> inspect(json, pretty: true))
    end
  end

  defp entity_problems(json, entity, prefix) do
    schema_problems =
      case validate_masto_schema(json, entity) do
        {:ok, _} -> []
        {:error, error} -> format_schema_errors(error, prefix)
      end

    schema_problems ++ client_null_problems(json, entity, prefix)
  end

  defp flunk_on_problems(json, [], _title), do: json

  defp flunk_on_problems(json, problems, title) do
    flunk(
      "#{title}:\n" <>
        Enum.map_join(problems, "\n", &("  - " <> &1)) <>
        "\n\nin: " <> inspect(json, pretty: true, limit: :infinity)
    )
  end

  @doc """
  Validates `json` against the `entity` schema of the Mastodon spec only (no client checks). Returns `{:ok, casted}` or `{:error, %JSV.ValidationError{}}`.
  """
  def validate_masto_schema(json, entity) when is_binary(entity) do
    {root, keys, _responses} = built()

    case Map.fetch(keys, entity) do
      {:ok, key} -> JSV.validate(json, root, key: key)
      :error -> raise ArgumentError, "No #{inspect(entity)} schema in #{@spec_file}"
    end
  end

  defp client_null_problems(json, entity, prefix) when is_map(json) do
    nulls =
      @client_required
      |> Map.get(entity, [])
      |> Enum.filter(&is_nil(json[&1]))
      |> Enum.map(&"#{prefix}#{&1} is null or missing (clients need it)")

    nested =
      @client_nested
      |> Map.get(entity, [])
      |> Enum.flat_map(fn {field, nested_entity} ->
        client_null_problems(json[field], nested_entity, "#{prefix}#{field}.")
      end)

    nulls ++ nested
  end

  defp client_null_problems(_not_a_map, _entity, _prefix), do: []

  # `prefix` is "" for a whole response, or "<index>." for an item of a list response, so its errors read `#/<index>/...`
  defp format_schema_errors(error, prefix) do
    location = if prefix == "", do: "#", else: "#/" <> String.trim_trailing(prefix, ".")

    error
    |> JSV.normalize_error(min_error_level: JSV.ErrorFormatter.level_cause())
    |> Map.get(:details, [])
    |> format_error_units(location, "")
    |> Enum.uniq()
  end

  # an error can carry the units that caused it (eg. why each `oneOf` branch failed), so those are listed under it
  defp format_error_units(units, location, indent) do
    Enum.flat_map(units, fn unit ->
      Enum.flat_map(unit[:errors] || [], fn error ->
        [
          "#{indent}#{location}#{String.trim_leading(unit.instanceLocation, "#")}: #{error.message}"
        ] ++
          format_error_units(error[:details] || [], location, indent <> "    ")
      end)
    end)
  end

  # A route template and a spec path give the same key whatever their parameters are named: `/api/v1/accounts/:account_id` and `/api/v1/accounts/{id}` both give `{"GET", ["api", "v1", "accounts", "*"]}`
  defp response_key(method, path, param_start) do
    segments =
      path
      |> String.split("/", trim: true)
      |> Enum.map(&if(String.starts_with?(&1, param_start), do: "*", else: &1))

    {String.upcase(to_string(method)), segments}
  end

  # What the spec's 200 JSON response for each operation is: `{:entity, name}` or `{:list, name}` for a `$ref` to a component schema, or to a list of them. Anything else (3 inline schemas) is left out, so it isn't checked
  defp response_schemas(spec) do
    for {path, operations} <- spec["paths"],
        {method, operation} <- operations,
        method in ~w(get post put patch delete),
        schema = get_in(operation, ["responses", "200", "content", "application/json", "schema"]),
        response = response_schema(schema),
        into: %{} do
      {response_key(method, path, "{"), response}
    end
  end

  defp response_schema(%{"$ref" => "#/components/schemas/" <> entity}), do: {:entity, entity}

  defp response_schema(%{
         "type" => "array",
         "items" => %{"$ref" => "#/components/schemas/" <> entity}
       }),
       do: {:list, entity}

  defp response_schema(_), do: nil

  # raises if a corrected path isn't in the spec any more, so a refreshed spec doesn't silently drop a correction
  defp correct_spec(spec) do
    Enum.reduce(@spec_corrections, spec, fn {path, value, _why}, spec ->
      if get_in(spec, path) == nil,
        do: raise("Spec correction no longer applies, #{inspect(path)} isn't in #{@spec_file}")

      put_in(spec, path, value)
    end)
  end

  # The spec is built once per VM: 142 schemas, which takes a moment
  defp built do
    case :persistent_term.get({__MODULE__, :built}, nil) do
      nil ->
        built = build()
        :persistent_term.put({__MODULE__, :built}, built)
        built

      built ->
        built
    end
  end

  defp build do
    spec =
      :bonfire_api_graphql
      |> :code.priv_dir()
      |> Path.join(@spec_file)
      |> File.read!()
      |> Jason.decode!()
      |> correct_spec()

    ctx =
      JSV.build_init!(
        formats: [
          Bonfire.API.MastoCompat.Test.MastoFormats | JSV.default_format_validator_modules()
        ]
      )

    {_root_key, _normal_schema, ctx} = JSV.build_add!(ctx, spec)

    {keys, ctx} =
      spec
      |> Map.fetch!("components")
      |> Map.fetch!("schemas")
      |> Map.keys()
      |> Enum.map_reduce(ctx, fn name, ctx ->
        {key, ctx} =
          JSV.build_key!(ctx, JSV.Ref.parse!("#/components/schemas/#{name}", :root))

        {{name, key}, ctx}
      end)

    {JSV.to_root!(ctx, :root), Map.new(keys), response_schemas(spec)}
  end
end
