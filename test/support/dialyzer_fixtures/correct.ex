defmodule DialyzerFixtures.Correct do
  @moduledoc false

  # Every generated function, used the way its @spec says to. Dialyzer has to
  # stay silent about this module: a warning here means the generated specs
  # contradict the code they are attached to.

  alias DialyzerFixtures.Thing

  @spec build() :: {:ok, Thing.t()} | {:error, [String.t()]}
  def build, do: Thing.new(%{name: "a", count: 1})

  @spec build_with_optional() :: {:ok, Thing.t()} | {:error, [String.t()]}
  def build_with_optional, do: Thing.new(%{name: "a", count: 1, note: "n"})

  @spec build!() :: Thing.t()
  def build!, do: Thing.new!(%{name: "a", count: 1})

  @spec replace(Thing.t()) :: {:ok, Thing.t()} | {:error, [String.t()]}
  def replace(thing), do: Thing.put(thing, %{count: 2})

  @spec replace!(Thing.t()) :: Thing.t()
  def replace!(thing), do: Thing.put!(thing, %{count: 2})

  @spec change(Thing.t()) :: {:ok, Thing.t()} | {:error, [String.t()]}
  def change(thing), do: Thing.update(thing, %{count: &(&1 + 1), name: &String.upcase/1})

  @spec change!(Thing.t()) :: Thing.t()
  def change!(thing), do: Thing.update!(thing, %{count: &(&1 + 1)})

  @spec check(Thing.t()) :: :ok | {:error, [String.t()]}
  def check(thing), do: Thing.validate(thing)

  @spec read_enforced_field() :: String.t()
  def read_enforced_field, do: Thing.new!(%{name: "a", count: 1}).name

  @spec read_field_with_a_default() :: String.t()
  def read_field_with_a_default, do: Thing.new!(%{name: "a", count: 1}).note

  @spec read_through_put(Thing.t()) :: integer()
  def read_through_put(thing) do
    case Thing.put(thing, %{count: 2}) do
      {:ok, updated} -> updated.count
      {:error, _reasons} -> 0
    end
  end
end
