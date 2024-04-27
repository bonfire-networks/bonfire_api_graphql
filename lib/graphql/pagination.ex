defmodule Bonfire.API.GraphQL.Pagination do
  import Bonfire.Common.Config, only: [repo: 0]
  import Untangle

  def pagination_args_filter(args) do
    # {pagination_args, filters} = 
    args
    |> Keyword.new()
    |> Keyword.split([:after, :before, :first, :last])
  end

  def connection_paginate(list, args, opts \\ [])

  def connection_paginate(
        %{
          edges: edges,
          page_info:
            %{
              end_cursor: end_cursor,
              start_cursor: start_cursor,
              # page_count: page_count, limit: limit, 
              cursor_for_record_fun: cursor_for_record_fun
            } = page_info
        },
        _args,
        opts
      ) do
    # IO.inspect(page_info)
    # best option, since doesn't use offset
    # Absinthe.Relay.Connection.from_slice(edges, end_cursor)
    {:ok,
     %{
       edges:
         build_edges(edges, Keyword.put(opts, :cursor_for_record_fun, cursor_for_record_fun)),
       page_info:
         Map.merge(page_info, %{
           # page_count == limit, 
           has_next_page: not is_nil(end_cursor),
           has_previous_page: not is_nil(start_cursor)
         })
     }}
  end

  def connection_paginate(%Ecto.Query{} = query, args, opts) do
    # simple limit + offset
    Absinthe.Relay.Connection.from_query(query, opts[:repo_fun] || (&Repo.all/1), args)
  end

  def connection_paginate(list, args, _opts) when is_list(list) do
    # need to provide the full list
    Absinthe.Relay.Connection.from_list(
      list,
      args
    )
  end

  defp build_cursors(items, opts \\ [])
  defp build_cursors([], _), do: {[], nil, nil}

  defp build_cursors(items, opts) do
    edges = build_edges(items, opts)
    first = edges |> List.first() |> get_in([:cursor])
    last = edges |> List.last() |> get_in([:cursor])
    {edges, first, last}
  end

  defp build_edges(items, opts \\ [])
  defp build_edges([], _), do: []

  defp build_edges([item | items], opts) do
    edge = build_edge(item, opts)
    {edges, _} = do_build_cursors(items, [edge], edge[:cursor], opts)
    edges
  end

  defp do_build_cursors([], edges, last, _), do: {Enum.reverse(edges), last}

  defp do_build_cursors([item | rest], edges, _last, opts) do
    edge = build_edge(item, opts)
    do_build_cursors(rest, [edge | edges], edge[:cursor], opts)
  end

  defp build_edge({item, args}, opts) do
    args
    |> Enum.flat_map(fn
      {key, _} when key in [:node] ->
        Logger.warn("Ignoring additional #{key} provided on edge (overriding is not allowed)")
        []

      {key, val} ->
        [{key, val}]
    end)
    |> Enum.into(build_edge(item, opts))
  end

  defp build_edge(item, opts) do
    # opts
    # |> IO.inspect(label: "opts")

    cursor_for_record_fun = opts[:cursor_for_record_fun] || (&Enums.id/1)

    item =
      if item_fun = opts[:item_prepare_fun] do
        item_fun.(item)
        # |> IO.inspect(label: "item1")
      else
        item
        # |> IO.inspect(label: "item2")
      end

    %{
      node: item,
      cursor: cursor_for_record_fun.(item)
    }
  end

  def page(
        queries,
        schema,
        cursor_fn,
        %{} = page_opts,
        base_filters,
        data_filters,
        count_filters
      )
      when is_atom(queries) and
             is_atom(schema) and
             is_function(cursor_fn, 1) and
             is_list(base_filters) and
             is_list(data_filters) and
             is_list(count_filters) do
    # queries_args = [schema, page_opts, base_filters, data_filters, count_filters]
    base_q = apply(queries, :query, [schema, base_filters])
    data_q = apply(queries, :filter, [base_q, data_filters])
    count_q = apply(queries, :filter, [base_q, count_filters])

    with {:ok, [data, counts]} <-
           repo().transact_many(all: data_q, count: count_q) do
      {:ok, Bonfire.API.GraphQL.Page.new(data, counts, cursor_fn, page_opts)}
    end
  end

  def page_all(
        queries,
        schema,
        cursor_fn,
        %{} = page_opts,
        base_filters,
        data_filters,
        count_filters
      )
      when is_atom(queries) and
             is_atom(schema) and
             is_function(cursor_fn, 1) and
             is_list(base_filters) and
             is_list(data_filters) and
             is_list(count_filters) do
    queries_args = [
      schema,
      page_opts,
      base_filters,
      data_filters,
      count_filters
    ]

    {data_q, count_q} = apply(queries, :queries, queries_args)

    with {:ok, [data, counts]} <-
           repo().transact_many(all: data_q, all: count_q) do
      {:ok, Bonfire.API.GraphQL.Page.new(data, counts, cursor_fn, page_opts)}
    end
  end

  def pages(
        queries,
        schema,
        cursor_fn,
        group_fn,
        page_opts,
        base_filters,
        data_filters,
        count_filters
      )
      when is_atom(queries) and
             is_atom(schema) and
             is_function(cursor_fn, 1) and
             is_function(group_fn, 1) and
             is_list(base_filters) and
             is_list(data_filters) and
             is_list(count_filters) do
    queries_args = [
      schema,
      page_opts,
      base_filters,
      data_filters,
      count_filters
    ]

    {data_q, count_q} = apply(queries, :queries, queries_args)

    with {:ok, [data, counts]} <-
           repo().transact_many(all: data_q, all: count_q) do
      {:ok,
       Bonfire.API.GraphQL.Pages.new(
         data,
         counts,
         cursor_fn,
         group_fn,
         page_opts
       )}
    end
  end
end
