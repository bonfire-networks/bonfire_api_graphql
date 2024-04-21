defmodule Bonfire.API.GraphQL.Pagination do
  import Bonfire.Common.Config, only: [repo: 0]

  def pagination_args_filter(args) do
    # {pagination_args, filters} = 
    args
    |> Keyword.new()
    |> Keyword.split([:after, :before, :first, :last])
  end

  def connection_paginate(list, args, repo_fun \\ &Repo.all/1)

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
        repo_fun
      ) do
    IO.inspect(page_info)
    # best option, since doesn't use offset
    # Absinthe.Relay.Connection.from_slice(edges, end_cursor)
    {:ok,
     %{
       edges: build_edges(edges, cursor_for_record_fun),
       page_info:
         Map.merge(page_info, %{
           # page_count == limit, 
           has_next_page: not is_nil(end_cursor),
           has_previous_page: not is_nil(start_cursor)
         })
     }}
  end

  def connection_paginate(%Ecto.Query{} = query, args, repo_fun) do
    # simple limit + offset
    Absinthe.Relay.Connection.from_query(query, repo_fun, args)
  end

  def connection_paginate(list, args, _repo_fun) when is_list(list) do
    # need to provide the full list
    Absinthe.Relay.Connection.from_list(
      list,
      args
    )
  end

  defp build_cursors(items, cursor_for_record_fun \\ nil)
  defp build_cursors([], _), do: {[], nil, nil}

  defp build_cursors(items, cursor_for_record_fun) do
    edges = build_edges(items, cursor_for_record_fun)
    first = edges |> List.first() |> get_in([:cursor])
    last = edges |> List.last() |> get_in([:cursor])
    {edges, first, last}
  end

  defp build_edges(items, cursor_for_record_fun \\ nil)
  defp build_edges([], _), do: []

  defp build_edges([item | items], cursor_for_record_fun) do
    edge = build_edge(item, cursor_for_record_fun)
    {edges, _} = do_build_cursors(items, [edge], edge[:cursor], cursor_for_record_fun)
    edges
  end

  defp do_build_cursors([], edges, last, _), do: {Enum.reverse(edges), last}

  defp do_build_cursors([item | rest], edges, _last, cursor_for_record_fun) do
    edge = build_edge(item, cursor_for_record_fun)
    do_build_cursors(rest, [edge | edges], edge[:cursor], cursor_for_record_fun)
  end

  defp build_edge({item, args}, cursor_for_record_fun) do
    args
    |> Enum.flat_map(fn
      {key, _} when key in [:node] ->
        Logger.warn("Ignoring additional #{key} provided on edge (overriding is not allowed)")
        []

      {key, val} ->
        [{key, val}]
    end)
    |> Enum.into(build_edge(item, cursor_for_record_fun))
  end

  defp build_edge(item, cursor_for_record_fun) do
    %{
      node: item,
      cursor:
        if(is_function(cursor_for_record_fun, 1),
          do: cursor_for_record_fun.(item),
          else: Paginator.cursor_for_record(item, [:id])
        )
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
