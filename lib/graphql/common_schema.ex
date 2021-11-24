
defmodule Bonfire.GraphQL.CommonSchema do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers
  alias Bonfire.GraphQL.CommonResolver


  object :login_response do
    # field(:current_account, :json)
    field(:current_user, :user)
    field(:current_account_id, :string)
    field(:current_username, :string)

  end

  object :common_queries do
  end

  object :common_mutations do

    @desc "Authenticate an account / user"
    field :login, :login_response do
      arg(:email_or_username, non_null(:string))
      arg(:password, non_null(:string))

      resolve(&Bonfire.GraphQL.Auth.login/3)
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
    field(:start_cursor, list_of(non_null(:cursor)))
    field(:end_cursor, list_of(non_null(:cursor)))
    field(:has_previous_page, :boolean)
    field(:has_next_page, :boolean)
  end

end
