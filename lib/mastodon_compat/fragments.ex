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

    - `user_profile/0` - Fields for Account mapping (profile, character, etc.)
    - `post_content/0` - Fields for Status content mapping
    - `activity_base/0` - Base fields for Activity mapping
    - `media_attachment/0` - Fields for MediaAttachment mapping
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
    # Activity fragments
    # ===========================================

    @activity_base """
      id
      date
      verb {
        verb
      }
      subject {
        #{@user_profile}
      }
    """

    @doc "GraphQL fragment for activity base fields"
    def activity_base, do: @activity_base

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

    @media_attachment """
      id
      media_type
      path
      metadata
    """

    @doc "GraphQL fragment for media attachment fields (alternative format)"
    def media_attachment, do: @media_attachment

    # ===========================================
    # Notification fragments
    # ===========================================

    @notification """
      id
      date
      verb {
        verb
      }
      subject {
        #{@user_profile}
      }
      object {
        ... on Post {
          #{@post_content}
        }
      }
    """

    @doc "GraphQL fragment for notification fields"
    def notification, do: @notification
  end
end
