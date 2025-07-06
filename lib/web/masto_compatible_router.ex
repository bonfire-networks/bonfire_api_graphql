defmodule Bonfire.API.GraphQL.MastoCompatible.Router do
  @api_spec Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/akkoma-openapi.json")

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

        get "/accounts/:id", Bonfire.API.MastoCompatible.AccountController, :show

        get "/preferences",
            Bonfire.API.MastoCompatible.AccountController,
            :show_preferences

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show

        post "/apps", Bonfire.API.MastoCompatible.AppController, :create

        get "/timelines/home", Bonfire.API.MastoCompatible.TimelineController, :home
        get "/timelines/:feed", Bonfire.API.MastoCompatible.TimelineController, :timeline
      end

      scope "/api/v2" do
        pipe_through([:basic_json, :masto_api, :load_authorization, :load_current_auth])

        get "/instance", Bonfire.API.MastoCompatible.InstanceController, :show_v2
      end

      # scope "/" do
      # pipe_through([:basic_json, :load_authorization, :load_current_auth])
      # require Apical
      # Apical.router_from_file(unquote(@api_spec),
      #   controller: Bonfire.API.MastoCompatible,
      #   nest_all_json: false, # If enabled, nest all json request body payloads under the "_json" key. Otherwise objects payloads will be merged into `conn.params`.
      #   root: "/", 
      #   dump: :all # temp: ony for debug
      # )
      # end
    end
  end
end
