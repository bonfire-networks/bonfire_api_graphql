# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.CoverageTest do
  @moduledoc """
  Comprehensive Mastodon API coverage test.

  This test iterates through all endpoints defined in the GoToSocial OpenAPI spec
  and reports which ones are implemented in Bonfire.

  Run with: just test extensions/bonfire_api_graphql/test/rest/masto_api/coverage_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false

  import Bonfire.API.MastoApiCase.Helpers

  @moduletag :masto_api_coverage

  setup do
    account = Bonfire.Me.Fake.fake_account!()
    user = Bonfire.Me.Fake.fake_user!(account)
    {:ok, user: user, account: account}
  end

  describe "Mastodon API Coverage Report" do
    @tag timeout: :infinity
    test "check all endpoints from GoToSocial spec", %{conn: conn, user: user, account: account} do
      endpoints = ApiSpec.all_endpoints()

      IO.puts("\n")
      IO.puts(String.duplicate("=", 70))
      IO.puts("  MASTODON API COVERAGE TEST")
      IO.puts("  Testing #{length(endpoints)} endpoints from GoToSocial OpenAPI spec")
      IO.puts(String.duplicate("=", 70))
      IO.puts("")

      results =
        Enum.map(endpoints, fn endpoint ->
          result = test_single_endpoint(conn, endpoint, user, account)

          indicator =
            case result.status do
              :implemented -> "."
              :not_found -> "x"
              :error -> "E"
              _ -> "?"
            end

          IO.write(indicator)

          result
        end)

      IO.puts("\n")

      grouped = Enum.group_by(results, & &1.status)
      implemented = Map.get(grouped, :implemented, [])
      not_found = Map.get(grouped, :not_found, [])
      errored = Map.get(grouped, :error, [])
      unknown = Map.get(grouped, :unknown, [])

      IO.puts(String.duplicate("=", 70))
      IO.puts("  COVERAGE SUMMARY")
      IO.puts(String.duplicate("=", 70))
      IO.puts("")
      IO.puts("  Total endpoints:     #{length(endpoints)}")

      IO.puts(
        "  Implemented:         #{length(implemented)} (#{percentage(implemented, endpoints)}%)"
      )

      IO.puts(
        "  Not found (404):     #{length(not_found)} (#{percentage(not_found, endpoints)}%)"
      )

      IO.puts("  Errors:              #{length(errored)}")
      IO.puts("  Unknown:             #{length(unknown)}")
      IO.puts("")

      if length(implemented) > 0 do
        IO.puts(String.duplicate("-", 70))
        IO.puts("  IMPLEMENTED ENDPOINTS")
        IO.puts(String.duplicate("-", 70))

        implemented
        |> Enum.sort_by(& &1.path)
        |> Enum.each(fn e ->
          IO.puts("  [#{e.http_status}] #{pad_method(e.method)} #{e.path}")
        end)

        IO.puts("")
      end

      if length(not_found) > 0 do
        IO.puts(String.duplicate("-", 70))
        IO.puts("  NOT IMPLEMENTED (404)")
        IO.puts(String.duplicate("-", 70))

        not_found
        |> Enum.group_by(fn e -> List.first(e.tags) || "other" end)
        |> Enum.sort_by(fn {tag, _} -> tag end)
        |> Enum.each(fn {tag, endpoints} ->
          IO.puts("\n  [#{tag}]")

          Enum.each(endpoints, fn e ->
            summary = if e.summary, do: " - #{truncate(e.summary, 40)}", else: ""
            IO.puts("    #{pad_method(e.method)} #{e.path}#{summary}")
          end)
        end)

        IO.puts("")
      end

      if length(errored) > 0 do
        IO.puts(String.duplicate("-", 70))
        IO.puts("  ERRORS (5xx)")
        IO.puts(String.duplicate("-", 70))

        Enum.each(errored, fn e ->
          IO.puts("  [#{e.http_status}] #{pad_method(e.method)} #{e.path}")

          if e.error_message do
            IO.puts("         #{truncate(e.error_message, 60)}")
          end
        end)

        IO.puts("")
      end

      IO.puts(String.duplicate("=", 70))

      report = %{
        generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        total: length(endpoints),
        implemented: length(implemented),
        not_found: length(not_found),
        errors: length(errored),
        coverage_percent: percentage(implemented, endpoints),
        endpoints: results
      }

      json_path = Path.join(File.cwd!(), "masto_api_coverage.json")
      File.write!(json_path, Jason.encode!(report, pretty: true))
      IO.puts("  Report saved to: #{json_path}")
      IO.puts(String.duplicate("=", 70))

      # Test passes - this is a coverage report, not a pass/fail test
      assert true
    end
  end

  defp test_single_endpoint(conn, endpoint, user, account) do
    test_path = substitute_path_params(endpoint.path, user)
    api_conn = masto_api_conn(conn, user: user, account: account)

    task =
      Task.async(fn ->
        try do
          http_conn =
            case endpoint.method do
              "GET" -> get(api_conn, test_path)
              "POST" -> post(api_conn, test_path, "{}")
              "PUT" -> put(api_conn, test_path, "{}")
              "PATCH" -> patch(api_conn, test_path, "{}")
              "DELETE" -> delete(api_conn, test_path)
            end

          %{
            path: endpoint.path,
            method: endpoint.method,
            operation_id: endpoint.operation_id,
            summary: endpoint.summary,
            tags: endpoint.tags,
            status: categorize_response(http_conn),
            http_status: http_conn.status,
            error_message: nil
          }
        rescue
          e ->
            %{
              path: endpoint.path,
              method: endpoint.method,
              operation_id: endpoint.operation_id,
              summary: endpoint.summary,
              tags: endpoint.tags,
              status: :error,
              http_status: nil,
              error_message: Exception.message(e)
            }
        end
      end)

    case Task.yield(task, 5000) || Task.shutdown(task) do
      {:ok, result} ->
        result

      nil ->
        %{
          path: endpoint.path,
          method: endpoint.method,
          operation_id: endpoint.operation_id,
          summary: endpoint.summary,
          tags: endpoint.tags,
          status: :error,
          http_status: nil,
          error_message: "timeout"
        }
    end
  end

  defp percentage(subset, total) when is_list(subset) and is_list(total) do
    if length(total) == 0 do
      0
    else
      Float.round(length(subset) / length(total) * 100, 1)
    end
  end

  defp pad_method(method) do
    String.pad_trailing(method, 7)
  end

  defp truncate(string, max_length) when is_binary(string) do
    if String.length(string) > max_length do
      String.slice(string, 0, max_length - 3) <> "..."
    else
      string
    end
  end

  defp truncate(nil, _max_length), do: ""
end
