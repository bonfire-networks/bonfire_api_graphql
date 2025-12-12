if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Poll do
    @moduledoc """
    Maps Bonfire Poll.Question objects to Mastodon Poll format.

    Per the Mastodon API spec, a Poll represents a poll attached to a status.
    See: https://docs.joinmastodon.org/entities/Poll/

    ## Required Fields

    - `id` (string) - The poll's database ID
    - `options` (array) - Poll options with title and votes_count

    ## Optional Fields

    - `expires_at` (string, datetime) - When the poll ends
    - `expired` (boolean) - Whether the poll has ended
    - `multiple` (boolean) - Whether multiple choices are allowed
    - `votes_count` (integer) - Total votes across all options
    - `voters_count` (integer) - Unique voters count
    - `voted` (boolean) - Whether the current user has voted
    - `own_votes` (array of integers) - Indices of user's choices
    - `emojis` (array) - Custom emojis in options
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.{Schemas, Helpers}

    @doc """
    Transform a Bonfire Poll.Question to a Mastodon Poll.

    ## Options

    - `:current_user` - The current user (for voted/own_votes)
    - `:votes_count` - Pre-computed votes count (optional)
    - `:voters_count` - Pre-computed voters count (optional)
    - `:user_votes` - Pre-loaded user votes list (optional)
    """
    def from_question(question, opts \\ [])

    def from_question(nil, _opts), do: nil

    def from_question(question, opts) when is_map(question) do
      question_id = e(question, :id, nil)

      if question_id do
        current_user = Keyword.get(opts, :current_user)
        choices = get_ordered_choices(question)

        # Get user's votes if we have a current user
        {voted, own_votes} = get_user_vote_info(current_user, question, choices, opts)

        Schemas.Poll.new(%{
          "id" => to_string(question_id),
          "expires_at" => extract_expires_at(question),
          "expired" => poll_expired?(question),
          "multiple" => allows_multiple?(question),
          "votes_count" => Keyword.get(opts, :votes_count) || calculate_votes_count(choices),
          "voters_count" => Keyword.get(opts, :voters_count),
          "voted" => voted,
          "own_votes" => own_votes,
          "options" => build_options(choices),
          "emojis" => []
        })
      else
        nil
      end
    end

    def from_question(_, _opts), do: nil

    @doc """
    Check if a given object is a Poll Question type.
    Uses module name check to avoid compile-time struct dependency.
    """
    def is_poll?(nil), do: false

    def is_poll?(object) when is_map(object) do
      struct_module = e(object, :__struct__, nil)

      cond do
        is_nil(struct_module) -> false
        struct_module == Bonfire.Poll.Question -> true
        to_string(struct_module) =~ "Poll.Question" -> true
        true -> false
      end
    end

    def is_poll?(_), do: false

    # Get choices in consistent order (by rank or id)
    defp get_ordered_choices(question) do
      e(question, :choices, [])
      |> List.wrap()
      |> Enum.sort_by(&e(&1, :id, ""))
    end

    # Build options array for Mastodon format
    defp build_options(choices) do
      choices
      |> Enum.map(fn choice ->
        %{
          "title" => extract_choice_title(choice),
          "votes_count" => e(choice, :votes_count, nil) || 0
        }
      end)
    end

    defp extract_choice_title(choice) do
      e(choice, :post_content, :name, nil) ||
        e(choice, :post_content, :html_body, nil) ||
        e(choice, :post_content, :summary, nil) ||
        ""
    end

    # Get user's vote info (voted boolean and own_votes indices)
    defp get_user_vote_info(nil, _question, _choices, _opts), do: {false, []}

    defp get_user_vote_info(current_user, question, choices, opts) do
      # Check if pre-loaded user votes were passed in opts
      user_votes = Keyword.get(opts, :user_votes)

      voted_choice_ids =
        if user_votes do
          # Use pre-loaded votes
          Enum.map(user_votes, &e(&1, :edge, :object_id, nil))
        else
          # Query for user votes (this is the N+1 path, but keeps it DRY)
          get_user_voted_choice_ids(current_user, question, choices)
        end

      if Enum.empty?(voted_choice_ids) do
        {false, []}
      else
        # Convert choice IDs to 0-indexed positions
        own_vote_indices =
          choices
          |> Enum.with_index()
          |> Enum.filter(fn {choice, _idx} -> e(choice, :id, nil) in voted_choice_ids end)
          |> Enum.map(fn {_choice, idx} -> idx end)

        {true, own_vote_indices}
      end
    end

    # Get the IDs of choices the user has voted for
    defp get_user_voted_choice_ids(current_user, _question, choices) do
      choice_ids = Enum.map(choices, &e(&1, :id, nil)) |> Enum.reject(&is_nil/1)

      if Enum.empty?(choice_ids) do
        []
      else
        # Use existing by_voter with objects filter (single query instead of N+1)
        Bonfire.Poll.Votes.by_voter(current_user, objects: choice_ids)
        |> Enum.map(&e(&1, :edge, :object_id, nil))
        |> Enum.reject(&is_nil/1)
      end
    end

    # Extract expiration datetime from voting_dates
    defp extract_expires_at(question) do
      case e(question, :voting_dates, []) do
        [_, close_at | _] when not is_nil(close_at) ->
          Helpers.format_datetime(close_at)

        _ ->
          nil
      end
    end

    # Check if poll has expired
    def poll_expired?(question) do
      case e(question, :voting_dates, []) do
        [_, close_at | _] when not is_nil(close_at) ->
          case close_at do
            %DateTime{} = dt -> DateTime.compare(DateTime.utc_now(), dt) == :gt
            _ -> false
          end

        _ ->
          false
      end
    end

    # Check if poll allows multiple choices
    defp allows_multiple?(question) do
      voting_format = e(question, :voting_format, "single")
      voting_format != "single"
    end

    # Calculate total votes across all choices
    defp calculate_votes_count(choices) do
      choices
      |> Enum.reduce(0, fn choice, acc ->
        acc + (e(choice, :votes_count, nil) || 0)
      end)
    end
  end
end
