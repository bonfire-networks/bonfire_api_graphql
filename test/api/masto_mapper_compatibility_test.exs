if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.MapperCompatibilityTest do
    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    alias Bonfire.API.MastoCompat.Mappers.{Account, MediaAttachment}

    doctest MediaAttachment, only: [normalize_duration: 1], import: true
    # Mastodon's notification type names and our atoms for them, read from config
    doctest Bonfire.API.MastoCompat.Schemas.Notification,
      only: [type_atom: 1, type_name: 1],
      import: true

    test "remote handles separate username from acct without changing local handles" do
      user = Bonfire.Me.Fake.fake_user!()

      for {username, acct} <- [
            {"by_caballero", "by_caballero@mastodon.social"},
            {"alice", "alice"}
          ] do
        # GraphQL-shaped input, the only shape the mapper reads (unit 4)
        actor = %{id: user.id, character: %{username: acct}, profile: %{}}
        result = Account.from_user(actor)
        assert result["username"] == username
        assert result["acct"] == acct
      end
    end

    test "an explicit remote acct is preserved" do
      user = Bonfire.Me.Fake.fake_user!()

      # GraphQL-shaped input, the only shape the mapper reads (unit 4)
      input = %{
        id: user.id,
        character: %{username: "alice", acct: "alice@remote.example"},
        profile: %{}
      }

      result = Account.from_user(input)
      assert result["username"] == "alice"
      assert result["acct"] == "alice@remote.example"
    end

    describe "pure: an atom-key GraphQL account in, a Mastodon account out, no query" do
      # the shape `Fragments.account_fields` selects (team-docs/plans/masto-pure-mappers.md, unit 2)
      defp graphql_account(user, extra \\ %{}) do
        Map.merge(
          %{
            id: user.id,
            created_at: "2026-11-01T10:00:00Z",
            profile: %{
              avatar: "/images/me.png",
              avatar_static: "/images/me.png",
              header: "/images/my-header.png",
              header_static: "/images/my-header.png",
              display_name: "Alice",
              note: "Hello",
              website: nil
            },
            character: %{
              username: "alice",
              acct: "alice",
              url: "http://localhost:4000/pub/actors/alice",
              peered: nil
            }
          },
          extra
        )
      end

      test "counts come from the input, and nothing is queried" do
        user = Bonfire.Me.Fake.fake_user!()

        input =
          graphql_account(user, %{
            followers_count: 3,
            following_count: 4,
            statuses_count: 5,
            last_post_at: "2026-11-18T09:00:00Z"
          })

        {account, queries} =
          Bonfire.Common.Testing.count_queries(fn -> Account.from_user(input) end)

        assert queries == 0
        assert account["id"] == user.id
        assert account["username"] == "alice"
        assert account["url"] == "http://localhost:4000/pub/actors/alice"
        assert account["uri"] == "http://localhost:4000/pub/actors/alice"
        assert account["display_name"] == "Alice"
        assert account["note"] =~ "Hello"
        assert account["created_at"] == "2026-11-01T10:00:00Z"
        # the date of the newest post, from the input, not the creation date (masto-live-fixes step 4)
        assert account["last_status_at"] == "2026-11-18"

        assert {account["statuses_count"], account["followers_count"], account["following_count"]} ==
                 {5, 3, 4}
      end

      test "counts not selected are 0, and nothing is queried" do
        user = Bonfire.Me.Fake.fake_user!()

        {account, queries} =
          Bonfire.Common.Testing.count_queries(fn -> Account.from_user(graphql_account(user)) end)

        assert queries == 0

        assert {account["statuses_count"], account["followers_count"], account["following_count"]} ==
                 {0, 0, 0}

        # not selected: null, as Mastodon sends for an account that never posted (masto-live-fixes step 4)
        assert account["last_status_at"] == nil
      end

      test "a struct is not read: nil, and nothing is queried" do
        user = Bonfire.Me.Fake.fake_user!()

        {account, queries} =
          Bonfire.Common.Testing.count_queries(fn -> Account.from_user(user) end)

        assert account == nil
        assert queries == 0
      end

      test "a struct that is not an account (a post as subject) gives nil without a warning" do
        log =
          ExUnit.CaptureLog.capture_log([level: :warning], fn ->
            assert Account.from_user(%Bonfire.Data.Social.Post{id: Needle.UID.generate()}) == nil
          end)

        refute log =~ "reads GraphQL output"
      end

      test "a group struct warns, as a user struct does" do
        log =
          ExUnit.CaptureLog.capture_log([level: :warning], fn ->
            group = %Bonfire.Classify.Category{id: Needle.UID.generate(), type: :group}
            assert Account.from_user(group) == nil
          end)

        assert log =~ "reads GraphQL output"
      end

      test "the reader's own account takes follow_requests_count from the input" do
        user = Bonfire.Me.Fake.fake_user!()
        input = graphql_account(user, %{follow_requests_count: 2})

        {account, queries} =
          Bonfire.Common.Testing.count_queries(fn ->
            Account.from_user(input, include_source: true)
          end)

        assert queries == 0
        assert account["source"]["follow_requests_count"] == 2
        assert account["source"]["note"] == "Hello"
      end
    end

    test "audio and video metadata expose numeric seconds through JSON" do
      for type <- ["audio/ogg", "video/mp4"],
          {duration, expected} <- [
            {"PT253.47S", 253.47},
            {"PT1H2M3.5S", 3723.5},
            {"P1DT2H", 93_600.0},
            {"PT0S", 0.0},
            {"253.47", 253.47},
            {253.47, 253.47},
            {0, 0}
          ] do
        attachment =
          media(type, duration)
          |> MediaAttachment.from_media()
          |> Jason.encode!()
          |> Jason.decode!()

        assert attachment["meta"]["duration"] == expected
        assert is_number(attachment["meta"]["duration"])
      end
    end

    test "invalid durations are omitted and images do not gain duration metadata" do
      for duration <- [nil, "", "P", "PT", "P1DT", "P1M", "PT-2S", "12junk", "-1", -1, %{}] do
        attachment = media("video/mp4", duration) |> MediaAttachment.from_media()
        refute Map.has_key?(attachment["meta"], "duration")
      end

      attachment = media("image/png", "PT2S") |> MediaAttachment.from_media()
      refute Map.has_key?(attachment["meta"], "duration")
    end

    test "duration can also come from the media field" do
      attachment =
        media("video/mp4", nil) |> Map.put(:duration, "PT2M") |> MediaAttachment.from_media()

      assert attachment["meta"]["duration"] == 120.0
    end

    defp media(type, duration) do
      %{
        id: "media-regression",
        media_type: type,
        url: "https://remote.example/media",
        preview_url: "https://remote.example/preview",
        metadata: %{"duration" => duration}
      }
    end
  end
end
