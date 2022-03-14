defmodule Bonfire.API.GraphQL.Router do
  defmacro __using__(_) do
    quote do
      import Redirect

      @schema Bonfire.API.GraphQL.Schema

      pipeline = {Bonfire.API.GraphQL.PlugPipelines, :default_pipeline}

      @doc """
      Used to serve the GraphiQL API browser
      """
      pipeline :api_browser do
        plug(:accepts, ["html", "json", "css", "js"])
        plug(:put_secure_browser_headers)
        plug(:fetch_session)
        plug(:fetch_flash)
        # plug(:protect_from_forgery) # enabling interferes with graphql
      end

      @doc """
      Used to serve GraphQL API queries
      """
      pipeline :graphql do
        plug(:accepts, ["json"])
        plug(:fetch_session)
        plug(Bonfire.API.GraphQL.Plugs.GraphQLContext)
      end

      scope "/api" do

        # TODO: choose default UI in config
        redirect("/", "/api/explore", :temporary)

        get("/schema", Bonfire.API.GraphQL.DevTools, :schema)

        scope "/explore" do
          pipe_through(:api_browser)
          pipe_through(:graphql)

          get("/simple", Absinthe.Plug.GraphiQL,
            schema: @schema,
            interface: :simple,
            json_codec: Jason,
            pipeline: pipeline,
            socket: Bonfire.API.GraphQL.UserSocket,
            default_url: "/api/graphql"
          )

          get("/playground", Absinthe.Plug.GraphiQL,
            schema: @schema,
            interface: :playground,
            default_url: "/api/graphql",
            json_codec: Jason,
            pipeline: pipeline,
            socket: Bonfire.API.GraphQL.UserSocket,
            before_send: {__MODULE__, :absinthe_before_send}
          )

          forward("/", Absinthe.Plug.GraphiQL,
            schema: @schema,
            interface: :advanced,
            default_url: "/api/graphql",
            json_codec: Jason,
            pipeline: pipeline,
            socket: Bonfire.API.GraphQL.UserSocket,
            before_send: {__MODULE__, :absinthe_before_send}
          )
        end

        scope "/graphql" do
          pipe_through(:graphql)

          forward("/", Absinthe.Plug,
            schema: @schema,
            json_codec: Jason,
            pipeline: {Bonfire.API.GraphQL.PlugPipelines, :default_pipeline},
            socket: Bonfire.API.GraphQL.UserSocket,
            before_send: {__MODULE__, :absinthe_before_send}
          )
        end
      end

      # Auth integration
      def absinthe_before_send(conn, blueprint), do: Bonfire.API.GraphQL.Auth.set_session_from_context(conn, blueprint)

    end
  end
end
