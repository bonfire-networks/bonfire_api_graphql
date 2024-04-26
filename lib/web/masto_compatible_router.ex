defmodule Bonfire.API.GraphQL.MastoCompatible.Router do
  @api_spec Path.join(:code.priv_dir(:bonfire_api_graphql), "specs/akkoma-openapi.json")

  defmacro include_masto_api do
    quote do
      scope "/" do
        pipe_through(:basic_json)
        pipe_through(:load_current_auth)

        # add here to override wrong priority order of routes
        get "/api/v1/accounts/verify_credentials",
            Bonfire.API.MastoCompatible.AccountController,
            :verify_credentials

        get "/api/v1/accounts/:id", Bonfire.API.MastoCompatible.AccountController, :show

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
