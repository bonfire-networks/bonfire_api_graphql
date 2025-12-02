# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoCompat.ApiSpec do
  @moduledoc """
  Loads and provides access to the GoToSocial/Mastodon OpenAPI specification
  for testing Mastodon API compatibility.

  Note: This module uses runtime checks instead of compile-time struct pattern
  matching because OpenApiSpex is only available in the test environment.
  """

  @spec_path Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/gotosocial-swagger.json")

  @doc """
  Load the OpenAPI spec from the JSON file.
  Returns the raw parsed JSON as a map (Swagger 2.0 format).
  """
  def spec do
    @spec_path
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Cached version of the spec for performance in tests.
  Uses persistent_term to store the parsed spec.
  """
  def cached_spec do
    case :persistent_term.get({__MODULE__, :spec}, nil) do
      nil ->
        spec = spec()
        :persistent_term.put({__MODULE__, :spec}, spec)
        spec

      cached ->
        cached
    end
  end

  @doc """
  Extract all API endpoints from the spec for coverage analysis.
  Returns a list of maps with path, method, operation_id, and summary.
  """
  def all_endpoints do
    spec = cached_spec()
    paths = get_paths(spec)

    paths
    |> Enum.flat_map(fn {path, path_item} ->
      path_item
      |> Enum.filter(fn {method, _} ->
        method in ["get", "post", "put", "patch", "delete"]
      end)
      |> Enum.map(fn {method, operation} ->
        %{
          path: path,
          method: String.upcase(method),
          operation_id: get_operation_id(operation),
          summary: get_summary(operation),
          tags: get_tags(operation)
        }
      end)
    end)
    |> Enum.sort_by(& &1.path)
  end

  @doc """
  Get endpoints grouped by tag/category.
  """
  def endpoints_by_tag do
    all_endpoints()
    |> Enum.group_by(fn endpoint ->
      case endpoint.tags do
        [tag | _] -> tag
        _ -> "untagged"
      end
    end)
  end

  # Handle Swagger 2.0 format (what GoToSocial uses)
  defp get_paths(%{"paths" => paths}) when is_map(paths), do: Map.to_list(paths)

  defp get_paths(spec) when is_map(spec) do
    case Map.get(spec, "paths") do
      nil -> []
      paths -> Map.to_list(paths)
    end
  end

  defp get_operation_id(%{"operationId" => id}), do: id
  defp get_operation_id(_), do: nil

  defp get_summary(%{"summary" => s}), do: s
  defp get_summary(_), do: nil

  defp get_tags(%{"tags" => tags}) when is_list(tags), do: tags
  defp get_tags(_), do: []
end
