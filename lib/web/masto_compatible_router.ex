defmodule Bonfire.API.GraphQL.MastoCompatible.Router do
  @api_spec Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/akkoma-openapi.json")

  defmacro include_masto_api do
    quote do
      scope "/" do
        pipe_through([:basic_json, :load_authorization, :load_current_auth])

        # add here to override wrong priority order of routes
        get "/api/v1/accounts/verify_credentials",
            Bonfire.API.MastoCompatible.AccountController,
            :verify_credentials

        get "/api/v1/accounts/:id", Bonfire.API.MastoCompatible.AccountController, :show

        get "/api/v1/preferences",
            Bonfire.API.MastoCompatible.AccountController,
            :show_preferences

        get "/api/v1/instance", Bonfire.API.MastoCompatible.InstanceController, :show
        get "/api/v2/instance", Bonfire.API.MastoCompatible.InstanceController, :show_v2

        post "/api/v1/apps", Bonfire.API.MastoCompatible.AppController, :create

        get "/api/v1/timelines/home", Bonfire.API.MastoCompatible.TimelineController, :home
        get "/api/v1/timelines/:feed", Bonfire.API.MastoCompatible.TimelineController, :timeline

        # require Apical
        # Apical.router_from_file(unquote(@api_spec),
        #   controller: Bonfire.API.MastoCompatible,
        #   nest_all_json: false, # If enabled, nest all json request body payloads under the "_json" key. Otherwise objects payloads will be merged into `conn.params`.
        #   root: "/", 
        #   dump: :all # temp: ony for debug
        # )
      end
    end
  end
end
