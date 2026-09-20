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

    doctest PaginationHelpers, only: [build_timeline_params: 3], import: true

    describe "timeline history window" do
      test "bounds timelines even when the native feed window is one year" do
        Process.put([:bonfire_ui_social, Bonfire.UI.Social.FeedLive, :time_limit], 365)

        for feed_name <- ["my", "local", "explore", "custom", nil] do
          params =
            PaginationHelpers.build_timeline_params(%{"limit" => "5"}, %{"feed_name" => feed_name})

          assert params["filter"]["time_limit"] == 7
          assert params[:first] == 5
        end
      end

      test "keeps the window on subsequent pages and preserves timeline filters" do
        params =
          PaginationHelpers.build_timeline_params(%{"max_id" => "01KQF70CN3DVTXVN6VWWPZ1B1J"}, %{
            "feed_name" => "local",
            "tags" => ["bonfire"]
          })

        assert params["filter"]["time_limit"] == 7
        assert params["filter"]["tags"] == ["bonfire"]
        assert params[:after]
      end

      test "honors explicit time filters, including unlimited history" do
        for days <- [0, 2, 30] do
          params = PaginationHelpers.build_timeline_params(%{"time_limit" => days}, %{"feed_name" => "my"})
          assert params["filter"]["time_limit"] == days
        end
      end

      test "does not restrict archive and notification callers" do
        for feed_name <- ["notifications", "user_activities", "bookmarks", nil] do
          params = PaginationHelpers.build_feed_params(%{}, %{"feed_name" => feed_name})
          assert params["filter"]["time_limit"] == 0
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
