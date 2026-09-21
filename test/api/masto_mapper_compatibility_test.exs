if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.MapperCompatibilityTest do
    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    alias Bonfire.API.MastoCompat.Mappers.{Account, MediaAttachment}

    doctest MediaAttachment, only: [normalize_duration: 1], import: true

    test "remote handles separate username from acct without changing local handles" do
      user = Bonfire.Me.Fake.fake_user!()

      for {username, acct} <- [
            {"by_caballero", "by_caballero@mastodon.social"},
            {"alice", "alice"}
          ] do
        actor = %{user | character: %{user.character | username: acct}}
        result = Account.from_user(actor, skip_expensive_stats: true)
        assert result["username"] == username
        assert result["acct"] == acct
      end
    end

    test "an explicit remote acct is preserved" do
      user = Bonfire.Me.Fake.fake_user!()

      character =
        user.character
        |> Map.from_struct()
        |> Map.merge(%{username: "alice", acct: "alice@remote.example"})

      result = Account.from_user(%{user | character: character}, skip_expensive_stats: true)
      assert result["username"] == "alice"
      assert result["acct"] == "alice@remote.example"
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
