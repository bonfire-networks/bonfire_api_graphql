defmodule Bonfire.GraphQL.CommonSchema do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers
  alias Bonfire.GraphQL.CommonResolver


  object :login_response do
    field(:token, :string)
    # field(:current_account, :json)
    field(:current_user, :user)
    field(:current_account_id, :string)
    field(:current_username, :string)

  end

  object :common_queries do
  end

  object :common_mutations do

    @desc "Authenticate an account and/or user"
    field :login, :login_response do
      arg(:email_or_username, non_null(:string))
      arg(:password, non_null(:string))

      resolve(&Bonfire.GraphQL.Auth.login/3)
      middleware(&Bonfire.GraphQL.Auth.set_context_from_resolution/2)
    end

    @desc "Switch to a user (among those from the authenticated account)"
    field :select_user, :login_response do
      arg(:username, non_null(:string))

      resolve(&Bonfire.GraphQL.Auth.select_user/3)
      middleware(&Bonfire.GraphQL.Auth.set_context_from_resolution/2)
    end

    @desc "Delete more or less anything"
    field :delete, :any_context do
      arg(:context_id, non_null(:string))
      resolve(&CommonResolver.delete/2)
    end

  end

  input_object :paginate do
    field :limit, :integer
    field :before, list_of(non_null(:cursor))
    field :after, list_of(non_null(:cursor))
  end

  @desc "Cursors for pagination"
  object :page_info do

    @desc "Cursor pointing to the first of the results returned, to be used with `before` query parameter if the backend supports reverse pagination."
    field(:start_cursor, list_of(non_null(:cursor)))

    @desc "Cursor pointing to the last of the results returned, to be used with `after` query parameter if the backend supports forward pagination."
    field(:end_cursor, list_of(non_null(:cursor)))

    @desc "True if there are more results before `startCursor`. If unable to be determined, implementations should return `true` to allow for requerying."
    field(:has_previous_page, :boolean)

    @desc "True if there are more results after `endCursor`. If unable to be determined, implementations should return `true` to allow for requerying."
    field(:has_next_page, :boolean)

    @desc "Returns the total result count, if it can be determined."
    field(:total_count, :integer)

  end
end
