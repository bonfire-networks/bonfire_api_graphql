defmodule Bonfire.API.MastoCompatible.InstanceController do
  use Bonfire.UI.Common.Web, :controller
  use Bonfire.Common.Config

  alias Bonfire.API.MastoCompatible.InstanceAdapter


  def instance(conn, _) do
    data = Bonfire.Common.URIs.base_uri(conn)
    |> InstanceAdapter.show()

    json(
      conn,
      data)
    )
  end

  def instance_v2(conn, _) do
    data = (Bonfire.Common.URIs.base_uri(conn))
    |> InstanceAdapter.show_v2()

    json(
      conn,
      data)
    )
  end

  @doc """
  Returns custom emojis available on this instance.
  GET /api/v1/custom_emojis
  """
  def custom_emojis(conn, _params) do
    json(conn, InstanceAdapter.custom_emojis())
  end
end
