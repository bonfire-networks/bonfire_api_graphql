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

  def return(name, ret, conn, transform_fun \\ nil) do
    case ret do
      {:error, e} ->
        # Handle error tuples directly (e.g., from unauthorized requests)
        error(e)

      %{data: data, errors: errors} ->
        # Check if we actually have data after extraction
        extracted_data = ret_data(data, name)

        if extracted_data do
          # Partial data with errors - log errors but return data
          warn(errors, "partial_graphql_errors")
          {:ok, transform_data(extracted_data, transform_fun)}
        else
          # No data, only errors - treat as full error
          error(errors)
        end

      %{data: data} ->
        {:ok, ret_data(data, name) |> transform_data(transform_fun)}

      %{errors: errors} ->
        error(errors)

      other ->
        error(other, "unexpected_graphql_response")
    end
    |> transform_response(conn)
  end

  defp ret_data(data, name) do
    if data do
      # AbsintheClient in :internal mode returns atom keys with snake_case
      # If the map has only one key and matches our expected name, extract it
      # Otherwise return the whole data map
      case Map.get(data, name) do
        nil when map_size(data) == 1 ->
          # Single key in map, return its value
          data |> Map.values() |> List.first()

        nil ->
          # Multiple keys but name not found, return whole map
          data

        value ->
          # Found the expected key, return its value
          value
      end
    else
      data
    end
  end

  defp transform_response({:ok, response}, conn), do: success_fn(response, conn)
  defp transform_response({:error, response}, conn), do: error_fn(response, conn)

  def success_fn(response, conn) do
    # Plug.Conn.send_resp(conn, 200, Jason.encode!(transform_data(response)))
    Phoenix.Controller.json(conn, response)
  end

  def error_fn(response, conn) do
    # error transformation logic
    {status, error_response} =
      case response do
        {:error, :unauthorized} ->
          {401, %{"error" => "Unauthorized"}}

        {:error, :not_found} ->
          {404, %{"error" => "Not found"}}

        {:error, reason} when is_binary(reason) ->
          {400, %{"error" => reason}}

        {:error, reason} when is_atom(reason) ->
          {400, %{"error" => Atom.to_string(reason)}}

        # Handle GraphQL error lists
        [%{code: code} | _] = errors when is_list(errors) ->
          status =
            case code do
              :unauthorized -> 401
              :not_found -> 404
              _ -> 400
            end

          first_error = List.first(errors)
          base_error = %{"error" => first_error[:message] || "GraphQL error"}
          # Only include details in dev/test environments for security
          error_with_details =
            if Mix.env() in [:dev, :test] do
              Map.put(base_error, "details", transform_data(errors))
            else
              base_error
            end

          {status, error_with_details}

        other ->
          base_error = %{"error" => "Internal server error"}
          # Only include details in dev/test environments for security
          error_with_details =
            if Mix.env() in [:dev, :test] do
              Map.put(base_error, "details", transform_data(other))
            else
              base_error
            end

          {500, error_with_details}
      end

    Plug.Conn.send_resp(conn, status, Jason.encode!(error_response))
  end

  def transform_data(data, transform_fun) when is_function(transform_fun, 1) do
    transform_fun.(data)
    |> transform_data()
  end

  def transform_data(data, _), do: transform_data(data)

  def transform_data(data) when is_binary(data), do: data
  def transform_data(%{} = data), do: Enums.struct_to_map(data, true)
  def transform_data(data) when is_list(data), do: Enum.map(data, &transform_data/1)
  def transform_data(data), do: inspect(data)
end
