if Application.compile_env(:bonfire_api_graphql, :modularity) != :disabled do
  defmodule Bonfire.API.MastoCompat.BatchLoaders do
    @moduledoc """
    Batch-loads the supplementary per-object data Mastodon mappers need (interaction
    state, mentions, hashtags, visibility, followers-grants, post-content) in a handful
    of queries instead of N+1, shared by the timeline and notification read paths.
    Callers pass object IDs and receive a keyword list ready to merge into mapper opts.

    Reads only through stable Bonfire context functions (`Bonfire.Social.Edges`,
    `Bonfire.Boundaries.Controlleds`, `Bonfire.Tag`), staying separated from core.
    """

    use Bonfire.Common.Repo
    import Ecto.Query

    alias Bonfire.Tag.Tagged

    @doc """
    Batch-load supplementary context for the given object IDs.

    Returns a keyword list with `:interaction_states`, `:mentions_by_object`,
    `:visibility_by_object` and `:followers_grant_objects`. Pass
    `post_content?: true` to also include `:post_content_by_id` (used by the
    notifications path, which may need to render objects the feed didn't preload).
    """
    def load(current_user, object_ids, opts \\ [])

    def load(_current_user, [], opts) do
      base = [
        interaction_states: %{},
        mentions_by_object: %{},
        hashtags_by_object: %{},
        visibility_by_object: %{},
        followers_grant_objects: MapSet.new()
      ]

      if Keyword.get(opts, :post_content?, false) do
        Keyword.put(base, :post_content_by_id, %{})
      else
        base
      end
    end

    def load(current_user, object_ids, opts) do
      # Pre-seed every object with an empty preset-ACL set so callers can rely on
      # a present entry, then overlay the actual preset ACLs.
      visibility_by_object =
        object_ids
        |> Map.new(fn object_id -> {object_id, MapSet.new()} end)
        |> Map.merge(Bonfire.Boundaries.Controlleds.list_preset_acl_ids_on_objects(object_ids))

      base = [
        interaction_states: interaction_states(current_user, object_ids),
        mentions_by_object: mentions(object_ids),
        hashtags_by_object: hashtags(object_ids),
        visibility_by_object: visibility_by_object,
        followers_grant_objects: followers_grants(object_ids, visibility_by_object)
      ]

      if Keyword.get(opts, :post_content?, false) do
        Keyword.put(base, :post_content_by_id, post_content(object_ids))
      else
        base
      end
    end

    @doc "Whether the current user has liked/boosted/bookmarked each object."
    def interaction_states(nil, _object_ids), do: %{}
    def interaction_states(_current_user, []), do: %{}

    def interaction_states(current_user, object_ids) do
      liked_ids = interaction(current_user, object_ids, Bonfire.Data.Social.Like)
      boosted_ids = interaction(current_user, object_ids, Bonfire.Data.Social.Boost)
      bookmarked_ids = interaction(current_user, object_ids, Bonfire.Data.Social.Bookmark)

      Map.new(object_ids, fn object_id ->
        {object_id,
         %{
           favourited: MapSet.member?(liked_ids, object_id),
           reblogged: MapSet.member?(boosted_ids, object_id),
           bookmarked: MapSet.member?(bookmarked_ids, object_id)
         }}
      end)
    end

    defp interaction(current_user, object_ids, interaction_module) do
      Bonfire.Social.Edges.batch_exists?(interaction_module, current_user, object_ids)
    end

    @doc "Map of object ID to the list of `@`-mentioned characters tagged on it."
    def mentions([]), do: %{}

    def mentions(object_ids) do
      base_map = Map.new(object_ids, fn id -> {id, []} end)

      mentions_map =
        from(t in Tagged,
          where: t.id in ^object_ids,
          preload: [tag: [:character, :profile]]
        )
        |> repo().all()
        |> Enum.group_by(& &1.id)
        |> Map.new(fn {object_id, tagged_records} ->
          {object_id, tagged_to_mentions(tagged_records)}
        end)

      Map.merge(base_map, mentions_map)
    end

    defp tagged_to_mentions(tagged_records) do
      tagged_records
      |> Enum.filter(fn tagged ->
        character = tagged.tag && Map.get(tagged.tag, :character)

        is_map(character) && !match?(%Ecto.Association.NotLoaded{}, character) &&
          map_size(character) > 0
      end)
      |> Enum.map(fn tagged ->
        %{
          tag_id: tagged.tag_id,
          character: Map.get(tagged.tag, :character) || %{},
          profile: Map.get(tagged.tag, :profile)
        }
      end)
    end

    @doc "Map of object ID to the list of hashtag tags on it (with `named` preloaded)."
    def hashtags([]), do: %{}

    def hashtags(object_ids) do
      base_map = Map.new(object_ids, fn id -> {id, []} end)

      hashtags_map =
        from(t in Tagged, where: t.id in ^object_ids, preload: [tag: [:named]])
        |> repo().all()
        |> Enum.filter(&(Bonfire.Common.Types.object_type(&1.tag) == Bonfire.Tag.Hashtag))
        |> Enum.group_by(& &1.id, & &1.tag)

      Map.merge(base_map, hashtags_map)
    end

    @doc """
    The subset of objects (among those without preset ACLs) that grant access to
    a followers circle — used to distinguish `private` from `direct` visibility.
    """
    def followers_grants(object_ids, visibility_by_object) do
      no_preset_ids =
        Enum.filter(object_ids, fn object_id ->
          case Map.get(visibility_by_object, object_id) do
            %MapSet{} = acl_ids -> MapSet.size(acl_ids) == 0
            nil -> true
          end
        end)

      Bonfire.Boundaries.Controlleds.list_objects_with_followers_grants(no_preset_ids)
    end

    @doc "Map of object ID to its `PostContent` (for objects the feed did not preload)."
    def post_content([]), do: %{}

    def post_content(object_ids) do
      from(pc in Bonfire.Data.Social.PostContent, where: pc.id in ^object_ids)
      |> repo().all()
      |> Map.new(&{&1.id, &1})
    end
  end
end
