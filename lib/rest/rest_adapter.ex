defmodule Bonfire.API.GraphQL.RestAdapter do
  use Untangle
  alias Bonfire.Common.Config
  alias Bonfire.API.MastoCompat.Helpers

  @doc """
  Process a GraphQL response and transform it to JSON.

  Takes the GraphQL result, extracts data by name, applies optional transformation,
  and returns JSON response via conn.
  """
  def return(name, ret, conn, transform_fun \\ nil, opts \\ []) do
    result =
      case ret do
        {:error, e} ->
          error(e)

        %{data: data, errors: errors} ->
          extracted_data = ret_data(data, name)

          if extracted_data do
            warn(errors, "partial_graphql_errors")
            {:ok, transform_data(extracted_data, transform_fun, opts)}
          else
            error(errors)
          end

        %{data: data} ->
          {:ok, ret_data(data, name) |> transform_data(transform_fun, opts)}

        %{errors: errors} ->
          error(errors)

        other ->
          error(other, "unexpected_graphql_response")
      end

    case result do
      {:ok, response} -> success_fn(response, conn, opts)
      {:error, _} = err -> transform_response(err, conn)
    end
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

  def success_fn(response, conn, opts \\ []) do
    Phoenix.Controller.json(conn, transform_data(response, nil, opts))
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

        {:error, {:unprocessable_entity, message}} ->
          {422, %{"error" => "Validation failed: #{message}"}}

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

        # Handle wrapped GraphQL error lists (from adapter calls like error_fn({:error, errors}, conn))
        {:error, [_ | _] = errors} ->
          graphql_error_response(errors)

        # Handle direct GraphQL error lists (from transform_response path)
        [_ | _] = errors ->
          graphql_error_response(errors)

        {:error, %Bonfire.Fail{status: status, message: message}} ->
          {status, %{"error" => message}}

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

  defp graphql_error_response(errors) when is_list(errors) do
    first_error = List.first(errors) || %{}
    error_status = first_error[:status]
    code = first_error[:code]
    message = first_error[:message] || "Request failed"

    status =
      cond do
        code in [:unauthorized] -> 401
        code in [:not_found] -> 404
        code in [:forbidden, :not_permitted, :invite_only] -> 403
        is_integer(error_status) and error_status in 400..599 -> error_status
        true -> 400
      end

    # Override status based on message content when code is ambiguous
    status =
      cond do
        status in [400, 500] and is_binary(message) and
            String.contains?(String.downcase(message), [
              "cannot edit",
              "cannot update",
              "not permitted"
            ]) ->
          403

        status == 400 and is_binary(message) and
            String.contains?(String.downcase(message), ["log in", "logged in", "unauthorized"]) ->
          401

        true ->
          status
      end

    base_error = %{"error" => message}

    error_with_details =
      if Config.env() in [:dev, :test] do
        Map.put(base_error, "details", transform_data(errors))
      else
        base_error
      end

    {status, error_with_details}
  end

  def transform_data(data, transform_fun, opts \\ [])

  def transform_data(data, transform_fun, opts) when is_function(transform_fun, 1) do
    transform_fun.(data)
    |> transform_data(nil, opts)
  end

  def transform_data(data, _, opts) when is_binary(data) and is_list(opts), do: data

  def transform_data(%{} = data, _, opts) when is_list(opts) do
    filter_nils = Keyword.get(opts, :filter_nils, true)
    Helpers.deep_struct_to_map(data, filter_nils: filter_nils)
  end

  def transform_data(data, _, opts) when is_list(data) and is_list(opts),
    do: Enum.map(data, &transform_data(&1, nil, opts))

  def transform_data(data, _, _opts), do: inspect(data)

  def transform_data(data) when is_binary(data), do: data

  def transform_data(%{} = data) do
    Helpers.deep_struct_to_map(data, filter_nils: true)
  end

  def transform_data(data) when is_list(data), do: Enum.map(data, &transform_data/1)
  def transform_data(data), do: inspect(data)
end
