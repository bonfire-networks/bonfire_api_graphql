# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.Middleware.CollapseErrorsTest do
  use ExUnit.Case, async: true

  alias Bonfire.API.GraphQL.Middleware.CollapseErrors

  @moduletag :graphql

  test "collapse renders plain string resolver errors without passing them through Bonfire.Fail" do
    assert [%{message: "At least one vote is required", status: 200}] =
             CollapseErrors.collapse(["At least one vote is required"])
  end
end
