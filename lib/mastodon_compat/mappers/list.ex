if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.List do
    @moduledoc """
    Transforms Bonfire Circles to Mastodon List format.

    In Bonfire, Circles are used to group users for access control and
    content organization. This module maps them to the Mastodon List API format.

    Handles both:
    - Direct Ecto struct format (atom keys, nested :named mixin)
    - GraphQL response format (string keys, flat structure)
    """

    alias Bonfire.API.MastoCompat.Helpers
    alias Bonfire.API.MastoCompat.Schemas
    import Helpers, only: [get_field: 2, to_string_safe: 1]
    import Untangle

    @doc """
    Converts a Bonfire Circle to a Mastodon List format.

    Returns `nil` if the input is nil, invalid, or fails validation.

    Supports both Ecto struct format and GraphQL response format:

    ## Examples

        # Ecto struct format
        iex> from_circle(%{id: "123", named: %{name: "Friends"}})
        %{"id" => "123", "title" => "Friends"}

        # GraphQL response format
        iex> from_circle(%{"id" => "123", "name" => "Friends"})
        %{"id" => "123", "title" => "Friends"}

        iex> from_circle(nil)
        nil
    """
    def from_circle(nil), do: nil

    def from_circle(circle) when is_map(circle) do
      id = get_id(circle)

      if is_nil(id) do
        warn(circle, "Circle missing id")
        nil
      else
        %{
          "id" => to_string(id),
          "title" => get_circle_name(circle)
        }
        |> Schemas.List.new()
        |> validate_and_return()
      end
    end

    def from_circle(_), do: nil

    # Get ID from either atom or string key
    defp get_id(%{id: id}) when not is_nil(id), do: id
    defp get_id(%{"id" => id}) when not is_nil(id), do: id
    defp get_id(circle), do: get_field(circle, :id) |> to_string_safe()

    # Get name from multiple possible formats:
    # 1. GraphQL response with atom key: %{name: "Friends"}
    # 2. Ecto struct with named mixin: %{named: %{name: "Friends"}}
    # 3. Direct name field: %{name: "Friends"}
    defp get_circle_name(circle) do
      # Try direct :name field first (GraphQL response uses atom keys)
      case get_field(circle, :name) do
        name when is_binary(name) and name != "" ->
          name

        _ ->
          # Try Ecto struct format (nested in :named mixin)
          case get_field(circle, :named) do
            %{name: name} when is_binary(name) ->
              name

            _ ->
              ""
          end
      end
    end

    defp validate_and_return(list) do
      case Schemas.List.validate(list) do
        {:ok, valid} ->
          valid

        {:error, reason} ->
          warn(reason, "List validation failed")
          nil
      end
    end
  end
end
