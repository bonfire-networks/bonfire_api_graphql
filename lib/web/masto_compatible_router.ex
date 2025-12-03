defmodule Bonfire.API.GraphQL.MastoCompatible.Router do
  # @api_spec Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/akkoma-openapi.json")

  defmacro include_masto_api do
    quote do
      # Define a pipeline for API routes with Oaskit/JSV validation
      pipeline :masto_api do
        # plug Oaskit.Plugs.SpecProvider, spec: Bonfire.API.MastoCompatible.Schema
      end

      scope "/api/v1" do
        pipe_through([:basic_json, :masto_api, :load_authorization, :load_current_auth])

        # add here to override wrong priority order of routes
        get "/accounts/verify_credentials",
            Bonfire.API.MastoCompatible.AccountController,
            :verify_credentials

        # More specific routes must come BEFORE less specific ones
        get "/accounts/:id/statuses",
            Bonfire.API.MastoCompatible.TimelineController,
            :user_statuses

        get "/accounts/:id/followers",
            Bonfire.API.MastoCompatible.AccountController,
            :followers

        get "/accounts/:id/following",
            Bonfire.API.MastoCompatible.AccountController,
            :following

        # Account actions - follow/unfollow/mute/unmute/block/unblock
        post "/accounts/:id/follow", Bonfire.API.MastoCompatible.AccountController, :follow
        post "/accounts/:id/unfollow", Bonfire.API.MastoCompatible.AccountController, :unfollow
        post "/accounts/:id/mute", Bonfire.API.MastoCompatible.AccountController, :mute
        post "/accounts/:id/unmute", Bonfire.API.MastoCompatible.AccountController, :unmute
        post "/accounts/:id/block", Bonfire.API.MastoCompatible.AccountController, :block
        post "/accounts/:id/unblock", Bonfire.API.MastoCompatible.AccountController, :unblock

        # Account relationships - MUST come before /accounts/:id
        get "/accounts/relationships",
            Bonfire.API.MastoCompatible.AccountController,
            :relationships

        get "/accounts/:id", Bonfire.API.MastoCompatible.AccountController, :show

        get "/preferences",
            Bonfire.API.MastoCompatible.AccountController,
            :show_preferences

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show
        get "/custom_emojis", Bonfire.API.MastoCompatible.InstanceController, :custom_emojis

        post "/apps", Bonfire.API.MastoCompatible.AppController, :create

        # Status creation - must come before /statuses/:id routes
        post "/statuses", Bonfire.Posts.Web.MastoStatusController, :create

        # Status GET endpoints (more specific routes before generic)
        get "/statuses/:id/context", Bonfire.API.MastoCompatible.StatusController, :context

        get "/statuses/:id/favourited_by",
            Bonfire.API.MastoCompatible.StatusController,
            :favourited_by

        get "/statuses/:id/reblogged_by",
            Bonfire.API.MastoCompatible.StatusController,
            :reblogged_by

        get "/statuses/:id", Bonfire.API.MastoCompatible.StatusController, :show
        delete "/statuses/:id", Bonfire.API.MastoCompatible.StatusController, :delete

        # Status POST interactions
        post "/statuses/:id/favourite", Bonfire.API.MastoCompatible.StatusController, :favourite

        post "/statuses/:id/unfavourite",
             Bonfire.API.MastoCompatible.StatusController,
             :unfavourite

        post "/statuses/:id/reblog", Bonfire.API.MastoCompatible.StatusController, :reblog
        post "/statuses/:id/unreblog", Bonfire.API.MastoCompatible.StatusController, :unreblog
        post "/statuses/:id/bookmark", Bonfire.API.MastoCompatible.StatusController, :bookmark
        post "/statuses/:id/unbookmark", Bonfire.API.MastoCompatible.StatusController, :unbookmark

        # Notifications
        post "/notifications/clear",
             Bonfire.API.MastoCompatible.TimelineController,
             :clear_notifications

        post "/notifications/:id/dismiss",
             Bonfire.API.MastoCompatible.TimelineController,
             :dismiss_notification

        get "/notifications/:id", Bonfire.API.MastoCompatible.TimelineController, :notification
        get "/notifications", Bonfire.API.MastoCompatible.TimelineController, :notifications

        # Bookmarks
        get "/bookmarks", Bonfire.API.MastoCompatible.TimelineController, :bookmarks

        # Favourites
        get "/favourites", Bonfire.API.MastoCompatible.TimelineController, :favourites

        # Mutes and Blocks lists
        get "/mutes", Bonfire.API.MastoCompatible.AccountController, :mutes
        get "/blocks", Bonfire.API.MastoCompatible.AccountController, :blocks

        # Follow Requests - specific routes before generic
        get "/follow_requests/outgoing",
            Bonfire.API.MastoCompatible.AccountController,
            :follow_requests_outgoing

        post "/follow_requests/:account_id/authorize",
             Bonfire.API.MastoCompatible.AccountController,
             :authorize_follow_request

        post "/follow_requests/:account_id/reject",
             Bonfire.API.MastoCompatible.AccountController,
             :reject_follow_request

        get "/follow_requests",
            Bonfire.API.MastoCompatible.AccountController,
            :follow_requests

        # Conversations (DM threads) - specific routes before generic
        post "/conversations/:id/read",
             Bonfire.API.MastoCompatible.ConversationController,
             :mark_read

        # TODO: delete "/conversations/:id", Bonfire.API.MastoCompatible.ConversationController, :delete
        get "/conversations", Bonfire.API.MastoCompatible.ConversationController, :index

        # Lists - specific routes before generic
        get "/lists/:id/accounts", Bonfire.API.MastoCompatible.ListController, :accounts
        post "/lists/:id/accounts", Bonfire.API.MastoCompatible.ListController, :add_accounts
        delete "/lists/:id/accounts", Bonfire.API.MastoCompatible.ListController, :remove_accounts
        get "/lists/:id", Bonfire.API.MastoCompatible.ListController, :show
        put "/lists/:id", Bonfire.API.MastoCompatible.ListController, :update
        delete "/lists/:id", Bonfire.API.MastoCompatible.ListController, :delete
        get "/lists", Bonfire.API.MastoCompatible.ListController, :index
        post "/lists", Bonfire.API.MastoCompatible.ListController, :create

        # Timelines - specific routes before generic
        get "/timelines/home", Bonfire.API.MastoCompatible.TimelineController, :home
        get "/timelines/public", Bonfire.API.MastoCompatible.TimelineController, :public
        get "/timelines/local", Bonfire.API.MastoCompatible.TimelineController, :local
        get "/timelines/tag/:hashtag", Bonfire.API.MastoCompatible.TimelineController, :hashtag

        get "/timelines/list/:list_id",
            Bonfire.API.MastoCompatible.TimelineController,
            :list_timeline

        get "/timelines/:feed", Bonfire.API.MastoCompatible.TimelineController, :timeline

        # Media endpoints
        get "/media/:id", Bonfire.Files.Web.MastoMediaController, :show
        put "/media/:id", Bonfire.Files.Web.MastoMediaController, :update
        post "/media", Bonfire.Files.Web.MastoMediaController, :create

        # Reports - specific route before generic
        get "/reports/:id", Bonfire.API.MastoCompatible.ReportController, :show
        get "/reports", Bonfire.API.MastoCompatible.ReportController, :index
        post "/reports", Bonfire.API.MastoCompatible.ReportController, :create
      end

      scope "/api/v2" do
        pipe_through([:basic_json, :masto_api, :load_authorization, :load_current_auth])

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show_v2
        get "/search", Bonfire.Search.Web.MastoSearchController, :search

        # Media upload (async - returns 202 Accepted)
        post "/media", Bonfire.Files.Web.MastoMediaController, :create_v2
      end

      # scope "/" do
      # pipe_through([:basic_json, :load_authorization, :load_current_auth])
      # require Apical
      # Apical.router_from_file(unquote(@api_spec),
      #   controller: Bonfire.API.MastoCompatible,
      #   nest_all_json: false, # If enabled, nest all json request body payloads under the "_json" key. Otherwise objects payloads will be merged into `conn.params`.
      #   root: "/", 
      #   dump: :all # temp: ony for debug
      # )
      # end
    end
  end
end
