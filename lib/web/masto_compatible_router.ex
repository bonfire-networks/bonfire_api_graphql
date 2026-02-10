defmodule Bonfire.API.GraphQL.MastoCompatible.Router do
  @behaviour Bonfire.UI.Common.RoutesModule
  # @api_spec Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/akkoma-openapi.json")

  defmacro __using__(_) do
    quote do
      # Define a pipeline for API routes with Oaskit/JSV validation
      pipeline :masto_api do
        # plug Oaskit.Plugs.SpecProvider, spec: Bonfire.API.MastoCompatible.Schema
      end

      # Pipeline for authenticated routes that require email confirmation (Mastodon-compatible)
      pipeline :require_confirmed do
        plug Bonfire.OpenID.Plugs.RequireConfirmed
      end

      # if Bonfire.Common.Extend.module_enabled?(Bonfire.OpenID.Plugs.Authorize) do

      # Mastodon-compatible API routes
      # import Bonfire.OpenID.Plugs.Authorize

      # Health check endpoints (Kubernetes-style probes)
      scope "/" do
        get "/livez", Bonfire.API.MastoCompatible.HealthController, :livez
        get "/readyz", Bonfire.API.MastoCompatible.HealthController, :readyz
      end

      # Public routes (no auth required)
      scope "/api/v1" do
        pipe_through([:basic_json, :masto_api])

        # App registration - used by clients to get client_id/secret before any user auth
        post "/apps", Bonfire.API.MastoCompatible.AppController, :create
      end

      # Routes that work WITHOUT email confirmation (signup, lookup, resend confirmation)
      scope "/api/v1" do
        pipe_through([:basic_json, :masto_api, :load_authorization])

        # Account registration - MUST work before email confirmation
        post "/accounts", Bonfire.Me.Web.MastoSignupController, :create

        # Account lookup by webfinger - allowed for unconfirmed accounts (to check username availability)
        get "/accounts/lookup",
            Bonfire.Me.Web.MastoAccountController,
            :lookup

        # Resend confirmation email
        post "/emails/confirmations", Bonfire.Me.Web.MastoSignupController, :resend_confirmation
      end

      # Routes that REQUIRE email confirmation
      scope "/api/v1" do
        pipe_through([:basic_json, :masto_api, :load_authorization, :require_confirmed])

        # add here to override wrong priority order of routes
        get "/accounts/verify_credentials",
            Bonfire.Me.Web.MastoAccountController,
            :verify_credentials

        # Account update credentials - MUST come before /accounts/:id
        patch "/accounts/update_credentials",
              Bonfire.Me.Web.MastoAccountController,
              :update_credentials

        # Account deletion and migration
        post "/accounts/delete", Bonfire.Me.Web.MastoAccountController, :delete_account
        post "/accounts/alias", Bonfire.Me.Web.MastoAccountController, :alias_account
        post "/accounts/move", Bonfire.Me.Web.MastoAccountController, :move_account

        # Profile image deletion
        delete "/profile/avatar", Bonfire.Me.Web.MastoAccountController, :delete_avatar
        delete "/profile/header", Bonfire.Me.Web.MastoAccountController, :delete_header

        # Markers - timeline position tracking (stub for client compatibility)
        get "/markers", Bonfire.API.MastoCompatible.MarkersController, :index
        post "/markers", Bonfire.API.MastoCompatible.MarkersController, :create

        # More specific routes must come BEFORE less specific ones
        get "/accounts/:id/statuses",
            Bonfire.Social.Web.MastoTimelineController,
            :user_statuses

        get "/accounts/:id/followers",
            Bonfire.Me.Web.MastoAccountController,
            :followers

        get "/accounts/:id/following",
            Bonfire.Me.Web.MastoAccountController,
            :following

        # Account featured tags - get pinned hashtags for any account
        get "/accounts/:id/featured_tags",
            Bonfire.Tag.Web.MastoTagController,
            :account_featured_tags

        # Account lists - get lists containing an account
        get "/accounts/:id/lists",
            Bonfire.Boundaries.Web.MastoListController,
            :account_lists

        # Account actions - follow/unfollow/mute/unmute/block/unblock
        post "/accounts/:id/follow", Bonfire.Me.Web.MastoAccountController, :follow
        post "/accounts/:id/unfollow", Bonfire.Me.Web.MastoAccountController, :unfollow
        post "/accounts/:id/mute", Bonfire.Me.Web.MastoAccountController, :mute
        post "/accounts/:id/unmute", Bonfire.Me.Web.MastoAccountController, :unmute
        post "/accounts/:id/block", Bonfire.Me.Web.MastoAccountController, :block
        post "/accounts/:id/unblock", Bonfire.Me.Web.MastoAccountController, :unblock

        # Account relationships - MUST come before /accounts/:id
        get "/accounts/relationships",
            Bonfire.Me.Web.MastoAccountController,
            :relationships

        # Account search - MUST come before /accounts/:id
        get "/accounts/search",
            Bonfire.Me.Web.MastoAccountController,
            :search

        # Themes - MUST come before /accounts/:id (not implemented, return empty array)
        get "/accounts/themes",
            Bonfire.API.MastoCompatible.InstanceController,
            :themes

        get "/accounts/:id", Bonfire.Me.Web.MastoAccountController, :show

        get "/preferences",
            Bonfire.Me.Web.MastoAccountController,
            :show_preferences

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show
        get "/custom_emojis", Bonfire.API.MastoCompatible.InstanceController, :custom_emojis

        # Status creation - must come before /statuses/:id routes
        post "/statuses", Bonfire.Posts.Web.MastoStatusController, :create

        # Status GET endpoints (more specific routes before generic)
        get "/statuses/:id/context", Bonfire.Social.Web.MastoStatusController, :context

        get "/statuses/:id/favourited_by",
            Bonfire.Social.Web.MastoStatusController,
            :favourited_by

        get "/statuses/:id/reblogged_by",
            Bonfire.Social.Web.MastoStatusController,
            :reblogged_by

        get "/statuses/:id/source", Bonfire.Social.Web.MastoStatusController, :source

        get "/statuses/:id", Bonfire.Social.Web.MastoStatusController, :show
        put "/statuses/:id", Bonfire.Social.Web.MastoStatusController, :update
        delete "/statuses/:id", Bonfire.Social.Web.MastoStatusController, :delete

        # Status POST interactions
        post "/statuses/:id/favourite", Bonfire.Social.Web.MastoStatusController, :favourite

        post "/statuses/:id/unfavourite",
             Bonfire.Social.Web.MastoStatusController,
             :unfavourite

        post "/statuses/:id/reblog", Bonfire.Social.Web.MastoStatusController, :reblog
        post "/statuses/:id/unreblog", Bonfire.Social.Web.MastoStatusController, :unreblog
        post "/statuses/:id/bookmark", Bonfire.Social.Web.MastoStatusController, :bookmark
        post "/statuses/:id/unbookmark", Bonfire.Social.Web.MastoStatusController, :unbookmark
        post "/statuses/:id/pin", Bonfire.Social.Web.MastoStatusController, :pin
        post "/statuses/:id/unpin", Bonfire.Social.Web.MastoStatusController, :unpin

        # Notifications
        post "/notifications/clear",
             Bonfire.Social.Web.MastoTimelineController,
             :clear_notifications

        # Notification requests (pending follow requests) - MUST come before /notifications/:id
        get "/notifications/requests",
            Bonfire.Social.Web.MastoTimelineController,
            :notification_requests

        post "/notifications/:id/dismiss",
             Bonfire.Social.Web.MastoTimelineController,
             :dismiss_notification

        get "/notifications/:id", Bonfire.Social.Web.MastoTimelineController, :notification
        get "/notifications", Bonfire.Social.Web.MastoTimelineController, :notifications

        # Bookmarks
        get "/bookmarks", Bonfire.Social.Web.MastoTimelineController, :bookmarks

        # Favourites
        get "/favourites", Bonfire.Social.Web.MastoTimelineController, :favourites

        # Mutes and Blocks lists
        get "/mutes", Bonfire.Me.Web.MastoAccountController, :mutes
        get "/blocks", Bonfire.Me.Web.MastoAccountController, :blocks

        # Follow Requests - specific routes before generic
        get "/follow_requests/outgoing",
            Bonfire.Me.Web.MastoAccountController,
            :follow_requests_outgoing

        post "/follow_requests/:account_id/authorize",
             Bonfire.Me.Web.MastoAccountController,
             :authorize_follow_request

        post "/follow_requests/:account_id/reject",
             Bonfire.Me.Web.MastoAccountController,
             :reject_follow_request

        get "/follow_requests",
            Bonfire.Me.Web.MastoAccountController,
            :follow_requests

        # Conversations (DM threads) - specific routes before generic
        post "/conversations/:id/read",
             Bonfire.Messages.Web.MastoConversationController,
             :mark_read

        delete "/conversations/:id", Bonfire.Messages.Web.MastoConversationController, :delete
        get "/conversations", Bonfire.Messages.Web.MastoConversationController, :index

        # Lists - specific routes before generic
        get "/lists/:id/accounts", Bonfire.Boundaries.Web.MastoListController, :accounts
        post "/lists/:id/accounts", Bonfire.Boundaries.Web.MastoListController, :add_accounts

        delete "/lists/:id/accounts",
               Bonfire.Boundaries.Web.MastoListController,
               :remove_accounts

        get "/lists/:id", Bonfire.Boundaries.Web.MastoListController, :show
        put "/lists/:id", Bonfire.Boundaries.Web.MastoListController, :update
        delete "/lists/:id", Bonfire.Boundaries.Web.MastoListController, :delete
        get "/lists", Bonfire.Boundaries.Web.MastoListController, :index
        post "/lists", Bonfire.Boundaries.Web.MastoListController, :create

        # Tags - follow/unfollow hashtags (specific routes before generic)
        post "/tags/:name/follow", Bonfire.Tag.Web.MastoTagController, :follow
        post "/tags/:name/unfollow", Bonfire.Tag.Web.MastoTagController, :unfollow
        get "/tags/:name", Bonfire.Tag.Web.MastoTagController, :show
        get "/followed_tags", Bonfire.Tag.Web.MastoTagController, :followed

        # Featured tags - pinned hashtags on user profile
        get "/featured_tags", Bonfire.Tag.Web.MastoTagController, :featured
        post "/featured_tags", Bonfire.Tag.Web.MastoTagController, :feature
        delete "/featured_tags/:id", Bonfire.Tag.Web.MastoTagController, :unfeature

        # Polls - view and vote (specific routes before generic)
        post "/polls/:id/votes", Bonfire.Poll.Web.MastoPollController, :vote
        get "/polls/:id", Bonfire.Poll.Web.MastoPollController, :show

        # Timelines - specific routes before generic
        get "/timelines/home", Bonfire.Social.Web.MastoTimelineController, :home
        get "/timelines/public", Bonfire.Social.Web.MastoTimelineController, :public
        get "/timelines/local", Bonfire.Social.Web.MastoTimelineController, :local
        get "/timelines/tag/:hashtag", Bonfire.Social.Web.MastoTimelineController, :hashtag

        get "/timelines/list/:list_id",
            Bonfire.Social.Web.MastoTimelineController,
            :list_timeline

        get "/timelines/:feed", Bonfire.Social.Web.MastoTimelineController, :timeline

        # Media endpoints
        get "/media/:id", Bonfire.Files.Web.MastoMediaController, :show
        put "/media/:id", Bonfire.Files.Web.MastoMediaController, :update
        post "/media", Bonfire.Files.Web.MastoMediaController, :create

        # Push subscription (web push notifications)
        post "/push/subscription", Bonfire.Notify.Web.MastoPushController, :create
        get "/push/subscription", Bonfire.Notify.Web.MastoPushController, :show
        put "/push/subscription", Bonfire.Notify.Web.MastoPushController, :update
        delete "/push/subscription", Bonfire.Notify.Web.MastoPushController, :delete

        # TODO: SSE streaming for real-time notifications
        # get "/streaming", Bonfire.Notify.Web.MastoStreamingController, :stream

        # Reports - specific route before generic
        get "/reports/:id", Bonfire.Social.Web.MastoReportController, :show
        get "/reports", Bonfire.Social.Web.MastoReportController, :index
        post "/reports", Bonfire.Social.Web.MastoReportController, :create
      end

      scope "/api/v2" do
        pipe_through([:basic_json, :masto_api, :load_authorization])

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show_v2
        get "/search", Bonfire.Search.Web.MastoSearchController, :search

        # Suggestions - accounts to follow
        get "/suggestions", Bonfire.Me.Web.MastoAccountController, :suggestions

        # Media upload (async - returns 202 Accepted)
        post "/media", Bonfire.Files.Web.MastoMediaController, :create_v2

        # Notifications (proxied to v1 handler for now; grouped format is a follow-up)
        get "/notifications", Bonfire.Social.Web.MastoTimelineController, :notifications
      end

      scope "/api/bonfire-v1" do
        pipe_through([:basic_json, :masto_api, :load_authorization])

        get "/timelines/events", Bonfire.Social.Events.MastoEventsController, :events_timeline
        get "/accounts/:id/events", Bonfire.Social.Events.MastoEventsController, :user_events
        get "/events/:id", Bonfire.Social.Events.MastoEventsController, :show

        get "/locations", Bonfire.Geolocate.Web.MastoLocationsController, :index
        get "/locations/:id", Bonfire.Geolocate.Web.MastoLocationsController, :show
        # add custom endpoints here
      end

      # scope "/" do
      # pipe_through([:basic_json, :load_authorization])
      # require Apical
      # Apical.router_from_file(unquote(@api_spec),
      #   controller: Bonfire.API.MastoCompatible,
      #   nest_all_json: false, # If enabled, nest all json request body payloads under the "_json" key. Otherwise objects payloads will be merged into `conn.params`.
      #   root: "/", 
      #   dump: :all # temp: ony for debug
      # )
      # end

      # else
      #   IO.puts(
      #     "Mastodon-compatible API routes not included (Bonfire.OpenID not enabled, make sure the extension is included and you can ENABLE_SSO_PROVIDER=true in env)."
      #   )
      # end
    end
  end
end
