if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Test.MastoSchemaTest do
    @moduledoc """
    The checks behind `assert_masto_entity/2`: an entity must match its schema in the vendored Mastodon OpenAPI spec, and the fields that clients need must not be null.
    """
    use ExUnit.Case, async: true

    # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag the extension case templates apply, so without it this also runs in the federation job catch-all
    @moduletag :backend

    import Bonfire.API.MastoCompat.Test.MastoSchema

    # The Status example from the Mastodon documentation, updated to what Mastodon sends today: the Account fields `uri` and `indexable` and the card's `authors` added (the spec requires them, the example predates them), and `last_status_at` a date, not a datetime (Mastodon's `REST::AccountSerializer#last_status_at` sends `to_date.iso8601`)
    @status_example Path.join(__DIR__, "../fixtures/masto/status_example.json")
                    |> File.read!()
                    |> Jason.decode!()

    test "a valid Status passes" do
      assert assert_masto_entity(@status_example, "Status") == @status_example
    end

    test "a Status with no account fails, naming the field" do
      status = Map.delete(@status_example, "account")

      error = assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(status, "Status") end
      assert error.message =~ "account"
    end

    test "a Status with a count as a string fails, naming the field" do
      status = Map.put(@status_example, "favourites_count", "11")

      error = assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(status, "Status") end
      assert error.message =~ "favourites_count"
    end

    test "a Status with a null spoiler_text fails, naming the field" do
      status = Map.put(@status_example, "spoiler_text", nil)

      error = assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(status, "Status") end
      assert error.message =~ "spoiler_text"
    end

    test "a card URL that is not a URI fails, though an empty one passes as Mastodon sends it" do
      assert @status_example["card"]["author_url"] == ""

      status = put_in(@status_example, ["card", "author_url"], "not a uri")

      error = assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(status, "Status") end
      assert error.message =~ "author_url"
    end

    test "an Account with a null url passes the spec but fails the client checks" do
      account = Map.put(@status_example["account"], "url", nil)

      assert {:ok, _} = validate_masto_schema(account, "Account")

      error =
        assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(account, "Account") end

      assert error.message =~ "url"
    end

    describe "corrections to the spec" do
      @group %{
        "group_key" => "favourite-1",
        "notifications_count" => 1,
        "sample_account_ids" => ["1"],
        "type" => "favourite"
      }

      test "a NotificationGroup's most_recent_notification_id is a string, as Mastodon sends it" do
        assert {:ok, _} =
                 validate_masto_schema(
                   Map.put(@group, "most_recent_notification_id", "123"),
                   "NotificationGroup"
                 )

        assert {:error, _} =
                 validate_masto_schema(
                   Map.put(@group, "most_recent_notification_id", 123),
                   "NotificationGroup"
                 )
      end

      test "a WebPushSubscription's id can be a string, as Bonfire's ids are" do
        alerts =
          Map.new(
            ~w(admin.report admin.sign_up favourite follow follow_request mention poll reblog status update),
            &{&1, true}
          )

        subscription = %{
          "id" => "01M6VGC91P35QJ06S8KN2GQ4VM",
          "endpoint" => "https://push.example.local/1",
          "server_key" => "key",
          "alerts" => alerts
        }

        assert {:ok, _} = validate_masto_schema(subscription, "WebPushSubscription")

        assert {:ok, _} =
                 validate_masto_schema(%{subscription | "id" => 1}, "WebPushSubscription")
      end
    end

    describe "assert_masto_response/3, by route" do
      test "checks a single entity response against the route's schema" do
        assert assert_masto_response(@status_example, "GET", "/api/v1/statuses/:id") ==
                 @status_example

        error =
          assert_raise ExUnit.AssertionError, fn ->
            assert_masto_response(
              Map.delete(@status_example, "account"),
              "GET",
              "/api/v1/statuses/:id"
            )
          end

        assert error.message =~ "account"
      end

      test "matches a route whatever its parameters are named" do
        account = @status_example["account"]

        # the spec names this `{id}`, the route could say `:account_id`
        assert assert_masto_response(account, "GET", "/api/v1/accounts/:account_id") == account
      end

      test "checks each item of a list response, with the client checks" do
        assert assert_masto_response([@status_example], "GET", "/api/v1/timelines/home") ==
                 [@status_example]

        bad = put_in(@status_example, ["account", "url"], nil)

        error =
          assert_raise ExUnit.AssertionError, fn ->
            assert_masto_response([@status_example, bad], "GET", "/api/v1/timelines/home")
          end

        assert error.message =~ "1.account.url"
      end

      test "skips a route the spec doesn't have" do
        assert assert_masto_response(%{"anything" => 1}, "GET", "/api/v1-bonfire/groups") ==
                 :no_schema
      end
    end

    test "a Status whose nested Account has a null url fails the client checks" do
      status = put_in(@status_example, ["account", "url"], nil)

      error = assert_raise ExUnit.AssertionError, fn -> assert_masto_entity(status, "Status") end
      assert error.message =~ "account.url"
    end
  end
end
