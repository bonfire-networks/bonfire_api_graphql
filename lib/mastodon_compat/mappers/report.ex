if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.Mappers.Report do
    @moduledoc """
    Transforms Bonfire Flag objects to Mastodon Report format.

    This module handles the conversion of Bonfire's internal Flag structure
    to the Mastodon-compatible Report entity format.
    """

    use Bonfire.Common.Utils
    import Untangle

    alias Bonfire.API.MastoCompat.{Helpers, Schemas, Mappers}
    alias Bonfire.Common.DatesTimes

    @doc """
    Transform a Bonfire Flag into a Mastodon Report.

    Returns nil if the flag is nil or invalid.

    ## Options

    - `:current_user` - Current user context
    - `:skip_expensive_stats` - Skip expensive account stats (default: true for reports)

    ## Examples

        iex> from_flag(%Bonfire.Data.Social.Flag{...})
        %{"id" => "123", "category" => "other", ...}

        iex> from_flag(nil)
        nil
    """
    def from_flag(flag, opts \\ [])

    def from_flag(nil, _opts), do: nil

    def from_flag(flag, opts) when is_map(flag) do
      case build_report(flag, opts) do
        %{"id" => id, "target_account" => account} = report
        when not is_nil(id) and not is_nil(account) ->
          report

        other ->
          warn(other, "Failed to build valid report - missing required fields")
          nil
      end
    end

    def from_flag(_, _opts), do: nil

    defp build_report(flag, opts) do
      edge = Helpers.get_field(flag, :edge)
      flagged = Helpers.get_field(edge, :object)
      target_account = extract_target_account(flagged, opts)

      named = Helpers.get_field(flag, :named)
      comment = Helpers.get_field(named, :name) || ""

      status_ids = extract_status_ids(flagged)

      # ULID contains timestamp
      flag_id = Helpers.get_field(flag, :id) || Helpers.get_field(edge, :id)
      created_at = extract_created_at(flag_id)

      Schemas.Report.new(%{
        "id" => Helpers.to_string_safe(flag_id),
        "action_taken" => false,
        "action_taken_at" => nil,
        "category" => "other",
        "comment" => comment,
        "forwarded" => false,
        "created_at" => created_at,
        "status_ids" => status_ids,
        "rule_ids" => nil,
        "target_account" => target_account
      })
    end

    defp extract_target_account(nil, _opts), do: nil

    defp extract_target_account(flagged, opts) do
      # Determine if flagged object is a User or content using Bonfire's type system
      object_type = Bonfire.Common.Types.object_type(flagged)

      user =
        if object_type in [Bonfire.Data.Identity.User, Bonfire.Data.Identity.Character] do
          # Flagged object IS a user
          flagged
        else
          # For content, get the creator
          created = Helpers.get_field(flagged, :created)
          Helpers.get_field(created, :creator)
        end

      debug(user, "target user for report")

      # Skip expensive stats for report listing performance
      account_opts = Keyword.put_new(opts, :skip_expensive_stats, true)
      Mappers.Account.from_user(user, account_opts)
    end

    defp extract_status_ids(nil), do: nil

    defp extract_status_ids(flagged) do
      object_type = Bonfire.Common.Types.object_type(flagged)

      if object_type in [Bonfire.Data.Identity.User, Bonfire.Data.Identity.Character] do
        # If flagging a user, no status IDs
        nil
      else
        # If flagging content, include its ID as a status
        case Helpers.get_field(flagged, :id) do
          nil -> nil
          id -> [to_string(id)]
        end
      end
    end

    defp extract_created_at(nil), do: nil

    defp extract_created_at(id) when is_binary(id) do
      case DatesTimes.date_from_pointer(id) do
        %DateTime{} = dt -> DateTime.to_iso8601(dt)
        _ -> DateTime.utc_now() |> DateTime.to_iso8601()
      end
    end

    defp extract_created_at(_), do: nil
  end
end
