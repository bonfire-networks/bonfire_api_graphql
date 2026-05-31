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

    describe "GET /api/v2/notifications" do
      test "returns 200 with list", %{conn: conn} do
        response =
          conn
          |> get("/api/v2/notifications")
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
          |> get("/api/v2/notifications?limit=30")
          |> json_response(200)

        ordinary_post_ids = [own_post.id, unrelated_post.id]

        leaked_status_notifications =
          Enum.filter(response, fn notification ->
            notification["type"] == "status" &&
              get_in(notification, ["status", "id"]) in ordinary_post_ids
          end)

        assert leaked_status_notifications == []
      end

      test "maps poll vote notifications as poll notifications", %{
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
          |> get("/api/v2/notifications?limit=10")
          |> json_response(200)

        assert Enum.any?(response, fn notification ->
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
          |> get("/api/v2/notifications?limit=10")
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
          |> get("/api/v2/notifications?limit=10")
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
          |> get("/api/v2/notifications?limit=1&exclude_types%5B%5D=poll")
          |> json_response(200)

        assert [first_notification] = first_page
        assert first_notification["type"] == "favourite"
        assert get_in(first_notification, ["status", "id"]) == newer_post.id

        second_page =
          conn
          |> get(
            "/api/v2/notifications?limit=1&exclude_types%5B%5D=poll&max_id=#{first_notification["id"]}"
          )
          |> json_response(200)

        assert [second_notification] = second_page
        assert second_notification["type"] == "favourite"
        assert get_in(second_notification, ["status", "id"]) == older_post.id
      end

      test "requires authentication" do
        response =
          unauthenticated_conn()
          |> get("/api/v2/notifications")
          |> json_response(401)

        assert response["error"]
      end
    end

    describe "notification mapper fallback status" do
      test "builds a valid mention notification when activity object is not preloaded", %{
        user: user
      } do
        subject = Bonfire.Me.Fake.fake_user!()
        activity_id = "01KS7CHQQ6Y8KQR9A7X4EBPJPM"
        object_id = "01KS62C1KD0B917AG5F0H0N7BP"

        activity = %{
          id: activity_id,
          subject_id: subject.id,
          object_id: object_id,
          verb_id: Bonfire.Boundaries.Verbs.get_id!(:create)
        }

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
            current_user: user,
            subjects_by_id: %{subject.id => subject},
            post_content_by_id: %{
              object_id => %{id: object_id, html_body: "Fallback status body"}
            },
            mentions_by_object: %{object_id => [%{tag_id: user.id}]}
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

      test "drops create activities that do not mention the current user", %{user: user} do
        subject = Bonfire.Me.Fake.fake_user!()
        activity_id = "01KS7CHQQ6Y8KQR9A7X4EBPJPM"
        object_id = "01KS62C1KD0B917AG5F0H0N7BP"

        activity = %{
          id: activity_id,
          subject_id: subject.id,
          object_id: object_id,
          verb_id: Bonfire.Boundaries.Verbs.get_id!(:create)
        }

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
            current_user: user,
            subjects_by_id: %{subject.id => subject},
            post_content_by_id: %{
              object_id => %{id: object_id, html_body: "Fallback status body"}
            },
            mentions_by_object: %{}
          )

        assert is_nil(notification)
      end

      test "maps vote activities to poll notifications", %{user: user} do
        subject = Bonfire.Me.Fake.fake_user!()
        activity_id = "01KS7CHQQ6Y8KQR9A7X4EBPJPM"
        object_id = "01KS62C1KD0B917AG5F0H0N7BP"

        activity = %{
          id: activity_id,
          subject_id: subject.id,
          object_id: object_id,
          verb_id: Bonfire.Boundaries.Verbs.get_id!(:vote)
        }

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
            current_user: user,
            subjects_by_id: %{subject.id => subject},
            post_content_by_id: %{
              object_id => %{id: object_id, html_body: "Poll status body"}
            },
            mentions_by_object: %{}
          )

        assert notification["type"] == "poll"
        assert notification["status"]["id"] == object_id
      end

      test "drops a real published post activity when it does not mention the current user", %{
        user: user
      } do
        subject = Bonfire.Me.Fake.fake_user!()

        {:ok, post} =
          Bonfire.Posts.publish(
            current_user: subject,
            post_attrs: %{post_content: %{html_body: "Plain public status"}},
            boundary: "public"
          )

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(post.activity,
            current_user: user,
            subjects_by_id: %{subject.id => subject},
            post_content_by_id: %{
              post.id => post.post_content
            },
            mentions_by_object: %{}
          )

        assert is_nil(notification)
      end

      test "drops unsupported internal notification verbs", %{user: user} do
        subject = Bonfire.Me.Fake.fake_user!()
        activity_id = "01KS7CHDPT6MFWEJTK92NWBC0K"
        object_id = "01KS63DWB94WNB1RYZKGA9QP98"

        activity = %{
          id: activity_id,
          subject_id: subject.id,
          object_id: object_id,
          verb_id: "VNKN0WNN0T1F1CAT10NVERB"
        }

        notification =
          Bonfire.API.MastoCompat.Mappers.Notification.from_activity(activity,
            current_user: user,
            subjects_by_id: %{subject.id => subject},
            post_content_by_id: %{
              object_id => %{id: object_id, html_body: "Fallback status body"}
            },
            mentions_by_object: %{}
          )

        assert is_nil(notification)
      end
    end
  end
end
