
defmodule Bonfire.GraphQL.CommonSchema do
  use Absinthe.Schema.Notation

  alias Bonfire.GraphQL.CommonResolver

  object :login_response do
    field(:current_account, :json)
    field(:current_user, :json)
  end

  object :common_queries do
  end

  object :common_mutations do

    @desc "Authenticate an account / user"
    field :login, :login_response do
      arg(:email_or_username, non_null(:string))
      arg(:password, non_null(:string))
      resolve(&CommonResolver.login/3)

      middleware(fn resolution, _ ->
        case resolution.value do
          %{current_user: current_user, current_account: current_account, auth_token: auth_token} ->
            Map.update!(
              resolution,
              :context,
              &Map.merge(&1, %{auth_token: auth_token, current_account: current_account, current_user: current_user})
            )

          _ ->
            resolution
        end
      end)
    end

    @desc "Delete more or less anything"
    field :delete, :any_context do
      arg(:context_id, non_null(:string))
      resolve(&CommonResolver.delete/2)
    end

  end

  @desc "Cursors for pagination"
  object :page_info do
    field(:start_cursor, list_of(non_null(:cursor)))
    field(:end_cursor, list_of(non_null(:cursor)))
    field(:has_previous_page, :boolean)
    field(:has_next_page, :boolean)
  end

end
