if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompatible.MarkersController do
    @moduledoc "Mastodon-compatible markers API for tracking timeline reading positions."

    use Bonfire.UI.Common.Web, :controller

    alias Bonfire.API.GraphQL.RestAdapter
    alias Bonfire.Social.Markers

    # Mastodon spec only supports these timelines
    @mastodon_timelines ["home", "notifications"]

    @doc "GET /api/v1/markers"
    def index(conn, params) do
      case conn.assigns[:current_user] do
        nil ->
          RestAdapter.error_fn({:error, :unauthorized}, conn)

        current_user ->
          timelines = requested_timelines(params)
          RestAdapter.json(conn, Markers.get(current_user, timelines))
      end
    end

    @doc "POST /api/v1/markers"
    def create(conn, params) do
      case conn.assigns[:current_user] do
        nil ->
          RestAdapter.error_fn({:error, :unauthorized}, conn)

        current_user ->
          result =
            @mastodon_timelines
            |> Enum.reduce(%{}, fn timeline, acc ->
              case params[timeline] do
                %{"last_read_id" => id} when is_binary(id) and id != "" ->
                  case Markers.save(current_user, timeline, id) do
                    {:ok, marker} -> Map.put(acc, timeline, marker)
                    _ -> acc
                  end

                _ ->
                  acc
              end
            end)

          RestAdapter.json(conn, result)
      end
    end

    defp requested_timelines(params) do
      case params["timeline[]"] || params["timeline"] do
        nil ->
          @mastodon_timelines

        list when is_list(list) ->
          Enum.filter(list, &(&1 in @mastodon_timelines))

        single when is_binary(single) ->
          if single in @mastodon_timelines, do: [single], else: []
      end
    end
  end
end
