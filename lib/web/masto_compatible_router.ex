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
        get "/accounts/:id/statuses", Bonfire.API.MastoCompatible.TimelineController, :user_statuses
        get "/accounts/:id", Bonfire.API.MastoCompatible.AccountController, :show

        get "/preferences",
            Bonfire.API.MastoCompatible.AccountController,
            :show_preferences

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show

        post "/apps", Bonfire.API.MastoCompatible.AppController, :create

        # Status interactions
        post "/statuses/:id/favourite", Bonfire.API.MastoCompatible.StatusController, :favourite
        post "/statuses/:id/unfavourite", Bonfire.API.MastoCompatible.StatusController, :unfavourite
        post "/statuses/:id/reblog", Bonfire.API.MastoCompatible.StatusController, :reblog
        post "/statuses/:id/unreblog", Bonfire.API.MastoCompatible.StatusController, :unreblog

        # Notifications
        get "/notifications", Bonfire.API.MastoCompatible.TimelineController, :notifications

        # Timelines - specific routes before generic
        get "/timelines/home", Bonfire.API.MastoCompatible.TimelineController, :home
        get "/timelines/public", Bonfire.API.MastoCompatible.TimelineController, :public
        get "/timelines/:feed", Bonfire.API.MastoCompatible.TimelineController, :timeline
      end

      scope "/api/v2" do
        pipe_through([:basic_json, :masto_api, :load_authorization, :load_current_auth])

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show_v2
      end
    end
  end
end
