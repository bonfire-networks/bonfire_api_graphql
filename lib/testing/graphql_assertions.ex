# SPDX-License-Identifier: AGPL-3.0-only
defmodule Bonfire.GraphQL.Test.GraphQLAssertions do

  alias Pointers.ULID
  import ExUnit.Assertions
  import Zest

  def assert_binary(val), do: assert(is_binary(val)) && val

  def assert_boolean(val), do: assert(is_boolean(val)) && val

  def assert_int(val), do: assert(is_integer(val)) && val

  def assert_non_neg(val), do: assert_int(val) && assert(val >= 0) && val

  def assert_pos(val), do: assert_int(val) && assert(val > 0) && val

  def assert_float(val), do: assert(is_float(val)) && val

  def assert_email(val), do: assert_binary(val)

  def assert_url(url) do
    uri = URI.parse(url)
    assert uri.scheme
    assert uri.host
    url
  end

  def assert_username(val), do: assert_binary(val)
  def assert_display_username(val), do: assert_binary(val)

  def assert_cursor(x) when is_binary(x) or is_integer(x), do: x

  def assert_cursors(x) when is_list(x), do: Enum.all?(x, &assert_cursor/1) && x

  def assert_ulid(ulid) do
    assert is_binary(ulid)
    assert {:ok, val} = Pointers.ULID.cast(ulid)
    val
  end

  def assert_uuid(uuid) do
    assert is_binary(uuid)
    assert {:ok, val} = Ecto.UUID.cast(uuid)
    val
  end

  def assert_datetime(%DateTime{} = time), do: time

  def assert_datetime(time) do
    assert is_binary(time)
    assert {:ok, val, 0} = DateTime.from_iso8601(time)
    val
  end

  def assert_datetime(%DateTime{} = dt, %DateTime{} = du) do
    assert :eq == DateTime.compare(dt, du)
    du
  end

  def assert_datetime(%DateTime{} = dt, other) when is_binary(other) do
    dt = String.replace(DateTime.to_iso8601(dt), "T", " ")
    assert dt == other
    dt
  end

  def assert_created_at(%{id: id}, %{created_at: created}) do
    scope assert: :created_at do
      assert {:ok, ts} = ULID.timestamp(id)
      assert_datetime(ts, created)
    end
  end

  def assert_updated_at(%{updated_at: left}, %{updated_at: right}) do
    scope assert: :created_at do
      assert_datetime(left, right)
    end
  end

  def assert_list() do
    fn l -> assert(is_list(l)) && l end
  end

  def assert_list(of) when is_function(of, 1) do
    fn l -> assert(is_list(l)) && Enum.map(l, of) end
  end

  def assert_list(of, size) when is_function(of, 1) and is_integer(size) and size >= 0 do
    fn l -> assert(is_list(l)) && assert(Enum.count(l) == size) && Enum.map(l, of) end
  end

  def assert_optional(map_fn) do
    fn o -> if is_nil(o), do: nil, else: map_fn.(o) end
  end

  def assert_eq(val1) do
    fn val2 -> assert(val1 == val2) && val2 end
  end

  def assert_field(object, key, test) when is_map(object) and is_function(test, 1) do
    scope assert_field: key do
      assert %{^key => value} = object
      Map.put(object, key, test.(value))
    end
  end

  def assert_optional_field(object, key, test) when is_map(object) and is_function(test, 1) do
    scope assert_field: key do
      case object do
        %{^key => nil} -> object
        %{^key => value} -> Map.put(object, key, test.(value))
        _ -> object
      end
    end
  end

  def assert_object(struct = %{__struct__: _}, name, required, optional \\ []) do
    assert_object(Map.from_struct(struct), name, required, optional)
  end

  def assert_object(%{} = object, name, required, optional)
      when is_atom(name) and is_list(required) and is_list(optional) do
    object = uncamel_map(object)

    scope [{name, object}] do
      object =
        Enum.reduce(required, object, fn {key, test}, acc ->
          assert_field(acc, key, test)
        end)

      Enum.reduce(optional, object, fn {key, test}, acc ->
        assert_optional_field(acc, key, test)
      end)
    end
  end

  def assert_maps_eq(left, right, name) do
    assert_maps_eq(left, right, name, Map.keys(left), [])
  end

  def assert_maps_eq(left, right, name, required) do
    assert_maps_eq(left, right, name, required, [])
  end

  def assert_maps_eq(%{} = left, %{} = right, name, required, optional)
      when is_list(required) and is_list(optional) do
    scope [{name, {left, right}}] do
      each(required, fn key ->
        assert %{^key => left_val} = left
        assert %{^key => right_val} = right
        assert left_val == right_val
      end)

      each(optional, fn key ->
        case left do
          %{^key => left_val} ->
            assert %{^key => right_val} = right
            assert left_val == right_val

          _ ->
            nil
        end
      end)

      right
    end
  end

  def assert_location(loc) do
    assert_object(loc, :assert_location,
      column: &assert_non_neg/1,
      line: &assert_pos/1
    )
  end

  def assert_not_logged_in(errs, path) do
    assert [err] = errs

    assert_object(err, :assert_not_logged_in,
      code: assert_eq("needs_login"),
      message: assert_eq("You need to log in first."),
      path: assert_eq(path),
      locations: assert_list(&assert_location/1, 1)
    )
  end

  def assert_not_permitted(errs, path, verb \\ "do") do
    assert [err] = errs

    assert_object(err, :assert_not_permitted,
      code: assert_eq("unauthorized"),
      message: assert_eq("You do not have permission to #{verb} this."),
      path: assert_eq(path),
      locations: assert_list(&assert_location/1, 1)
    )
  end

  def assert_not_found(errs, path) do
    assert [err] = errs

    assert_object(err, :assert_not_found,
      code: assert_eq("not_found"),
      message: assert_eq("Not found"),
      path: assert_eq(path),
      locations: assert_list(&assert_location/1, 1)
    )
  end

  def assert_invalid_credential(errs, path) do
    assert [err] = errs

    assert_object(err, :assert_invalid_credential,
      code: assert_eq("invalid_credential"),
      message: assert_eq("We couldn't find an account with these details"),
      path: assert_eq(path),
      locations: assert_list(&assert_location/1, 1)
    )
  end

  def assert_page_info(page_info) do
    assert_object(page_info, :assert_page_info,
      start_cursor: assert_optional(&assert_cursors/1),
      end_cursor: assert_optional(&assert_cursors/1),
      has_previous_page: assert_optional(&assert_boolean/1),
      has_next_page: assert_optional(&assert_boolean/1)
    )
  end

  def assert_page() do
    fn page ->
      page =
        assert_object(page, :assert_page,
          edges: assert_list(),
          total_count: &assert_non_neg/1,
          page_info: &assert_page_info/1
        )

      if page.edges == [] do
        assert is_nil(page.page_info.start_cursor)
        assert is_nil(page.page_info.end_cursor)
      end

      page
    end
  end

  def assert_page(of) when is_function(of, 1) do
    fn page ->
      page =
        assert_object(page, :assert_page,
          edges: assert_list(of),
          total_count: &assert_non_neg/1,
          page_info: &assert_page_info/1
        )

      if page.edges == [] do
        assert is_nil(page.page_info.start_cursor)
        assert is_nil(page.page_info.end_cursor)
      end

      page
    end
  end

  # def assert_pages_eq(page, page2) do
  #   assert page.edges
  #   assert page.page_info.has_previous_page == prev?
  #   assert page.page_info.has_next_page == next?
  #   page
  # end

  def assert_page(page, returned_count, total_count, prev?, next?, cursor_fn) do
    page =
      assert_object(page, :assert_page,
        edges: assert_list(& &1, returned_count),
        total_count: assert_eq(total_count),
        page_info: &assert_page_info/1
      )

    if page.edges == [] do
      assert is_nil(page.page_info.start_cursor)
      assert is_nil(page.page_info.end_cursor)
    else
      assert page.page_info.start_cursor == cursor_fn.(List.first(page.edges))
      assert page.page_info.end_cursor == cursor_fn.(List.last(page.edges))
    end

    assert page.page_info.has_previous_page == prev?
    assert page.page_info.has_next_page == next?
    page
  end

  # TODO: move to some utils module
  def uncamel_map(%{} = map) do
    Enum.reduce(map, %{}, fn {k, v}, acc -> Map.put(acc, uncamel(k), v) end)
  end

  @doc false
  def uncamel(atom) when is_atom(atom), do: atom
  def uncamel("__typeName"), do: :typename
  def uncamel(bin) when is_binary(bin), do: String.to_existing_atom(Recase.to_snake(bin))


end
