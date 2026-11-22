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
    - `poll_fields/0` - Poll fields (`... on Poll`)
    - `object_interactions/0` - The reader's like/boost/bookmark of an object or activity
    - `status_post_content/0`, `status_object/0` - A status's content and its object (post or poll)
    - `post_content/0` - Status content fields
    - `media/0` - Media fields for status queries
    """

    @doc "Thread linkage and parent author for Mastodon status responses."
    def thread_fields do
      """
      replied {
        reply_to_id: replyToId
        reply_to: replyTo { id subject { ... on User { id } ... on Category { id } } }
      }
      """
    end

    # ===========================================
    # Account / User fragments
    # ===========================================

    @user_profile """
      id
      created_at: date_created
      discoverable
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

    @account_fields @user_profile <>
                      """
                        followers_count
                        following_count
                        statuses_count
                      """

    @doc "`user_profile/0` plus the counts."
    def account_fields, do: @account_fields

    # Actor (subject/creator) selection for the raw `Absinthe.run` masto read paths. camelCase
    # field names with snake_case aliases (the inline-query style those adapters use), and it
    # MUST cover every actor type in the :any_character union — User AND Category (groups) — or
    # group-authored activities resolve to an untyped actor and get dropped on validation.
    @actor_fields """
    ... on User { id discoverable character { username url: canonicalUri } profile { name summary avatar: icon header: image } }
    ... on Category { id character { username url: canonicalUri } profile { name summary avatar: icon header: image } }
    """

    @doc "Actor (subject/creator) fields for `Absinthe.run` masto queries — covers User + Category."
    def actor_fields, do: @actor_fields

    @author_counts "followers_count: followersCount following_count: followingCount statuses_count: statusesCount"

    @author_fields @actor_fields <>
                     """
                     ... on User { #{@author_counts} }
                     ... on Category { #{@author_counts} }
                     """

    @doc "`actor_fields/0` plus the counts, for authors; mentions use `actor_fields/0`."
    def author_fields, do: @author_fields

    @poll_fields """
    id
    __typename
    voting_format: votingFormat
    voting_close_at: votingCloseAt
    votes_count: votesCount
    voters_count: votersCount
    voted
    own_votes: ownVotes { id }
    choices { id post_content: postContent { name html_body: htmlBody summary } votes_result_total: votesResultTotal }
    """

    @doc "Poll fields for `Mappers.Poll.from_question/2`: the poll endpoint selects them, and the status queries inside `... on Poll` so a poll status needs no second query."
    def poll_fields, do: @poll_fields

    @doc "Whether the reader liked, boosted or bookmarked it. Inside `... on Post`/`... on Poll` they describe the object; on an activity, that activity (on a boost or a like the two differ)."
    def object_interactions,
      do: "liked_by_me: likedByMe boosted_by_me: boostedByMe bookmarked_by_me: bookmarkedByMe"

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
      preview_url: thumbnail_url
      path
      media_type
      label
      description
      size
    """

    @doc "GraphQL fragment for media fields (used in status queries)"
    def media, do: @media

    @doc "A status's media attachments, aliased to the keys `Mappers.MediaAttachment` reads."
    def status_media do
      "media { id media_type: mediaType url preview_url: thumbnailUrl description metadata }"
    end

    @doc "A status's content, aliased to the keys `Mappers.Status` reads."
    def status_post_content, do: "post_content: postContent { name summary html_body: rawBody }"

    @doc """
    A conversation (`my_conversations`, `conversation(id:)`) for `Mappers.Conversation`, its own selection rather than the shared status ones (conversation decision 9). It leaves out what the conversations API has never shown: counts, the replied-to post, media and hashtags (conversation decision 8). Participants and sender are read with the reader's boundaries.
    """
    def conversation_fields do
      """
      id
      unread
      participants { #{author_fields()} }
      sender { #{author_fields()} }
      last_message: lastMessage {
        id
        #{status_post_content()}
        #{object_interactions()}
        activity { mentions { #{actor_fields()} } }
      }
      """
    end

    @doc "A status's object: a post or a poll, with its content, media, author and the reader's flags on it."
    def status_object do
      """
      object {
        __typename
        ... on Post {
          id
          #{status_post_content()}
          #{status_media()}
          creator { #{author_fields()} }
          #{object_interactions()}
        }
        ... on Poll {
          #{poll_fields()}
          #{status_post_content()}
          creator { #{author_fields()} }
          #{object_interactions()}
        }
      }
      """
    end
  end
end
