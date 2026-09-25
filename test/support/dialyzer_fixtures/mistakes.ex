defmodule DialyzerFixtures.Mistakes do
  @moduledoc false

  # Each function here breaks one of the generated specs. Dialyzer has to report
  # every single one: the moment it stops, the plugin is generating code whose
  # types it can no longer see through, and the specs have become a promise that
  # nothing checks.
  #
  # Kept out of the `dev` build by `elixirc_paths/1`, so `mix dialyzer` never
  # sees them.

  alias DialyzerFixtures.Thing

  # :name is a String.t().
  def new_with_wrong_field_type, do: Thing.new(%{name: 1, count: 1})

  # :count is enforced, so the attributes type requires it.
  def new_without_an_enforced_field, do: Thing.new(%{name: "a"})

  # :nmae is not a field, so it is not in the attributes type either.
  def new_with_an_unknown_key, do: Thing.new(%{name: "a", count: 1, nmae: "a"})

  def new_bang_with_wrong_field_type, do: Thing.new!(%{name: 1, count: 1})

  def put_with_wrong_field_type(thing), do: Thing.put(thing, %{count: "1"})

  def put_bang_with_an_unknown_key(thing), do: Thing.put!(thing, %{nmae: "a"})

  # new!/1 hands back a struct whose :name is a String.t().
  @spec read_name_as_an_integer() :: integer()
  def read_name_as_an_integer, do: Thing.new!(%{name: "a", count: 1}).name

  # put/2 hands back a Thing, so :count is an integer, not a map.
  @spec read_put_result_as_a_map(Thing.t()) :: map()
  def read_put_result_as_a_map(thing) do
    case Thing.put(thing, %{count: 2}) do
      {:ok, updated} -> updated.count
      {:error, _reasons} -> %{}
    end
  end

  # validate/1 answers :ok or {:error, reasons}, never a boolean.
  @spec read_validate_as_a_boolean(Thing.t()) :: boolean()
  def read_validate_as_a_boolean(thing), do: Thing.validate(thing) == :ok and thing.count

  # An updater of the wrong arity, or one that is not a function at all, does not
  # fit `(integer() -> integer())` in any reading, so both are reported.
  def update_with_an_updater_of_the_wrong_arity(thing) do
    Thing.update(thing, %{count: fn a, b -> a + b end})
  end

  def update_with_an_updater_that_is_not_a_function(thing) do
    Thing.update(thing, %{count: 5})
  end

  # What is *not* reported: an updater of the right arity whose argument or
  # return type is wrong. Dialyzer checks that a value is a function and how many
  # arguments it takes, and stops there — it never compares a function's domain
  # or range against a contract, in a map or anywhere else. So the
  # `(integer() -> integer())` in update/2's spec documents the intent without
  # anything enforcing it, and this call goes unreported. Left here, unasserted,
  # so the gap is written down where someone would look for it.
  def update_with_an_updater_of_the_wrong_type(thing) do
    Thing.update(thing, %{count: &Integer.to_string/1})
  end
end
