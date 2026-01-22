defmodule Bonfire.API.GraphQL.RestAdapter do
  use Untangle
  alias Bonfire.Common.Config
  alias Bonfire.API.MastoCompat.Helpers

  @doc """
  Process a GraphQL response and transform it to JSON.

  Takes the GraphQL result, extracts data by name, applies optional transformation,
  and returns JSON response via conn.
  """
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

  @doc """
  Helper to require authentication and execute a function with the current user.

  Returns 401 Unauthorized if no user is logged in.
  """
  def with_current_user(conn, fun) do
    case conn.assigns[:current_user] do
      nil -> error_fn({:error, :unauthorized}, conn)
      user -> fun.(user)
    end
  end

  def success_fn(response, conn) do
    Phoenix.Controller.json(conn, transform_data(response))
  end

  def json(conn, data) do
    Phoenix.Controller.json(conn, transform_data(data))
  end

  def error_fn(response, conn) do
    # error transformation logic
    {status, error_response} =
      case response do
        {:error, :unauthorized} ->
          {401, %{"error" => "Unauthorized"}}

        {:error, :forbidden} ->
          {403, %{"error" => "Forbidden"}}

        {:error, :not_found} ->
          {404, %{"error" => "Not found"}}

        {:error, :poll_expired} ->
          {422, %{"error" => "Validation failed: Poll has already ended"}}

        {:error, :already_voted} ->
          {422, %{"error" => "Validation failed: You have already voted on this poll"}}

        {:error, reason} when is_binary(reason) ->
          # Detect permission-related error strings and return 403 Forbidden
          if String.contains?(String.downcase(reason), "permission") do
            {403, %{"error" => "Forbidden"}}
          else
            {400, %{"error" => reason}}
          end

        {:error, reason} when is_atom(reason) ->
          {400, %{"error" => Atom.to_string(reason)}}

        # Handle Ecto Changeset errors (e.g., constraint violations, validation errors)
        {:error, %Ecto.Changeset{} = changeset} ->
          message = Bonfire.Common.Errors.error_msg(changeset)
          # Treat constraint errors as "not found" for non-existent references
          if String.contains?(message, "constraint") do
            {404, %{"error" => "Record not found"}}
          else
            {422, %{"error" => "Validation failed: #{message}"}}
          end

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
            if Config.env() in [:dev, :test] do
              Map.put(base_error, "details", transform_data(errors))
            else
              base_error
            end

          {status, error_with_details}

        other ->
          base_error = %{"error" => "Internal server error"}
          # Only include details in dev/test environments for security
          error_with_details =
            if Config.env() in [:dev, :test] do
              Map.put(base_error, "details", transform_data(other))
            else
              base_error
            end

          {500, error_with_details}
      end

    # Safely encode the error response, falling back to a simple error if encoding fails
    body =
      try do
        Jason.encode!(error_response)
      rescue
        _ -> Jason.encode!(%{"error" => "Internal server error"})
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  def transform_data(data, transform_fun) when is_function(transform_fun, 1) do
    transform_fun.(data)
    |> transform_data()
  end

  def transform_data(data, _), do: transform_data(data)

  def transform_data(data) when is_binary(data), do: data

  def transform_data(%{} = data) do
    Helpers.deep_struct_to_map(data, filter_nils: true)
  end

  def transform_data(data) when is_list(data), do: Enum.map(data, &transform_data/1)
  def transform_data(data), do: inspect(data)
end
