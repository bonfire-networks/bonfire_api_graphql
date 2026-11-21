# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.MastoCompat.Test.MastoClients do
  @moduledoc """
  What each Mastodon client app sends at login and needs back, read from the app's source (link per profile), for tests that replay an app against the API.
  """
  @scopes "read write follow push"

  @profiles [
    %{
      id: :phanpy,
      # https://github.com/cheeaun/phanpy
      register: %{encoding: :form, redirect_uri: "https://phanpy.social"},
      token: :form,
      preflight: [],
      non_null: %{}
    },
    %{
      id: :elk,
      # https://github.com/elk-zone/elk
      register: %{
        encoding: :json,
        redirect_uri: "https://elk.zone/api/localhost/oauth/https%3A%2F%2Felk.zone"
      },
      token: :json,
      preflight: [],
      non_null: %{}
    },
    %{
      id: :tusky,
      # https://codeberg.org/tusky/Tusky/src/branch/main/app/src/main/java/com/keylesspalace/tusky/entity
      register: %{encoding: :form, redirect_uri: "oauth2redirect://com.keylesspalace.tusky/"},
      token: :form,
      preflight: [],
      non_null: %{
        "Status" =>
          ~w(id account content created_at emojis reblogs_count favourites_count replies_count sensitive spoiler_text visibility media_attachments mentions),
        "Account" => ~w(id username acct created_at note url avatar header),
        "Notification" => ~w(type id account)
      }
    },
    %{
      id: :ice_cubes,
      # https://github.com/Dimillian/IceCubesApp/tree/main/Packages/Models/Sources/Models
      register: %{encoding: :json, redirect_uri: "icecubesapp://"},
      token: :json,
      preflight: [{"/api/v2/instance", "InstanceV2"}],
      non_null: %{
        "Status" =>
          ~w(id content account created_at media_attachments mentions replies_count reblogs_count favourites_count emojis visibility spoiler_text sensitive tags),
        "Account" => ~w(avatar header fields locked emojis bot),
        "InstanceV2" => ~w(title domain version thumbnail registrations.enabled contact.email)
      },
      urls: %{"Account" => ~w(avatar header)},
      enums: %{"Status" => %{"visibility" => ~w(public unlisted private direct)}}
    },
    %{
      id: :mastodon_ios,
      # https://github.com/mastodon/mastodon-ios/tree/develop/MastodonSDK/Sources/MastodonSDK/Entity
      register: %{encoding: :json, redirect_uri: "mastodon://joinmastodon.org/oauth"},
      token: :form,
      preflight: [],
      non_null: %{
        "Status" =>
          ~w(id uri created_at account mentions tags emojis reblogs_count favourites_count),
        "Account" =>
          ~w(id username acct url display_name note avatar header locked emojis created_at statuses_count followers_count following_count),
        "Notification" => ~w(id type created_at account)
      }
    },
    %{
      id: :mastodon_android,
      # https://github.com/mastodon/mastodon-android/tree/master/mastodon/src/main/java/org/joinmastodon/android/model
      register: %{encoding: :json, redirect_uri: "org.joinmastodon.android-auth://callback"},
      token: :json,
      preflight: [{"/api/v2/instance", "InstanceV2"}],
      non_null: %{
        "Status" =>
          ~w(id uri created_at account content visibility spoiler_text media_attachments mentions tags emojis),
        "Account" => ~w(id username acct url display_name note avatar header created_at),
        "InstanceV2" => ~w(title description version languages domain registrations),
        "Notification" => ~w(id created_at)
      },
      enums: %{"Status" => %{"visibility" => ~w(public unlisted private direct)}}
    },
    %{
      id: :ivory,
      # closed source; redirect URI from extensions/bonfire_open_id/lib/provider/client_apps.ex:327, streaming URL from issue #916
      register: %{encoding: :form, redirect_uri: "com.tapbots.Ivory.19300:/request_token"},
      token: :form,
      preflight: [],
      non_null: %{"InstanceV1" => ~w(urls.streaming_api)}
    }
  ]

  # entities nested in an entity, checked with the same profile
  @nested %{
    "Status" => [{"account", "Account"}, {"reblog", "Status"}],
    "Notification" => [{"account", "Account"}, {"status", "Status"}]
  }

  def profiles, do: @profiles
  def scopes, do: @scopes

  @doc "Every field some client needs non-null in `entity`: what `MastoSchema` checks on top of the spec."
  def non_null(entity) do
    @profiles |> Enum.flat_map(&Map.get(&1.non_null, entity, [])) |> Enum.uniq()
  end

  @doc "The ways `json` (one `entity`) breaks `profile`'s rules, as a list of messages; empty when it's fine."
  def problems(profile, entity, json, prefix \\ "")

  def problems(profile, entity, json, prefix) when is_map(json) do
    nulls =
      for field <- Map.get(profile.non_null, entity, []),
          is_nil(get_in(json, String.split(field, "."))),
          do: "#{prefix}#{field} is null or missing"

    urls =
      for field <- Map.get(profile[:urls] || %{}, entity, []),
          value = json[field],
          not (is_binary(value) and String.starts_with?(value, ["http://", "https://"])),
          do: "#{prefix}#{field} is not an absolute URL: #{inspect(value)}"

    enums =
      for {field, allowed} <- Map.get(profile[:enums] || %{}, entity, %{}),
          json[field] not in allowed,
          do: "#{prefix}#{field} is #{inspect(json[field])}, not one of #{inspect(allowed)}"

    nested =
      for {field, nested_entity} <- Map.get(@nested, entity, []),
          problem <- problems(profile, nested_entity, json[field], "#{prefix}#{field}."),
          do: problem

    nulls ++ urls ++ enums ++ nested
  end

  def problems(_profile, _entity, _not_a_map, _prefix), do: []
end
