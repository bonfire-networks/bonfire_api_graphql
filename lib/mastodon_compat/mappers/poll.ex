if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Poll do
    @moduledoc "Pure translation of the shared GraphQL poll representation into Mastodon fields."
    alias Bonfire.API.MastoCompat.Schemas
    import Bonfire.API.MastoCompat.Helpers, only: [get_field: 2]

    @doc "Maps GraphQL results, including visibility-filtered totals and the viewer's choices."
    def from_question(question, opts \\ [])
    def from_question(nil, _opts), do: nil

    def from_question(question, _opts) when is_map(question) do
      choices = (get_field(question, :choices) || []) |> Enum.sort_by(&get_field(&1, :id))
      own_ids = (get_field(question, :own_votes) || []) |> Enum.map(&get_field(&1, :id))
      own_votes = choices |> Enum.with_index() |> Enum.filter(fn {choice, _} -> get_field(choice, :id) in own_ids end) |> Enum.map(&elem(&1, 1))
      expires_at = get_field(question, :voting_close_at)

      Schemas.Poll.new(%{
        "id" => get_field(question, :id),
        "expires_at" => expires_at,
        "expired" => poll_expired?(question),
        "multiple" => get_field(question, :voting_format) != "single",
        "votes_count" => get_field(question, :votes_count) || 0,
        "voters_count" => get_field(question, :voters_count) || 0,
        "voted" => get_field(question, :voted) || false,
        "own_votes" => own_votes,
        "options" => Enum.map(choices, fn choice ->
          content = get_field(choice, :post_content)
          %{"title" => get_field(content, :name) || get_field(content, :html_body) || "",
            "votes_count" => get_field(choice, :votes_result_total)}
        end),
        "emojis" => []
      })
    end

    @doc "Recognises native and GraphQL poll objects for status enrichment."
    def is_poll?(object), do: get_field(object, :__struct__) == Bonfire.Poll.Question or get_field(object, :__typename) == "Poll"

    @doc "Whether the GraphQL poll's closing time has been reached."
    def poll_expired?(question) do
      case get_field(question, :voting_close_at) do
        %DateTime{} = date -> DateTime.compare(DateTime.utc_now(), date) != :lt
        date when is_binary(date) ->
          case DateTime.from_iso8601(date) do
            {:ok, parsed, _} -> DateTime.compare(DateTime.utc_now(), parsed) != :lt
            _ -> false
          end
        _ -> false
      end
    end
  end
end
