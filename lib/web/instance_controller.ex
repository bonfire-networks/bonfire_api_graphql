defmodule Bonfire.API.MastoCompatible.InstanceController do
  use Bonfire.UI.Common.Web, :controller
  use Bonfire.Common.Config
  # TODO: move to extension

  alias Bonfire.API.MastoCompatible.InstanceAdapter

  def show(conn, _) do
    data =
      Bonfire.Common.URIs.base_uri(conn)
      |> InstanceAdapter.show()

    json(conn, data)
  end

  def show_v2(conn, _) do
    data =
      Bonfire.Common.URIs.base_uri(conn)
      |> InstanceAdapter.show_v2()

    json(conn, data)
  end

  @doc """
  Returns custom emojis available on this instance.
  GET /api/v1/custom_emojis
  """
  def custom_emojis(conn, _params) do
    json(conn, InstanceAdapter.custom_emojis())
  end

  @doc """
  Returns available CSS themes for the web UI.
  GET /api/v1/accounts/themes

  Bonfire uses Tailwind/DaisyUI with dynamic theming, so we return an empty array
  since client apps don't need this for their own styling.
  """
  def themes(conn, _params) do
    json(conn, [])
  end

  @peers_query "query { peers: knownInstances }"

  @doc "GET /api/v1/instance/peers: the known instances' domains, read through GraphQL (masto-live-fixes decision 10)."
  def peers(conn, _params) do
    case Bonfire.API.MastoCompat.Helpers.run_query(@peers_query, conn.assigns[:current_user]) do
      {:ok, %{data: %{peers: peers}}} when is_list(peers) -> json(conn, peers)
      other -> Bonfire.API.GraphQL.RestAdapter.error_fn(other, conn)
    end
  end

  @doc "GET /api/v2/filters: Bonfire has no filters yet; an empty list lets Phanpy and Elk start (masto-live-fixes decision 11)."
  def filters(conn, _params), do: json(conn, [])

  @doc "GET /api/v1/announcements: Bonfire has no announcements yet; an empty list lets Phanpy and Elk start (masto-live-fixes decision 11)."
  def announcements(conn, _params), do: json(conn, [])
end
