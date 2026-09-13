defmodule Bonfire.API.MastoCompat.Mappers.NotificationGroups do
  @moduledoc "Serializes grouped notification metadata and canonical REST entities."

  @doc """
  Builds the grouped response with deduplicated account and status references.

      iex> Bonfire.API.MastoCompat.Mappers.NotificationGroups.from_groups([])
      %{"accounts" => [], "statuses" => [], "notification_groups" => []}
  """
  def from_groups(groups) do
    notifications = Enum.flat_map(groups, fn {_group, items} -> items end)
    %{
      "accounts" => notifications |> Enum.map(& &1["account"]) |> Enum.uniq_by(& &1["id"]),
      "statuses" => notifications |> Enum.map(& &1["status"]) |> Enum.reject(&is_nil/1) |> Enum.uniq_by(& &1["id"]),
      "notification_groups" => Enum.map(groups, &from_group/1)
    }
  end

  defp from_group({group, [latest | _] = items}) do
    %{
      "group_key" => group["key"],
      "notifications_count" => group["count"],
      "type" => latest["type"],
      "most_recent_notification_id" => group["latest_id"],
      "page_max_id" => group["latest_id"],
      "page_min_id" => group["latest_id"],
      "latest_page_notification_at" => latest["created_at"],
      "sample_account_ids" => items |> Enum.map(& &1["account"]["id"]) |> Enum.uniq()
    }
    |> then(fn mapped -> if latest["status"], do: Map.put(mapped, "status_id", latest["status"]["id"]), else: mapped end)
  end
end
