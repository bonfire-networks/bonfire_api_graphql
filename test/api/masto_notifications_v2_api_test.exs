# SPDX-License-Identifier: AGPL-3.0-only
if Application.compile_env(:bonfire_social, :modularity) != :disabled do
  defmodule Bonfire.Social.Web.MastoNotificationsV2ApiTest do
    @moduledoc "Run with: just test extensions/bonfire_social/test/api/masto_api/masto_notifications_v2_api_test.exs"

    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    setup %{conn: conn} do
      account = Bonfire.Me.Fake.fake_account!()
      user = Bonfire.Me.Fake.fake_user!(account)

      conn = masto_api_conn(conn, user: user, account: account)

      {:ok, conn: conn, user: user, account: account}
    end

    defp unauthenticated_conn do
      Phoenix.ConnTest.build_conn()
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")
    end

    describe "GET /api/v1/notifications" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v1/notifications")
          |> json_response(200)

        assert is_list(response)
      end

      test "does not expose ordinary statuses as notifications", %{conn: conn, user: user} do
        other_user = Bonfire.Me.Fake.fake_user!()

        {:ok, own_post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "Own post should not notify me"}},
            boundary: "public"
          )

        {:ok, unrelated_post} =
          Bonfire.Posts.publish(
            current_user: other_user,
            post_attrs: %{post_content: %{html_body: "Unrelated post should not notify me"}},
            boundary: "public"
          )

        response =
          conn
          |> get("/api/v1/notifications?limit=30")
          |> json_response(200)

        ordinary_post_ids = [own_post.id, unrelated_post.id]

        leaked_status_notifications =
          Enum.filter(response, fn notification ->
            notification["type"] == "status" &&
              get_in(notification, ["status", "id"]) in ordinary_post_ids
          end)

        assert leaked_status_notifications == []
      end

      test "does not report a vote as a poll completion", %{
        conn: conn,
        user: user
      } do
        voter = Bonfire.Me.Fake.fake_user!()

        {:ok, question} =
          Bonfire.Poll.Fake.fake_question_with_choices(
            %{
              post_content: %{html_body: "Poll notification body"},
              voting_dates: [DateTime.utc_now()]
            },
            [%{name: "A"}],
            current_user: user
          )

        [choice] = question.choices

        assert {:ok, _} =
                 Bonfire.Poll.Votes.vote(voter, question, [
                   %{choice_id: choice.id, weight: 1}
                 ])

        response =
          conn
          |> get("/api/v1/notifications?limit=10")
          |> json_response(200)

        refute Enum.any?(response, fn notification ->
                 notification["type"] == "poll" &&
                   get_in(notification, ["status", "id"]) == question.id
               end)
      end

      test "includes the attached status html body in notification content", %{
        conn: conn,
        user: user
      } do
        liker = Bonfire.Me.Fake.fake_user!()
        html_body = "<p>Notification status body should be present</p>"

        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: html_body}},
            boundary: "public"
          )

        {:ok, _like} = Bonfire.Social.Likes.like(liker, post)

        response =
          conn
          |> get("/api/v1/notifications?limit=10")
          |> json_response(200)

        notification =
          Enum.find(response, fn notification ->
            notification["type"] == "favourite" &&
              get_in(notification, ["status", "id"]) == post.id
          end)

        assert notification
        assert get_in(notification, ["status", "content"]) =~ "Notification status body"
      end

      test "maps quote request notifications as quote notifications", %{
        conn: conn,
        user: user
      } do
        quoter = Bonfire.Me.Fake.fake_user!()

        {:ok, original_post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "Original post being quoted"}},
            boundary: "public"
          )

        {:ok, quote_post} =
          Bonfire.Posts.publish(
            current_user: quoter,
            post_attrs: %{post_content: %{html_body: "Quote request post"}},
            boundary: "public"
          )

        assert [_request] =
                 Bonfire.Social.Quotes.create_quote_requests(
                   quoter,
                   [original_post],
                   quote_post
                 )

        response =
          conn
          |> get("/api/v1/notifications?limit=10")
          |> json_response(200)

        assert Enum.any?(response, fn notification ->
                 notification["type"] == "quote" &&
                   notification["account"]["id"] == quoter.id &&
                   get_in(notification, ["status", "id"]) == quote_post.id
               end)
      end

      test "paginates across raw notification candidates filtered from the Mastodon response", %{
        conn: conn,
        user: user
      } do
        liker = Bonfire.Me.Fake.fake_user!()

        {:ok, older_post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "Older favourite notification"}},
            boundary: "public"
          )

        {:ok, _older_like} = Bonfire.Social.Likes.like(liker, older_post)

        {:ok, newer_post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "Newer favourite notification"}},
            boundary: "public"
          )

        {:ok, _newer_like} = Bonfire.Social.Likes.like(liker, newer_post)

        for i <- 1..6 do
          voter = Bonfire.Me.Fake.fake_user!()

          {:ok, question} =
            Bonfire.Poll.Fake.fake_question_with_choices(
              %{
                post_content: %{html_body: "Poll notification #{i}"},
                voting_dates: [DateTime.utc_now()]
              },
              [%{name: "A"}],
              current_user: user
            )

          [choice] = question.choices

          assert {:ok, _} =
                   Bonfire.Poll.Votes.vote(voter, question, [
                     %{choice_id: choice.id, weight: 1}
                   ])
        end

        first_page =
          conn
          |> get("/api/v1/notifications?limit=1&exclude_types%5B%5D=poll")
          |> json_response(200)

        assert [first_notification] = first_page
        assert first_notification["type"] == "favourite"
        assert get_in(first_notification, ["status", "id"]) == newer_post.id

        second_page =
          conn
          |> get(
            "/api/v1/notifications?limit=1&exclude_types%5B%5D=poll&max_id=#{first_notification["id"]}"
          )
          |> json_response(200)

        assert [second_notification] = second_page
        assert second_notification["type"] == "favourite"
        assert get_in(second_notification, ["status", "id"]) == older_post.id
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v1/notifications")
          |> json_response(401)

        assert response["error"]
      end
    end

    # Ice Cubes asks for the policy each time its notifications open; the `/notifications/:group_key` route caught the word "policy" and answered 501 (live testing L4, masto-live-fixes step 1)
    describe "GET /api/v2/notifications/policy" do
      test "answers a notification policy, not 501", %{conn: conn} do
        policy =
          conn
          |> get("/api/v2/notifications/policy")
          |> json_response(200)

        for key <-
              ~w(for_not_following for_not_followers for_new_accounts for_private_mentions for_limited_accounts) do
          assert policy[key] in ~w(accept filter drop), "#{key}: #{inspect(policy[key])}"
        end

        assert %{"pending_requests_count" => _, "pending_notifications_count" => _} =
                 policy["summary"]
      end

      # v1 is Mastodon 4.3's shape (booleans), v2 is 4.4's (`for_*`); both routes answered v2's (code review of masto-live-fixes)
      test "GET /api/v1/notifications/policy answers the v1 shape", %{conn: conn} do
        policy =
          conn
          |> get("/api/v1/notifications/policy")
          |> json_response(200)

        for key <-
              ~w(filter_not_following filter_not_followers filter_new_accounts filter_private_mentions) do
          assert is_boolean(policy[key]), "#{key}: #{inspect(policy[key])}"
        end

        refute Enum.any?(Map.keys(policy), &String.starts_with?(&1, "for_"))

        assert %{"pending_requests_count" => _, "pending_notifications_count" => _} =
                 policy["summary"]
      end

      test "a group key still answers 501", %{conn: conn} do
        assert conn
               |> get("/api/v2/notifications/ungrouped-#{Needle.ULID.generate()}")
               |> json_response(501)
      end
    end

    # the badge count apps show; both routes were caught by `/notifications/:group_key` and `/notifications/:id` (masto-live-fixes decision 4)
    describe "GET /api/v2/notifications/unread_count" do
      test "counts a notification the reader has not seen, in v2 and v1", %{
        conn: conn,
        user: user
      } do
        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "like me"}},
            boundary: "public"
          )

        {:ok, _} = Bonfire.Social.Likes.like(Bonfire.Me.Fake.fake_user!(), post)

        assert %{"count" => count} =
                 conn |> get("/api/v2/notifications/unread_count") |> json_response(200)

        assert count >= 1

        assert %{"count" => ^count} =
                 conn |> get("/api/v1/notifications/unread_count") |> json_response(200)
      end

      # the count stops at `limit`, in the query rather than after counting every unseen row (code review of masto-live-fixes)
      test "counts no further than limit", %{conn: conn, user: user} do
        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: user,
            post_attrs: %{post_content: %{html_body: "like me, three of you"}},
            boundary: "public"
          )

        for _ <- 1..3,
            do: {:ok, _} = Bonfire.Social.Likes.like(Bonfire.Me.Fake.fake_user!(), post)

        assert %{"count" => 2} =
                 conn |> get("/api/v2/notifications/unread_count?limit=2") |> json_response(200)

        assert %{"count" => count} =
                 conn |> get("/api/v2/notifications/unread_count") |> json_response(200)

        assert count >= 3
      end

      test "requires authentication" do
        assert unauthenticated_conn()
               |> get("/api/v2/notifications/unread_count")
               |> json_response(401)
      end
    end

    describe "notification mapper fallback status" do
      test "builds a valid mention notification when activity object is not preloaded", %{
        user: user
      } do
        subject = Bonfire.Me.Fake.fake_user!()
        activity_id = "01KS7CHQQ6Y8KQR9A7X4EBPJPM"
        object_id = "01KS62C1KD0B917AG5F0H0N7BP"

        # shaped as the notification list's GraphQL selection returns it: the subject, the object's content and the mentions on the activity itself
        activity = %{
          id: activity_id,
          subject_id: subject.id,
          object_id: object_id,
          verb_id: Bonfire.Boundaries.Verbs.get_id!(:create),
          subject: %{
            id: subject.id,
            character: %{username: subject.character.username},
            profile: %{name: subject.profile.name}
          },
          object_post_content: %{id: object_id, html_body: "Fallback status body"},
          mentions: [%{id: user.id, character: %{username: user.character.username}}]
        }

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
            current_user: user,
            # the caller names the type, as the notification list does
            notification_type: "mention"
          )

        status = notification["status"]

        assert notification["type"] == "mention"
        assert notification["account"]["id"] == subject.id
        assert status["id"] == object_id
        assert status["created_at"]
        assert status["uri"]
        assert status["url"] == status["uri"]
        assert {:ok, _} = Bonfire.API.MastoCompat.Schemas.Status.validate(status)
      end
    end

    # a notification's Mastodon type, named once for the list, push and streaming: a mention only when it names the reader, anything else that reached them a `status`
    describe "Mappers.Notification.type_for/2" do
      test "a create that doesn't name the reader is a status, not dropped", %{user: user} do
        activity = %{verb_id: Bonfire.Boundaries.Verbs.get_id!(:create), tags: []}

        assert Bonfire.API.MastoCompat.Mappers.Notification.type_for(activity, user) == "status"
      end

      test "a create that names the reader is a mention", %{user: user} do
        activity = %{verb_id: Bonfire.Boundaries.Verbs.get_id!(:create), tags: [%{id: user.id}]}

        assert Bonfire.API.MastoCompat.Mappers.Notification.type_for(activity, user) == "mention"
      end

      # Mastodon's `poll` means a poll ended, which a vote isn't
      test "a vote has no Mastodon type", %{user: user} do
        activity = %{verb_id: Bonfire.Boundaries.Verbs.get_id!(:vote)}

        assert is_nil(Bonfire.API.MastoCompat.Mappers.Notification.type_for(activity, user))
      end

      # read as a create, as a row carrying no verb is, so something that reached the reader without naming them: a `status`, as the list's Other category shows it
      test "a verb nobody declared is a status", %{user: user} do
        activity = %{verb_id: "VNKN0WNN0T1F1CAT10NVERB"}

        assert Bonfire.API.MastoCompat.Mappers.Notification.type_for(activity, user) == "status"
      end

      test "the mapper names no type itself: without one from its caller it drops the activity",
           %{user: user} do
        activity = %{
          id: "01KS7CHQQ6Y8KQR9A7X4EBPJPM",
          object_id: "01KS62C1KD0B917AG5F0H0N7BP",
          verb_id: Bonfire.Boundaries.Verbs.get_id!(:like)
        }

        assert is_nil(
                 Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
                   current_user: user
                 )
               )
      end
    end

    describe "a post that reaches the reader without naming them" do
      test "is a status in the notification list", %{conn: conn, user: user} do
        subject = Bonfire.Me.Fake.fake_user!()
        {:ok, _} = Bonfire.Notify.Bells.enable(user, subject)

        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: subject,
            post_attrs: %{post_content: %{html_body: "Plain public status"}},
            boundary: "public"
          )

        # the positive first: the bell put it in the reader's notifications
        assert Bonfire.Social.FeedLoader.feed_contains?(:notifications, post, current_user: user)

        notification =
          conn
          |> get("/api/v1/notifications")
          |> json_response(200)
          |> Enum.find(&(get_in(&1, ["status", "id"]) == post.id))

        assert %{"type" => "status"} = notification
      end
    end
  end
end
