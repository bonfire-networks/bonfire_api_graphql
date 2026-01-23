if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.Social.Events.MastoEventsController do
    @moduledoc "Mastodon-compatible events REST endpoints."

    # TODO: move to extension

    use Bonfire.UI.Common.Web, :controller
    import Untangle

    alias Bonfire.Social.Events.API.GraphQLMasto.EventsAdapter

    @doc """
    GET /api/bonfire-v1/timelines/events

    Returns event feed with optional filters:
    - limit: number of events to return
    - location_id: filter by location
    - max_id, min_id, since_id: pagination
    """
    def events_timeline(conn, params) do
      debug(params, "GET /api/bonfire-v1/timelines/events")
      # feed_by_name returns conn with response already sent
      EventsAdapter.list_events(params, conn)
    end

    @doc """
    GET /api/bonfire-v1/accounts/:id/events

    Returns events created by a specific user.
    """
    def user_events(conn, %{"id" => user_id} = params) do
      debug({user_id, params}, "GET /api/bonfire-v1/accounts/:id/events")
      # feed_by_name returns conn with response already sent
      EventsAdapter.list_user_events(user_id, params, conn)
    end

    @doc """
    GET /api/bonfire-v1/events/:id

    Returns event details as Mastodon Status with Event attachment.
    """
    def show(conn, %{"id" => id}) do
      debug(id, "GET /api/bonfire-v1/events/:id")

      case EventsAdapter.get_event(id, conn) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{"error" => "Event not found"})

        event ->
          json(conn, event)
      end
    end
  end
end
