if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.NotificationContentTest do
    use Bonfire.API.MastoApiCase, async: false

    @moduletag :masto_api

    alias Bonfire.API.MastoCompat.Mappers.Notification

    # Post bodies are stored as Markdown, so a status built straight from the stored body must render it to HTML like `Mappers.Status` does
    test "a notification status built from the stored body is rendered and sanitized" do
      user = Bonfire.Me.Fake.fake_user!()
      object_id = Needle.UID.generate()

      activity = %{
        id: Needle.UID.generate(),
        object_id: object_id,
        subject: user,
        object_post_content: %{html_body: "> quoted\n\n**bold** <img src=x onerror=alert(1)>"}
      }

      content =
        Notification.from_activity(activity, notification_type: "mention", subject: user)
        |> get_in(["status", "content"])

      assert content =~ "<blockquote>"
      assert content =~ "<strong>bold</strong>"
      refute content =~ "onerror"
    end
  end
end
