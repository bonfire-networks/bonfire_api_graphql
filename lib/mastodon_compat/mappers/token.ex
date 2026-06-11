if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Token do
    @moduledoc """
    Maps a Boruta OAuth access token (`Boruta.Ecto.Token`) to
    `tokenInfo` entity returned by `/api/v1/tokens`.
    """

    use Bonfire.Common.Utils

    @doc """
    Build a `tokenInfo` map from a Boruta token.

    The token's `:client` association is used for the nested `application` object
    when loaded; the client secret is never exposed here.
    """
    def from_oauth_token(nil), do: nil

    def from_oauth_token(token) when is_map(token) do
      %{
        "id" => token.id,
        "created_at" => iso8601(Map.get(token, :inserted_at)),
        # Boruta doesn't track a precise last-used time; updated_at is the closest proxy
        "last_used" => iso8601(Map.get(token, :updated_at)),
        "scope" => token.scope || "",
        "application" => application(Map.get(token, :client))
      }
    end

    defp application(%Ecto.Association.NotLoaded{}), do: nil
    defp application(nil), do: nil

    defp application(client) do
      # Intentionally omits client_secret — this is a read endpoint.
      %{
        "id" => client.id,
        "name" => Map.get(client, :name),
        "website" => nil,
        "redirect_uri" => client |> Map.get(:redirect_uris) |> List.wrap() |> List.first(),
        "redirect_uris" => Map.get(client, :redirect_uris) || [],
        "scopes" => client |> Map.get(:authorized_scopes) |> scope_names()
      }
    end

    defp scope_names(scopes) when is_list(scopes) do
      Enum.map(scopes, fn
        %{name: name} -> name
        %{"name" => name} -> name
        name when is_binary(name) -> name
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
    end

    defp scope_names(_), do: []

    defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

    defp iso8601(%NaiveDateTime{} = ndt),
      do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_iso8601()

    defp iso8601(_), do: nil
  end
end
