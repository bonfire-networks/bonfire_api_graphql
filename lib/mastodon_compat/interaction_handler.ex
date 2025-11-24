if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.InteractionHandler do
    @moduledoc """
    Handles user interactions with statuses (like/unlike/boost/unboost).

    This module consolidates the common pattern for interaction mutations:
    1. Check authorization
    2. Perform the interaction via Bonfire context
    3. Fetch the updated activity with proper preloads
    4. Transform to Mastodon Status format
    5. Set the appropriate interaction flag

    Previously, this pattern was duplicated across 4 functions (~178 lines).
    Now it's a single reusable function.

    ## Usage

        # Like a status
        InteractionHandler.handle_interaction(
          conn,
          id,
          interaction_type: :like,
          context_fn: &Bonfire.Social.Likes.like/2,
          flag: "favourited",
          flag_value: true
        )

        # Boost a status
        InteractionHandler.handle_interaction(
          conn,
          id,
          interaction_type: :boost,
          context_fn: &Bonfire.Social.Boosts.boost/2,
          flag: "reblogged",
          flag_value: true
        )
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.Mappers
    alias Bonfire.Social.API.Adapter.REST, as: RestAdapter

    @doc """
    Common handler for all status interactions.

    ## Options

    - `:interaction_type` - Type of interaction (for logging): :like, :unlike, :boost, :unboost
    - `:context_fn` - The Bonfire context function to call (e.g., &Bonfire.Social.Likes.like/2)
    - `:flag` - The Mastodon status flag to set: "favourited" or "reblogged"
    - `:flag_value` - Value to set for the flag: true or false

    ## Examples

        iex> handle_interaction(conn, "123",
        ...>   interaction_type: :like,
        ...>   context_fn: &Bonfire.Social.Likes.like/2,
        ...>   flag: "favourited",
        ...>   flag_value: true
        ...> )
        %Plug.Conn{...}
    """
    def handle_interaction(conn, id, opts) do
      interaction_type = Keyword.fetch!(opts, :interaction_type)
      context_fn = Keyword.fetch!(opts, :context_fn)
      flag = Keyword.fetch!(opts, :flag)
      flag_value = Keyword.fetch!(opts, :flag_value)

      current_user = conn.assigns[:current_user]

      if current_user do
        perform_interaction(
          conn,
          current_user,
          id,
          interaction_type,
          context_fn,
          flag,
          flag_value
        )
      else
        RestAdapter.error_fn({:error, :unauthorized}, conn)
      end
    end

    # Private functions

    defp perform_interaction(
           conn,
           current_user,
           id,
           interaction_type,
           context_fn,
           flag,
           flag_value
         ) do
      case context_fn.(current_user, id) do
        {:ok, _result} ->
          debug(id, "#{interaction_type} completed successfully")
          fetch_and_respond(conn, current_user, id, interaction_type, flag, flag_value)

        {:error, reason} ->
          error(reason, "#{interaction_type} error")
          RestAdapter.error_fn({:error, reason}, conn)
      end
    end

    defp fetch_and_respond(conn, current_user, id, interaction_type, flag, flag_value) do
      opts = [
        current_user: current_user,
        preload: [
          :with_subject,
          :with_creator,
          :with_media,
          :with_object_more,
          :with_object_peered,
          :with_reply_to
        ]
      ]

      case Bonfire.Social.Activities.read([id: id], opts) do
        {:ok, activity} ->
          prepared =
            activity
            |> Mappers.Status.from_activity(current_user: current_user)
            |> Map.put(flag, flag_value)
            |> deep_struct_to_map()

          Phoenix.Controller.json(conn, prepared)

        {:error, reason} ->
          error(reason, "Failed to fetch activity after #{interaction_type}")
          RestAdapter.error_fn({:error, reason}, conn)
      end
    end

    # Helper to recursively convert all structs to JSON-safe maps
    # This ensures no Ecto structs leak through to Jason.encode!
    defp deep_struct_to_map(data) when is_struct(data) do
      data
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> deep_struct_to_map()
    end

    defp deep_struct_to_map(data) when is_map(data) do
      data
      |> Enum.map(fn {k, v} -> {k, deep_struct_to_map(v)} end)
      |> Map.new()
    end

    defp deep_struct_to_map(data) when is_list(data) do
      Enum.map(data, &deep_struct_to_map/1)
    end

    defp deep_struct_to_map(data), do: data

    @doc """
    Helper to get preload options for activity fetching.
    Exposed for testing and consistency.
    """
    def activity_preload_opts do
      [
        preload: [
          :with_subject,
          :with_creator,
          :with_media,
          :with_object_more,
          :with_object_peered,
          :with_reply_to
        ]
      ]
    end
  end
end
