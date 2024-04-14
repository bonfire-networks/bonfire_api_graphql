defmodule Bonfire.API.GraphQL.RestAdapter do
  use Untangle
  alias Bonfire.Common.Enums

  defmodule EndpointConfig do
    defstruct query: nil, success_fn: nil, error_fn: nil
  end

  def endpoint(query, success_fn \\ nil, error_fn \\ nil) do
    %EndpointConfig{
      query: query,
      success_fn: success_fn,
      error_fn: error_fn
    }
  end

  def return(name, ret, conn) do
    case ret do
      %{data: data, errors: errors} ->
        error(errors, "partial_graphql_errors")
        {:ok, ret_data(data, name)}

      %{data: data} ->
        {:ok, ret_data(data, name)}

      %{errors: errors} ->
        error(errors)

      other ->
        error(other)
    end
    |> transform_response(conn)
  end

  defp ret_data(data, name) do
    if data do
      if Enum.count(data) == 1 && Map.get(data, name) do
        Map.get(data, name)
      else
        data
      end
    end
  end

  defp transform_response(response, conn, transform_fun \\ nil)
  defp transform_response({:ok, response}, conn, _), do: success_fn(response, conn)
  defp transform_response({:error, response}, conn, _), do: error_fn(response, conn)

  def success_fn(response, conn) do
    # Plug.Conn.send_resp(conn, 200, Jason.encode!(transform_data(response)))
    Phoenix.Controller.json(conn, transform_data(response))
  end

  def error_fn(response, conn) do
    # error transformation logic 
    Plug.Conn.send_resp(conn, 500, Jason.encode!(transform_data(response)))
  end

  def transform_data(data) when is_binary(data), do: data
  def transform_data(%{} = data), do: Enums.maybe_to_map(data, true)
  def transform_data(data) when is_list(data), do: Enum.map(data, &transform_data/1)
  def transform_data(data), do: inspect(data)
end
