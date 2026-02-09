if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.InteractionHandler do
    @moduledoc "Common handler for status interactions (like/unlike/boost/unboost/bookmark)."

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.{Mappers, Schemas, Helpers}
    alias Bonfire.API.GraphQL.RestAdapter

    @doc "Perform an interaction and return the updated status. Opts: :interaction_type, :context_fn, :flag, :flag_value."
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

    defp perform_interaction(
           conn,
           current_user,
           id,
           interaction_type,
           context_fn,
           flag,
           flag_value
         ) do
      try do
        case context_fn.(current_user, id) do
          {:ok, result} ->
            fetch_and_respond(conn, current_user, id, interaction_type, flag, flag_value, result)

          {:error, reason} ->
            error(reason, "#{interaction_type} error")
            RestAdapter.error_fn({:error, reason}, conn)
        end
      rescue
        e ->
          error(e, "#{interaction_type} error")
          RestAdapter.error_fn({:error, :not_found}, conn)
      end
    end

    defp fetch_and_respond(
           conn,
           current_user,
           id,
           interaction_type,
           flag,
           flag_value,
           interaction_result
         ) do
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

      case Bonfire.Social.Objects.read(id, opts) do
        {:ok, object} ->
          case Mappers.Status.from_post(object, current_user: current_user) do
            nil ->
              RestAdapter.error_fn({:error, :not_found}, conn)

            status ->
              prepared =
                if interaction_type in [:boost, :unboost] do
                  wrap_as_boost(status, current_user, interaction_result, flag_value)
                else
                  Map.put(status, flag, flag_value)
                end
                |> Helpers.deep_struct_to_map()

              Phoenix.Controller.json(conn, prepared)
          end

        {:error, reason} ->
          RestAdapter.error_fn({:error, reason}, conn)
      end
    end

    defp wrap_as_boost(original_status, current_user, boost_result, reblogged) do
      booster_account = Mappers.Account.from_user(current_user, skip_expensive_stats: true)
      boost_id = Helpers.get_field(boost_result, :id)

      Schemas.Status.new(%{
        "id" => boost_id || original_status["id"],
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "account" => booster_account,
        "content" => "",
        "reblog" => Map.put(original_status, "reblogged", reblogged),
        "reblogged" => reblogged
      })
    end
  end
end
