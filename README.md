# TypedStructBuilderValidators

TypedStructBuilderValidators is a plugin library for TypedStruct which generates type-safe and validating helper methods for
creating and updating structs.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `typed_struct_builder_validators` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:typed_struct_builder_validators, "~> 0.1.0"}
  ]
end
```

## Summary

A `TypedStruct` plugin that generates validating constructors and updaters.
It enforces validity both at runtime and via compile-time types.

Adding `plugin TypedStructBuilderValidators` to a `typedstruct` block defines seven
functions:

  * `new/1` — build from a map, returning `{:ok, t()}` or `{:error, reasons}`
  * `new!/1` — build from a map, returning `t()` or raising
  * `validate/1` — check an existing struct, returning `:ok` or `{:error, reasons}`
  * `put/2` — replace some fields of an existing struct, then revalidate
  * `put!/2` — replace some fields, returning `t()` or raising
  * `update/2` — transform some fields through functions, then revalidate
  * `update!/2` — transform some fields, returning `t()` or raising

These methods are fully typed in order to provide higher quality dialyzer results.

```elixir
typedstruct module: MyStruct do
  plugin TypedStructBuilderValidators

  field :field1, String.t()
  field :field2, non_neg_integer(), enforce: true

  validator &(&1.field2 > 0)
end

# Results in dialyzer warnings and results in `{:error, reason}` at runtime
MyStruct.new(%{field1: 1})
MyStruct.new(%{field1: 1, field2: 2})
MyStruct.new(%{field1: "hello"})

# Valid
MyStruct.new(%{field1: "hello", field2: 2})
```

`new/1`, `put/2` and `update/2` all perform `validate/1`, as do the raising
variants.

## Specs

Each generated function carries a `@spec` built from the declared field types:
```elixir
@spec validate(t()) :: :ok | {:error, [String.t()]}

@spec new(%{optional(:field1) => String.t(), field2: float()}) ::
        {:ok, t()} | {:error, [String.t()]}

@spec new!(map()) :: t()

@spec put(t(), %{optional(:field1) => String.t(), optional(:field2) => float()}) ::
        {:ok, t()} | {:error, [String.t()]}

@spec put!(t(), %{optional(:field1) => String.t(), optional(:field2) => float()}) :: t()

@spec update(t(), %{
        optional(:field1) => (String.t() -> String.t()),
        optional(:field2) => (float() -> float())
      }) :: {:ok, t()} | {:error, [String.t()]}

@spec update!(t(), %{
        optional(:field1) => (String.t() -> String.t()),
        optional(:field2) => (float() -> float())
      }) :: t()
```

For `new/1`, fields that are `enforce: true` are required keys and the rest
are optional. For `put/2` and `update/2`, every field is optional.

`validate/1` collects all the problems it finds and returns them
together, rather than stopping at the first.

## Naming the argument types

If you'd like to use the type signatures used by any of the methods, you can
provide a name to declare the type with that the spec then refers to:

```elixir
    typedstruct module: Config, enforce: true do
      plugin TypedStructBuilderValidators, fields_type_name: :my_fields_type

      field :field1, String.t(), enforce: false
      field :field2, float()
    end

    # Generated
    @type my_fields_type :: %{optional(:field1) => String.t(), field2: float()}
    @spec new(my_fields_type()) :: {:ok, t()} | {:error, [String.t()]}
```

so that you can use it elsewhere:
```elixir
    @spec init(Config.my_fields_type()) :: t()
```

The three maps are named separately:

  * `:fields_type_name` — the `new/1` argument
  * `:changes_type_name` — the `put/2` and `put!/2` argument
  * `:updates_type_name` — the `update/2` and `update!/2` argument

Each takes a bare name, which defines a `@type`, or a `{name, kind}` pair
where `kind` is one of `[:type, :typep, :opaque]`:
```elixir
    plugin TypedStructBuilderValidators,
      fields_type_name: :attrs,
      changes_type_name: {:changes, :typep}
```

## Renaming the generated functions

Any of these methods can be renamed by passing its default name as an option.
The ones you leave out keep their defaults:
```elixir
    typedstruct module: Config, enforce: true do
      plugin TypedStructBuilderValidators, new!: :build!, validate: :check

      field :field1, String.t()
    end

    Config.build!(%{field1: "x"})
    Config.check(config)
    Config.put(config, %{field1: "y"})
```

## Generating only some of them

`:only` narrows the set to the methods you name:
```elixir
    plugin TypedStructBuilderValidators, only: [:put, :put!]
```

## Validators

`validator/1` takes a predicate on the completed struct:
```elixir
    typedstruct enforce: true do
      plugin TypedStructBuilderValidators

      field :foo, float()
      field :bar, float()
      field :baz, non_neg_integer()

      validator fn c -> c.baz > 0 end
      validator &(&1.foo > &1.bar)
    end
```

`validator/1` is a macro. The predicate is inlined into the final
`validate/1` method. Its source doubles as the default failure message.
The two above report `"fn c -> c.baz > 0 end"` and `"&(&1.foo > &1.bar)"`.
Pass your own message as a second argument when the source is not self-explanatory:
```elixir
    validator &(&1.foo > &1.bar), "foo must name a higher value than bar"
```

A validator passes by returning `true` or `:ok`, and fails by returning
`false` or `{:error, reason}`. Any other return raises, on the grounds that a
validator returning something unexpected is a bug rather than a rejection.
Returning `{:error, reason}` replaces the message, which is how to build one
that quotes the offending value.

Validators run against a built struct, so a field left out of `attrs` is
checked with its declared default rather than skipped. In `new/1` they run
only once the struct can be built at all: if a key is missing or unknown,
`new/1` reports that and does not run them.

Because the predicate is inlined, it must be a pure function of the struct; it
cannot close over variables from the surrounding scope.
