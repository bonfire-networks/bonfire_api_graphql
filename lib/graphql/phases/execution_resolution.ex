# this code is based on Absinthe library: Absinthe.Phase.Document.Execution.Resolution
defmodule Bonfire.API.GraphQL.Phase.ExecutionResolution do
  @moduledoc false

  # Runs resolution functions in a blueprint.
  #
  # Blueprint results are placed under `blueprint.result.execution`. This is
  # because the results form basically a new tree from the original blueprint.

  # alias Absinthe.{Blueprint, Phase}
  # alias Blueprint.{Result, Execution}

  use Absinthe.Phase

  import Untangle

  alias Bonfire.Common.Errors

  def run(bp_root, options \\ []) do
    Absinthe.Phase.Document.Execution.Resolution.run(bp_root, options)
  rescue
    error in Ecto.Query.CastError ->
      debug_exception(
        "You seem to have provided an incorrect data type (eg. an invalid ID)",
        error,
        __STACKTRACE__,
        :error
      )

    error in Ecto.ConstraintError ->
      debug_exception(
        "You seem to be referencing an invalid object ID, or trying to insert duplicated data",
        error,
        __STACKTRACE__,
        :error
      )

    error ->
      debug_exception(
        "The API encountered an exceptional error",
        error,
        __STACKTRACE__,
        :error
      )
  catch
    error ->
      debug_exception(
        "The API was thrown an exceptional error",
        error,
        __STACKTRACE__,
        :error
      )
  end

  defp debug_exception(msg, exception, stacktrace, kind) do
    debug_log(msg, exception, stacktrace, kind)

    if env() == :dev or System.get_env("SENTRY_ENV") == "next" do
      {:error,
       msg <>
         ": " <>
         Errors.format_banner(kind, exception, stacktrace) <>
         " -- Details: " <>
         Untangle.format_stacktrace(stacktrace)}
    else
      {:error, msg}
    end
  end

  defp env() do
    Bonfire.Common.Config.env()
  end

  defp debug_log(msg, exception, stacktrace, kind) do
    error(msg)
    error(Errors.format_banner(kind, exception, stacktrace))
    IO.puts(Exception.format_exit(exception))
    IO.puts(Untangle.format_stacktrace(stacktrace))

    if Bonfire.Common.Errors.maybe_sentry_dsn(),
      do:
        Sentry.capture_exception(
          exception,
          stacktrace: stacktrace
        )
  end
end
