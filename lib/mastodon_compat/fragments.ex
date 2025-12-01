if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Fragments do
    @moduledoc """
    Shared GraphQL fragments for Mastodon API adapters.

    This module centralizes common GraphQL query fragments used across multiple
    adapters to ensure consistency and reduce duplication.

    ## Usage

        alias Bonfire.API.MastoCompat.Fragments

        @user_profile Fragments.user_profile()

        @graphql "query { user { \#{@user_profile} } }"
    """

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

    @doc """
    User profile fragment for Mastodon Account mapping.

    Includes all fields needed by `Mappers.Account.from_user/2`:
    - Basic identity (id, created_at)
    - Profile data (avatar, header, display_name, note)
    - Character data (username, canonical_uri for acct/url)
    """
    def user_profile, do: @user_profile

    @post_content """
      name
      summary
      content: html_body
    """

    @doc """
    Post content fragment for status content extraction.

    Maps Bonfire PostContent fields to Mastodon Status content fields.
    """
    def post_content, do: @post_content

    @media """
      id
      url
      path
      media_type
      label
      description
      size
    """

    @doc """
    Media attachment fragment for status media.

    Includes all fields needed by `Mappers.Status` media attachment handling.
    """
    def media, do: @media
  end
end
