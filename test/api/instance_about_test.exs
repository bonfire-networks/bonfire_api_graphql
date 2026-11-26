# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoApi.InstanceAboutTest do
  @moduledoc """
  What a Mastodon app shows under "About this server": the instance's rules (in `/api/v1/instance` and `/api/v2/instance`) and its longer description (`/api/v1/instance/extended_description`). Bonfire sent no rules and had no extended description, so Mastodon iOS showed only the short description (masto-instance-about).

  Not async: the tests change the instance's rules and code of conduct.

  Run with: just test extensions/bonfire_api_graphql/test/api/instance_about_test.exs
  """

  use Bonfire.API.MastoApiCase, async: false
  use Bonfire.Common.Config
  use Bonfire.Common.Settings

  @moduletag :masto_api

  @template [
    behavior: [
      name: "Behavior",
      sections: [
        civility: [name: "Civility", rules: [be_respectful: %{name: "Be respectful"}]],
        spam: [name: "Spam", rules: [no_spam: %{name: "No spam", has_qualifier: true}]]
      ]
    ]
  ]

  describe "rules" do
    setup do
      Settings.put([:bonfire_community_rules, :template_rules], @template,
        scope: :instance,
        skip_boundary_check: true
      )

      {:ok, _} =
        Bonfire.CommunityRules.save_rules(Settings.instance_scope(), %{
          "civility" => %{"be_respectful" => %{}},
          "spam" => %{"no_spam" => %{"qualifier" => "no"}}
        })

      :ok
    end

    # numbered in the order /about shows them; the qualifier, when the rule has one, is the hint (decisions 2 and 3)
    test "the instance's chosen rules, numbered, with the qualifier as hint", %{conn: conn} do
      expected = [
        %{"id" => "1", "text" => "Be respectful", "hint" => ""},
        %{"id" => "2", "text" => "No spam", "hint" => "Not allowed"}
      ]

      assert get_json(conn, "/api/v2/instance")["rules"] == expected
      assert get_json(conn, "/api/v1/instance")["rules"] == expected
    end
  end

  describe "GET /api/v1/instance/extended_description" do
    setup do
      previous = Config.get([:terms, :conduct])
      on_exit(fn -> Config.put([:terms, :conduct], previous) end)
      :ok
    end

    test "is the code of conduct as HTML", %{conn: conn} do
      Config.put([:terms, :conduct], "Be kind. No **harassment**.")

      response = get_json(conn, "/api/v1/instance/extended_description")

      assert response["content"] =~ "<strong>harassment</strong>"
      assert Map.has_key?(response, "updated_at")
    end

    # the same text /conduct shows when the operators wrote none
    test "says so when the instance has no code of conduct", %{conn: conn} do
      Config.put([:terms, :conduct], nil)

      assert get_json(conn, "/api/v1/instance/extended_description")["content"] =~
               "have not yet added a code of conduct"
    end
  end

  # as in `instance_guest_test.exs`
  defp get_json(conn, path) do
    conn
    |> put_req_header("accept", "application/json")
    |> get(path)
    |> json_response(200)
  end
end
