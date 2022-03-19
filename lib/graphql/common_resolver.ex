# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.API.GraphQL.CommonResolver do
  alias Pointers.ULID
  alias Bonfire.API.GraphQL

  alias Bonfire.API.GraphQL

  alias Bonfire.API.GraphQL.{
    Fields,
    # Pages,
    # FetchFields,
    # FetchPage,
    ResolveFields,
    ResolvePages
  }

  alias Bonfire.Common.Pointers
  # alias CommonsPub.Common

  # def resolve_context_type(%CommonsPub.Communities.Community{}, _), do: :community
  # def resolve_context_type(%CommonsPub.Collections.Collection{}, _), do: :collection
  # def resolve_context_type(%Organisation{}, _), do: :organisation
  # def resolve_context_type(%{}, _), do: :community

  def created_at_edge(%{id: id}, _, _), do: ULID.timestamp(id)

  def context_edge(%{context_id: id}, _, info) do
    ResolveFields.run(%ResolveFields{
      module: __MODULE__,
      fetcher: :fetch_context_edge,
      context: id,
      info: info
    })
  end

  def context_edge(_, _, _info) do
    {:ok, nil}
  end

  def fetch_context_edge(_, ids) do
    {:ok, ptrs} = Pointers.many(id: List.flatten(ids))
    Fields.new(Pointers.list!(ids), &Map.get(&1, :id))
  end

  def context_edges(%{context_ids: ids}, %{} = page_opts, info) do
    ResolvePages.run(%ResolvePages{
      module: __MODULE__,
      fetcher: :fetch_context_edges,
      context: ids,
      page_opts: page_opts,
      info: info
    })
  end

  def fetch_context_edges(_page_opts, _info, pointers) do
    {:ok, Pointers.list!(pointers)}
  end

  # def loaded_context(%Community{}=community), do: Repo.preload(community, :character)
  # def loaded_context(%Collection{}=collection), do: Repo.preload(collection, :character)
  # def loaded_context(%User{}=user), do: Repo.preload(user, :character)
  # def loaded_context(other), do: other

  @doc "Returns the canonical url for a thing or character"
  def canonical_url_edge(obj, _, _),
    do: {:ok, Bonfire.Common.URIs.canonical_url(obj)}

  @doc "Returns the username for a character"
  def display_username_edge(object, _, _) do
    {:ok, Bonfire.Common.Utils.maybe_apply(Bonfire.Me.Characters, :display_username, object)}
  end

  def is_public_edge(parent, _, _), do: {:ok, not is_nil(parent.published_at)}
  def is_local_edge(%{is_local: is_local}, _, _), do: {:ok, is_local}
  def is_disabled_edge(parent, _, _), do: {:ok, not is_nil(parent.disabled_at)}
  def is_hidden_edge(parent, _, _), do: {:ok, not is_nil(parent.hidden_at)}
  def is_deleted_edge(parent, _, _), do: {:ok, not is_nil(parent.deleted_at)}

  # FIXME
  if Bonfire.Common.Extend.module_enabled?(Bonfire.Repo.Delete) do
    def delete(%{context_id: id}, info) do
      with {:ok, user} <- GraphQL.current_user_or_not_logged_in(info),
           {:ok, deleted} <- Bonfire.Repo.Delete.trigger_soft_delete(id, user) do
        {:ok, deleted}
      else
        e ->
          #IO.inspect(cannot_delete: e)
          GraphQL.not_permitted("delete")
      end
    end
  else
    def delete(_, _) do
      {:error, "Generic deletion is not supported."}
    end
  end

end
