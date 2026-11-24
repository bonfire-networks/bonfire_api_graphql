if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Schemas.Report do
    @moduledoc "Mastodon Report entity schema definition."

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
  end
end
