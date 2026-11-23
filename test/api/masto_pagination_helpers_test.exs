if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.PaginationHelpersTest do
    @moduledoc """
    Unit tests for Mastodon pagination/limit handling and filter translation.
    """
    use ExUnit.Case, async: true

    # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag the extension case templates apply, so without it this also runs in the federation job catch-all
    @moduletag :backend

    alias Bonfire.API.MastoCompat.PaginationHelpers

    @moduletag :masto_api

    # Mastodon timelines carry no window; the 7-day one (commit 2692c30) stopped scrolling at posts a week old (masto-live-fixes pagination bug 1, decision 1.1), so timelines use build_feed_params/3 like the other lists
    describe "no history window" do
      test "timelines, archives and notifications carry none" do
        for feed_name <- [
              "my",
              "local",
              "explore",
              "notifications",
              "user_activities",
              "bookmarks",
              nil
            ] do
          params =
            PaginationHelpers.build_feed_params(%{"limit" => "5"}, %{"feed_name" => feed_name})

          assert params["filter"]["time_limit"] == 0
        end
      end

      test "keeps timeline filters on subsequent pages" do
        params =
          PaginationHelpers.build_feed_params(%{"max_id" => "01KQF70CN3DVTXVN6VWWPZ1B1J"}, %{
            "feed_name" => "local",
            "tags" => ["bonfire"]
          })

        assert params["filter"]["time_limit"] == 0
        assert params["filter"]["tags"] == ["bonfire"]
        assert params[:after]
      end

      test "honors explicit time filters" do
        for days <- [0, 2, 30] do
          params =
            PaginationHelpers.build_feed_params(%{"time_limit" => days}, %{"feed_name" => "my"})

          assert params["filter"]["time_limit"] == days
        end
      end
    end

    describe "validate_limit/2 caps" do
      test "clamps to the explicit max (Mastodon timeline/status/conversation max is 40)" do
        assert PaginationHelpers.validate_limit(100, max: 40) == 40
        assert PaginationHelpers.validate_limit("100", max: 40) == 40
        assert PaginationHelpers.validate_limit(40, max: 40) == 40
      end

      test "respects valid limits below the max" do
        assert PaginationHelpers.validate_limit(10, max: 40) == 10
      end

      test "falls back to default for nil/invalid" do
        assert PaginationHelpers.validate_limit(nil, default: 20, max: 40) == 20
        assert PaginationHelpers.validate_limit("abc", default: 20, max: 40) == 20
        assert PaginationHelpers.validate_limit(0, default: 20, max: 40) == 20
      end
    end

    describe "build_feed_params/2 only_media translation" do
      test "only_media=true adds a has-media filter (media_types: [\"*\"])" do
        params =
          PaginationHelpers.build_feed_params(%{"only_media" => "true"}, %{
            "feed_name" => "local"
          })

        assert params["filter"]["media_types"] == ["*"]
        assert params["filter"]["feed_name"] == "local"
      end

      test "only_media as a boolean true is also honored" do
        params =
          PaginationHelpers.build_feed_params(%{"only_media" => true}, %{"feed_name" => "local"})

        assert params["filter"]["media_types"] == ["*"]
      end

      test "only_media=false / absent does not add a media filter" do
        params_false =
          PaginationHelpers.build_feed_params(%{"only_media" => "false"}, %{
            "feed_name" => "local"
          })

        params_absent = PaginationHelpers.build_feed_params(%{}, %{"feed_name" => "local"})

        refute Map.has_key?(params_false["filter"], "media_types")
        refute Map.has_key?(params_absent["filter"], "media_types")
      end
    end
  end
end
