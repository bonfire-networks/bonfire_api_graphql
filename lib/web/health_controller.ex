if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompatible.HealthController do
    @moduledoc "Health check endpoints for Kubernetes-style liveness and readiness probes"

    use Bonfire.UI.Common.Web, :controller

    @doc "Liveness probe - returns 200 if the app is running"
    def livez(conn, _params) do
      send_resp(conn, 200, "")
    end

    @doc "Readiness probe - returns 200 if the app is ready to serve requests"
    def readyz(conn, _params) do
      # Could add database connectivity check here if needed
      send_resp(conn, 200, "")
    end
  end
end
