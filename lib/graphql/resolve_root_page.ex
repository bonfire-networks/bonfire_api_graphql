# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.GraphQL.ResolveRootPage do
  @moduledoc """
  Encapsulates the flow of resolving a page in the absence of parents.
  """

  @enforce_keys [:module, :fetcher, :page_opts, :info]
  defstruct [
    :module,
    :fetcher,
    :page_opts,
    :info,
    cursor_validators: [&Pointers.ULID.cast/1],
    paging_opts: %{default_limit: 10, max_limit: 100}
  ]

  alias Bonfire.GraphQL
  alias Bonfire.GraphQL.ResolveRootPage
  alias Bonfire.GraphQL

  def run(%ResolveRootPage{
        module: module,
        fetcher: fetcher,
        page_opts: page_opts,
        info: info,
        paging_opts: opts,
        cursor_validators: validators
      }) do

    with {:ok, page_opts_to_fetch} <- GraphQL.full_page_opts(page_opts, validators, opts) do

      info_to_fetch = Map.take(info, [:context])
        |> Map.put(:data_filters,
            Map.drop(page_opts, [:limit, :before, :after])
          ) #|> IO.inspect

      apply(module, fetcher, [page_opts_to_fetch, info_to_fetch])
    end
  end
end
