if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Report do
    @moduledoc """
    Mastodon Report entity schema definition.

    Based on https://docs.joinmastodon.org/entities/Report/
    This module provides a single source of truth for Report field structure and defaults.
    """

    @doc """
    Returns a new Report map with default values.
    Can optionally merge custom values via the overrides parameter.

    ## Examples

        iex> Report.new(%{"id" => "123", "comment" => "spam"})
        %{"id" => "123", "comment" => "spam", "category" => "other", ...}
    """
    def new(overrides \\ %{}) do
      defaults()
      |> Map.merge(overrides)
    end

    def defaults do
      %{
        "id" => nil,
        "created_at" => nil,
        "action_taken" => false,
        "action_taken_at" => nil,
        "category" => "other",
        "comment" => "",
        "forwarded" => false,
        "status_ids" => nil,
        "rule_ids" => nil,
        "target_account" => nil
      }
    end

    def required_fields do
      ["id", "action_taken", "category", "comment", "forwarded", "created_at", "target_account"]
    end

    @doc """
    Validates that all required fields are present and non-nil.
    Returns {:ok, report} or {:error, missing_fields}.
    """
    def validate(report) when is_map(report) do
      missing =
        required_fields()
        |> Enum.filter(fn field -> is_nil(Map.get(report, field)) end)

      if missing == [] do
        {:ok, report}
      else
        {:error, {:missing_fields, missing}}
      end
    end

    def validate(_), do: {:error, :invalid_report}
  end
end
