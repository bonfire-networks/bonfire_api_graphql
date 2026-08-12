# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.CollapseErrorsTest do
  use ExUnit.Case, async: true

  # bucket this into the backend CI leg: bare `ExUnit.Case` skips the tag the extension case templates apply, so without it this also runs in the federation job catch-all
  @moduletag :backend

  alias Bonfire.API.GraphQL.Middleware.CollapseErrors

  @moduletag :graphql

  test "collapse renders plain string resolver errors without passing them through Bonfire.Fail" do
    assert [%{message: "At least one vote is required", status: 200}] =
             CollapseErrors.collapse(["At least one vote is required"])
  end
end
