if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Fragments do
    @moduledoc """
    Centralized GraphQL fragments for Mastodon API mapping.

    These fragments define the GraphQL field selections used by adapters
    to fetch data for Mastodon-compatible responses.

    ## Usage

        alias Bonfire.API.MastoCompat.Fragments

        @user_profile Fragments.user_profile()
        @post_content Fragments.post_content()

    ## Available Fragments

    - `user_profile/0` - Account/profile fields (`... on User`)
    - `actor_fields/0` - Actor (subject/creator) selection covering User + Category (groups)
    - `post_content/0` - Status content fields
    - `media/0` - Media fields for status queries
    """

    # ===========================================
    # Account / User fragments
    # ===========================================

    @user_profile """
      id
      created_at: date_created
      profile {
        avatar: icon
        avatar_static: icon
        header: image
        header_static: image
        display_name: name
        note: summary
        website
      }
      character {
        username
        acct: username
        url: canonical_uri
        peered {
          canonical_uri
        }
      }
    """

    @doc "GraphQL fragment for user/account profile data"
    def user_profile, do: @user_profile

    # Actor (subject/creator) selection for the raw `Absinthe.run` masto read paths. camelCase
    # field names with snake_case aliases (the inline-query style those adapters use), and it
    # MUST cover every actor type in the :any_character union — User AND Category (groups) — or
    # group-authored activities resolve to an untyped actor and get dropped on validation.
    @actor_fields """
    ... on User { id character { username url: canonicalUri } profile { name summary } }
    ... on Category { id character { username url: canonicalUri } profile { name summary } }
    """

    @doc "Actor (subject/creator) fields for `Absinthe.run` masto queries — covers User + Category."
    def actor_fields, do: @actor_fields

    # ===========================================
    # Status / Post fragments
    # ===========================================

    @post_content """
      name
      summary
      content: html_body
    """

    @doc "GraphQL fragment for post/status content"
    def post_content, do: @post_content

    # ===========================================
    # Media fragments
    # ===========================================

    @media """
      id
      url
      path
      media_type
      label
      description
      size
    """

    @doc "GraphQL fragment for media fields (used in status queries)"
    def media, do: @media
  end
end
