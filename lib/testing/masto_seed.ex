# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoCompat.Test.MastoSeed do
  @moduledoc """
  One scene that fills a user's Mastodon API views (home, thread, notifications, lists, tags), for tests that check response shapes.

  `seed!/0` returns a map of named records. A piece whose extension is disabled is skipped and its key left out.
  """
  import Bonfire.Common.Extend, only: [module_enabled?: 1]
  alias Bonfire.Me.Fake
  alias Bonfire.Posts.Fake, as: PostsFake
  alias Bonfire.Social.{Boosts, Likes, Objects}
  alias Bonfire.Social.Graph.Follows

  @tag "mastoseed"

  def seed! do
    account = Fake.fake_account!()
    a = Fake.fake_user!(account)
    b = Fake.fake_user!()
    {:ok, _} = Follows.follow(b, a)

    post = PostsFake.fake_post!(a, "public", content("Seed post ##{@tag}"))
    reply = PostsFake.fake_comment!(b, post, "public", reply_to(post, "Seed reply"))
    {:ok, _} = Likes.like(b, post)
    {:ok, _} = Boosts.boost(b, post)
    mention = mention_post(b, a, "public", "Seed mention")
    followers_only = followers_only_post(a)
    direct = mention_post(a, b, "mentions", "Seed direct")

    # a thread whose middle post is deleted, so the leaf has a missing ancestor
    root = PostsFake.fake_post!(a, "public", content("Thread root"))
    middle = PostsFake.fake_comment!(b, root, "public", reply_to(root, "Deleted middle"))
    leaf = PostsFake.fake_comment!(a, middle, "public", reply_to(middle, "Thread leaf"))
    {:ok, _} = Objects.delete(middle, current_user: b)

    %{
      account: account,
      a: a,
      b: b,
      post: post,
      reply: reply,
      mention: mention,
      followers_only: followers_only,
      direct: direct,
      root: root,
      leaf: leaf,
      tag: @tag
    }
    |> maybe_put(:hashtag, Bonfire.Tag, fn -> followed_tag(a) end)
    |> maybe_put(:list, Bonfire.Boundaries.Circles, fn -> list_with(a, b) end)
    |> maybe_put(:poll, Bonfire.Poll.Fake, fn -> poll(a) end)
    |> maybe_put(:media_post, Bonfire.Files, fn -> media_post(a) end)
    |> maybe_put(:group_post, Bonfire.Classify.Simulate, fn -> group_post(a) end)
  end

  defp maybe_put(seed, key, module, fun) do
    if module_enabled?(module), do: Map.put(seed, key, fun.()), else: seed
  end

  defp content(text), do: %{post_content: %{html_body: "<p>#{text}</p>"}}
  defp reply_to(parent, text), do: Map.put(content(text), :reply_to_id, parent.id)

  # b names a, so a reader other than a sees one mention (mappers leave the reader out of their own list)
  defp mention_post(author, named, boundary, text) do
    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: author,
        post_attrs:
          content(text)
          |> Map.put(:mentions, [named.id]),
        boundary: boundary,
        mentions: [named.id]
      )

    post
  end

  # what POST /api/v1/statuses does for visibility "private"
  defp followers_only_post(author) do
    followers = Bonfire.Boundaries.Circles.get_stereotype_circle_ids(author, :followers)

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: author,
        post_attrs: content("Seed followers only"),
        boundary: "mentions",
        to_circles: followers
      )

    post
  end

  defp followed_tag(a) do
    {:ok, hashtag} = Bonfire.Tag.get_or_create_hashtag(@tag)
    {:ok, _} = Follows.follow(a, hashtag, skip_boundary_check: true)
    hashtag
  end

  defp list_with(a, b) do
    {:ok, circle} = Bonfire.Boundaries.Circles.create(a, %{named: %{name: "Seed list"}})
    {:ok, _} = Bonfire.Boundaries.Circles.add_to_circles(b, circle, current_user: a)
    circle
  end

  defp poll(a) do
    {:ok, question} =
      Bonfire.Poll.Fake.fake_question_with_choices(
        %{post_content: %{html_body: "Seed poll?"}},
        [%{name: "Yes"}, %{name: "No"}],
        current_user: a
      )

    question
  end

  defp media_post(a) do
    media = Bonfire.Social.Fake.upload_media(:images, a, "seed image")

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: a,
        post_attrs: Map.put(content("Seed post with media"), :uploaded_media, [media]),
        boundary: "public"
      )

    post
  end

  # publishing into a group makes the group boost the post (the Tag act), which is the boost clients showed empty
  defp group_post(a) do
    group = Bonfire.Classify.Simulate.fake_group!(a, %{membership: "open"})

    {:ok, post} =
      Bonfire.Posts.publish(
        current_user: a,
        post_attrs:
          content("Seed post in a group")
          |> Map.merge(%{context_id: group.id, mentions: [group.id]}),
        boundary: "public",
        context_id: group.id,
        mentions: [group.id]
      )

    %{group: group, post: post}
  end
end
