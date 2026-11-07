# SPDX-License-Identifier: AGPL-3.0-only
# Always defined, like `Bonfire.API.MastoCompat.Test.MastoSchema`, which passes it to JSV. Implements the `JSV.FormatValidator` behaviour, not declared with `@behaviour` since `jsv` is a dev/test-only dependency, which Mix drops when compiling this as a dependency
defmodule Bonfire.API.MastoCompat.Test.MastoFormats do
  @moduledoc """
  The string formats used in the vendored Mastodon OpenAPI spec that JSV doesn't know (JSV refuses to build a schema with an unknown format), and `uri`, which accepts "" as Mastodon sends it.
  """

  # an ISO 639 language code, as Mastodon gives `language` and `locale`: two letters (ISO 639-1), or three for languages with no two-letter code, optionally with a region or script (eg. `zh-TW`)
  @language ~r/\A[a-z]{2,3}([-_][A-Za-z0-9]+)*\z/
  # OAuth scopes, space-separated (eg. `read write:statuses`)
  @scopes ~r/\A[a-z:]+( [a-z:]+)*\z/

  def supported_formats, do: ["iso-639-1", "scopes", "binary", "uri"]

  def applies_to_type?(_format, data), do: is_binary(data)

  # Mastodon sends "" for an absent URL in fields the spec marks as `uri` (eg. a PreviewCard's `author_url`, `provider_url` and `embed_url`, which are `default: "", null: false` columns), so clients handle it. Any other value gets JSV's own `uri` check
  def validate_cast("uri", ""), do: {:ok, ""}
  def validate_cast("uri", data), do: JSV.FormatValidator.Default.validate_cast("uri", data)

  def validate_cast("iso-639-1", data) do
    if Regex.match?(@language, data),
      do: {:ok, data},
      else: {:error, "not an ISO 639 language code"}
  end

  def validate_cast("scopes", data) do
    if Regex.match?(@scopes, data),
      do: {:ok, data},
      else: {:error, "not space-separated OAuth scopes"}
  end

  # file uploads, in request bodies only: any content
  def validate_cast("binary", data), do: {:ok, data}
end
