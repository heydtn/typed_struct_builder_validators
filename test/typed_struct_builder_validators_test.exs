defmodule TypedStructBuilderValidatorsTest do
  use ExUnit.Case, async: true

  use TypedStruct

  typedstruct module: Mixed, enforce: true do
    plugin(TypedStructBuilderValidators)

    field(:base, float())
    field(:label, String.t(), enforce: false)
    field(:count, integer())
    field(:note, String.t(), default: "n")
  end

  typedstruct module: Optionals do
    plugin(TypedStructBuilderValidators)

    field(:a, integer())
    field(:b, atom())
  end

  typedstruct module: Validated, enforce: true do
    plugin(TypedStructBuilderValidators)

    field(:base, float())
    field(:factor, float())
    field(:beta_fast, float())
    field(:beta_slow, float())

    validator fn config -> config.base > 0 end
    validator fn config -> config.factor >= 1.0 end
    validator &(&1.beta_fast > &1.beta_slow)
  end

  typedstruct module: Messaged, enforce: true do
    plugin(TypedStructBuilderValidators)

    field(:a, integer())

    validator fn s -> s.a > 0 end, "a must be positive"
    validator fn s -> if rem(s.a, 2) == 0, do: :ok, else: {:error, "#{s.a} is not even"} end
  end

  typedstruct module: WithDefaultChecked do
    plugin(TypedStructBuilderValidators)

    field(:limit, integer(), default: -1)

    validator fn s -> s.limit > 0 end
  end

  typedstruct module: Confused, enforce: true do
    plugin(TypedStructBuilderValidators)

    field(:a, integer())

    validator fn _s -> :maybe end
  end

  typedstruct module: Named, enforce: true do
    plugin(TypedStructBuilderValidators,
      fields_type_name: :attrs,
      changes_type_name: {:changes, :typep},
      updates_type_name: {:updates, :opaque}
    )

    field(:base, float())
    field(:label, String.t(), enforce: false)
  end

  typedstruct module: Renamed, enforce: true do
    plugin(TypedStructBuilderValidators,
      validate: :check,
      new: :build,
      new!: :build!,
      put: :replace,
      put!: :replace!,
      update: :change,
      update!: :change!
    )

    field(:low, float())
    field(:high, float())

    validator &(&1.low < &1.high), "low must be below high"
  end

  typedstruct module: PartlyRenamed, enforce: true do
    plugin(TypedStructBuilderValidators, new!: :build!)

    field(:a, integer())
  end

  typedstruct module: OnlyBang, enforce: true do
    plugin(TypedStructBuilderValidators, only: [:new!])

    field(:low, float())
    field(:high, float())

    validator &(&1.low < &1.high), "low must be below high"
  end

  typedstruct module: OnlyPutPair, enforce: true do
    plugin(TypedStructBuilderValidators, only: [:put, :put!])

    field(:a, integer())

    validator &(&1.a > 0), "a must be positive"
  end

  typedstruct module: OnlyValidate, enforce: true do
    plugin(TypedStructBuilderValidators, only: [:validate])

    field(:a, integer())
  end

  typedstruct module: OnlyRenamed, enforce: true do
    plugin(TypedStructBuilderValidators, only: [:new!], new!: :build!)

    field(:a, integer())
  end

  @plugin_functions [validate: 1, new: 1, new!: 1, put: 2, put!: 2, update: 2, update!: 2]

  # Which of the plugin's functions a module exposes.
  defp exported(module, candidates \\ @plugin_functions) do
    Code.ensure_loaded!(module)

    for {name, arity} <- candidates, function_exported?(module, name, arity), do: name
  end

  defp rendered(fields, enforced, validators, opts) do
    fields
    |> TypedStructBuilderValidators.__functions__(enforced, validators, opts)
    |> Macro.to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.replace("%{ ", "%{")
    |> String.replace(" }", "}")
  end

  # Renders one @spec from the AST the plugin generates.
  defp spec_string(name, fields, enforced, validators \\ [], opts \\ []) do
    [spec] =
      Regex.run(
        ~r/@spec #{name}\(.*?\) :: (?:\{:ok, t\(\)\}|:ok) \| \{:error, \[String\.t\(\)\]\}/,
        rendered(fields, enforced, validators, opts)
      )

    spec
  end

  # Renders one type definition from the AST the plugin generates.
  defp type_string(name, fields, enforced, opts) do
    [type] =
      Regex.run(
        ~r/@(?:type|typep|opaque) #{name}\(\) :: .*?\}/,
        rendered(fields, enforced, [], opts)
      )

    type
  end

  @two_fields [{:a, quote(do: integer()), nil}, {:b, quote(do: atom()), nil}]

  # Whether the generated functions can report anything depends on there being
  # something to report, so the specs that carry an error half need a validator.
  @a_validator [{quote(do: &(&1.a > 0)), "a must be positive"}]

  describe "new/1 spec" do
    test "puts optional fields first and required fields in shorthand form" do
      fields = [
        {:base, quote(do: float()), nil},
        {:label, quote(do: String.t()), nil},
        {:count, quote(do: integer()), nil}
      ]

      assert spec_string(:new, fields, [:base, :count]) ==
               "@spec new(%{optional(:label) => String.t(), base: float(), count: integer()}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "emits an all-shorthand map when every field is required" do
      assert spec_string(:new, @two_fields, [:a, :b]) ==
               "@spec new(%{a: integer(), b: atom()}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "emits an all-optional map when nothing is enforced" do
      assert spec_string(:new, @two_fields, [], @a_validator) ==
               "@spec new(%{optional(:a) => integer(), optional(:b) => atom()}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "preserves declaration order within each group" do
      fields = for name <- [:z, :y, :x, :w], do: {name, quote(do: integer()), nil}

      assert spec_string(:new, fields, [:y, :w]) ==
               "@spec new(%{optional(:z) => integer(), optional(:x) => integer(), y: integer(), w: integer()}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "the generated spec is valid Elixir source" do
      assert {:ok, _ast} = spec_string(:new, @two_fields, [:b]) |> Code.string_to_quoted()
    end

    test "omits the missing-key clause when nothing is enforced" do
      rendered =
        [{:a, quote(do: integer()), nil}]
        |> TypedStructBuilderValidators.__functions__([], [])
        |> Macro.to_string()

      refute rendered =~ "__missing_keys__"
    end
  end

  describe "named argument types" do
    test "defines no types at all unless a name is given" do
      refute rendered(@two_fields, [:a], [], []) =~ "@type"
    end

    test "defines the new/1 argument and refers to it from the spec" do
      opts = [fields_type_name: :attrs]

      assert type_string(:attrs, @two_fields, [:b], opts) ==
               "@type attrs() :: %{optional(:a) => integer(), b: atom()}"

      assert spec_string(:new, @two_fields, [:b], [], opts) ==
               "@spec new(attrs()) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "defines the put/2 and update/2 arguments" do
      opts = [changes_type_name: :changes, updates_type_name: :updates]

      assert type_string(:changes, @two_fields, [:a, :b], opts) ==
               "@type changes() :: %{optional(:a) => integer(), optional(:b) => atom()}"

      assert type_string(:updates, @two_fields, [:a, :b], opts) ==
               "@type updates() :: %{optional(:a) => (integer() -> integer()), optional(:b) => (atom() -> atom())}"

      assert spec_string(:put, @two_fields, [:a, :b], @a_validator, opts) ==
               "@spec put(t(), changes()) :: {:ok, t()} | {:error, [String.t()]}"

      assert spec_string(:update, @two_fields, [:a, :b], @a_validator, opts) ==
               "@spec update(t(), updates()) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "the raising variants share their non-raising argument types" do
      opts = [changes_type_name: :changes, updates_type_name: :updates]
      rendered = rendered(@two_fields, [:a], [], opts)

      assert rendered =~ "@spec put!(t(), changes()) :: t()"
      assert rendered =~ "@spec update!(t(), updates()) :: t()"
    end

    test "names one type without affecting the others" do
      rendered = rendered(@two_fields, [:a, :b], [], fields_type_name: :attrs)

      assert rendered =~ "@spec new(attrs())"
      assert rendered =~ "@spec put(t(), %{optional(:a) => integer()"
      refute rendered =~ "@type changes()"
    end

    test "a bare name defines a public type" do
      assert type_string(:attrs, @two_fields, [], fields_type_name: :attrs) =~ "@type attrs() ::"
    end

    test "a {name, kind} pair chooses the kind" do
      for kind <- [:type, :typep, :opaque] do
        assert type_string(:attrs, @two_fields, [], fields_type_name: {:attrs, kind}) =~
                 "@#{kind} attrs() ::"
      end
    end

    test "rejects an unsupported kind" do
      error =
        assert_raise ArgumentError, fn ->
          rendered(@two_fields, [], [], fields_type_name: {:attrs, :nope})
        end

      assert error.message =~ "expected fields_type_name to be a type name"
      assert error.message =~ "[:type, :typep, :opaque]"
    end

    test "rejects an unknown option rather than ignoring it" do
      error =
        assert_raise ArgumentError, fn ->
          rendered(@two_fields, [], [], field_type_name: :attrs)
        end

      assert error.message =~ "unknown option(s) [:field_type_name]"
      assert error.message =~ ":fields_type_name"
    end

    test "the named types are usable by a caller" do
      assert {:ok, %Named{base: 1.0, label: nil}} = Named.new(%{base: 1.0})
      assert {:ok, %Named{label: "x"}} = Named.put(Named.new!(%{base: 1.0}), %{label: "x"})
    end
  end

  describe "renaming the generated functions" do
    test "every function answers to its new name" do
      assert {:ok, config} = Renamed.build(%{low: 1.0, high: 2.0})
      assert %Renamed{low: 1.0, high: 2.0} = Renamed.build!(%{low: 1.0, high: 2.0})
      assert Renamed.check(config) == :ok
      assert {:ok, %Renamed{high: 9.0}} = Renamed.replace(config, %{high: 9.0})
      assert %Renamed{high: 9.0} = Renamed.replace!(config, %{high: 9.0})
      assert {:ok, %Renamed{high: 20.0}} = Renamed.change(config, %{high: &(&1 * 10)})
      assert %Renamed{high: 20.0} = Renamed.change!(config, %{high: &(&1 * 10)})
    end

    test "the default names are no longer defined" do
      assert exported(Renamed) == []
    end

    test "the functions left out of the options keep their defaults" do
      assert %PartlyRenamed{a: 1} = PartlyRenamed.build!(%{a: 1})
      assert {:ok, %PartlyRenamed{a: 1}} = PartlyRenamed.new(%{a: 1})
      assert PartlyRenamed.validate(PartlyRenamed.build!(%{a: 1})) == :ok
      assert exported(PartlyRenamed) == [:validate, :new, :put, :put!, :update, :update!]
    end

    test "the renamed constructor still runs the validators" do
      assert Renamed.build(%{low: 5.0, high: 2.0}) == {:error, ["low must be below high"]}
    end

    test "the renamed updaters still run the validators" do
      config = Renamed.build!(%{low: 1.0, high: 2.0})

      assert Renamed.replace(config, %{high: 0.0}) == {:error, ["low must be below high"]}

      assert Renamed.change(config, %{high: &(&1 * -1.0)}) ==
               {:error, ["low must be below high"]}
    end

    test "the missing-key clause follows the renamed constructor" do
      assert {:error, [message]} = Renamed.build(%{low: 1.0})
      assert message =~ "missing required key(s): :high"
    end

    test "the specs carry the new names" do
      code =
        rendered(@two_fields, [:a, :b], @a_validator,
          validate: :check,
          new: :build,
          new!: :build!
        )

      assert code =~ "@spec check(t()) :: :ok | {:error, [String.t()]}"
      assert code =~ "@spec build(%{a: integer(), b: atom()})"
      assert code =~ "@spec build!(%{a: integer(), b: atom()}) :: t()"
    end

    test "rejects a new name that is not an atom" do
      error = assert_raise ArgumentError, fn -> rendered(@two_fields, [], [], new!: "build!") end

      assert error.message =~ ~s(expected new! to be renamed to an atom, got: "build!")
    end

    test "rejects two functions renamed onto the same name" do
      error =
        assert_raise ArgumentError, fn ->
          rendered(@two_fields, [], [], new: :build, new!: :build)
        end

      assert error.message =~ "would define :build more than once"
    end

    test "the unknown-option message lists the renameable functions" do
      error =
        assert_raise ArgumentError, fn -> rendered(@two_fields, [], [], new_bang: :build!) end

      assert error.message =~ "unknown option(s) [:new_bang]"
      assert error.message =~ ":new!"
    end
  end

  describe "only" do
    test "generates just the functions it names" do
      assert exported(OnlyPutPair) == [:put, :put!]
      assert exported(OnlyValidate) == [:validate]
    end

    test "a bang variant named without its plain counterpart is one function" do
      assert exported(OnlyBang) == [:new!]
      assert %OnlyBang{low: 1.0, high: 2.0} = OnlyBang.new!(%{low: 1.0, high: 2.0})
    end

    test "the inlined body still reports missing keys" do
      error = assert_raise ArgumentError, fn -> OnlyBang.new!(%{low: 1.0}) end

      assert error.message =~ "missing required key(s): :high"
    end

    test "the inlined body ignores a key the struct does not declare" do
      assert %OnlyBang{low: 1.0, high: 2.0} = OnlyBang.new!(%{low: 1.0, high: 2.0, z: 1})
    end

    test "the inlined body still runs the validators" do
      error = assert_raise ArgumentError, fn -> OnlyBang.new!(%{low: 5.0, high: 2.0}) end

      assert error.message =~ "low must be below high"
    end

    test "validate stays reachable without being exported" do
      refute :validate in exported(OnlyPutPair)

      assert OnlyPutPair.put(struct(OnlyPutPair, %{a: 1}), %{a: -1}) ==
               {:error, ["a must be positive"]}
    end

    test "combines with renaming" do
      assert exported(OnlyRenamed) == []
      assert exported(OnlyRenamed, build!: 1) == [:build!]
      assert %OnlyRenamed{a: 1} = OnlyRenamed.build!(%{a: 1})
    end

    test "rejects a name that is not one of the generated functions" do
      error =
        assert_raise ArgumentError, fn ->
          TypedStructBuilderValidators.__functions__(@two_fields, [], [], only: [:nope])
        end

      assert error.message =~ "expected only to name generated functions, got: [:nope]"
    end

    test "rejects anything that is not a list" do
      error =
        assert_raise ArgumentError, fn ->
          TypedStructBuilderValidators.__functions__(@two_fields, [], [], only: :new)
        end

      assert error.message =~ "expected only to be a list of function names, got: :new"
    end

    test "rejects renaming a function it leaves out" do
      error =
        assert_raise ArgumentError, fn ->
          TypedStructBuilderValidators.__functions__(@two_fields, [], [],
            only: [:new],
            put: :replace
          )
        end

      assert error.message =~ "cannot rename :put"
    end
  end

  describe "put/2 and update/2 specs" do
    test "put takes the struct and an all-optional map, even for enforced fields" do
      assert spec_string(:put, @two_fields, [:a, :b], @a_validator) ==
               "@spec put(t(), %{optional(:a) => integer(), optional(:b) => atom()}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "update takes the struct and a map of same-type functions" do
      assert spec_string(:update, @two_fields, [:a, :b], @a_validator) ==
               "@spec update(t(), %{optional(:a) => (integer() -> integer()), optional(:b) => (atom() -> atom())}) :: {:ok, t()} | {:error, [String.t()]}"
    end

    test "validate takes the struct and returns :ok or errors" do
      assert spec_string(:validate, @two_fields, [:a, :b], @a_validator) ==
               "@spec validate(t()) :: :ok | {:error, [String.t()]}"
    end

    # Nothing declared to check means nothing that can fail, and a body dialyzer
    # can see only ever answers `:ok`. Saying otherwise would leave every caller
    # matching on `{:error, reasons}` with a clause it reports as unreachable.
    test "validate is typed as answering only :ok when no validator is declared" do
      code = rendered(@two_fields, [:a, :b], [], [])

      assert code =~ "@spec validate(t()) :: :ok"
      assert code =~ "def validate(%__MODULE__{}) do :ok end"
      # still called, and matched against the one thing it can answer: the call
      # is what carries `t()` onto the assembled struct.
      assert code =~ ":ok = validate(candidate)"
      refute code =~ "case validate(candidate)"
    end

    # The same reasoning carried through the rest: with nothing to report, `put/2`
    # answers `{:ok, struct}` and nothing else, and `put!/2` has nothing to raise.
    # A spec keeping its error half here would put an unreachable clause in the
    # user's module — a warning from the compiler, before dialyzer is even run.
    test "put and update drop their error half when no validator is declared" do
      code = rendered(@two_fields, [:a, :b], [], only: [:put, :put!, :update, :update!])

      assert code =~
               "@spec put(t(), %{optional(:a) => integer(), optional(:b) => atom()}) :: {:ok, t()}"

      assert code =~
               "@spec update(t(), %{optional(:a) => (integer() -> integer()), optional(:b) => (atom() -> atom())}) :: {:ok, t()}"

      refute code =~ "raise ArgumentError"
      assert code =~ "{:ok, value} = put(value, changes)"
    end

    # `only: [:new!]` inlines the assembly rather than delegating, and its
    # missing-key case is a clause of its own that raises directly. So the
    # expression it wraps cannot report anything unless a validator is declared.
    test "a standalone new! raises only where the assembly it inlines can fail" do
      code = rendered(@two_fields, [:a], [], only: [:new!])

      assert code =~ ":ok = __tsbuildervalidators_validate__(candidate)"
      assert code =~ "{:ok, value} ="
      assert code =~ "def new!(attrs) when is_map(attrs)"
      # the missing-key clause still raises on its own
      assert code =~ "__missing_keys__"

      checked = rendered(@two_fields, [:a], @a_validator, only: [:new!])
      assert checked =~ "raise ArgumentError"
    end

    test "new keeps its error half while a required key can be missing" do
      code = rendered(@two_fields, [:a, :b], [], only: [:new, :new!])

      assert code =~
               "@spec new(%{a: integer(), b: atom()}) :: {:ok, t()} | {:error, [String.t()]}"

      assert code =~ "raise ArgumentError"
    end

    test "new drops its error half when nothing is enforced and nothing is checked" do
      code = rendered(@two_fields, [], [], only: [:new, :new!])

      assert code =~
               "@spec new(%{optional(:a) => integer(), optional(:b) => atom()}) :: {:ok, t()}"

      refute code =~ "raise ArgumentError"
      refute code =~ "__missing_keys__"
    end
  end

  # The generated bodies name every field they touch. `struct/2` and
  # `Map.update!/3` take the field name as a runtime value and hand back a bare
  # `struct()`, which costs dialyzer both the module and every field type, so
  # the specs above would promise more than the code could be checked against.
  describe "assembly" do
    test "new builds one struct literal, enforced fields bound in the head" do
      code = rendered(@two_fields, [:a], @a_validator, only: [:new, :validate])

      assert code =~ "def new(%{a: enforced_a} = attrs)"
      assert code =~ "candidate = %__MODULE__{"
      assert code =~ "a: enforced_a,"
      assert code =~ "%{b: field} -> field"
    end

    test "new falls back to each field's declared default" do
      fields = [{:a, quote(do: integer()), nil}, {:b, quote(do: String.t()), "x"}]
      code = rendered(fields, [:a], [], only: [:new])

      assert code =~ ~s(_ -> "x")
    end

    test "put takes each field from the changes or leaves it as it was" do
      code = rendered(@two_fields, [:a], [], only: [:put])

      assert code =~ "%{a: field} -> field"
      assert code =~ "_ -> value.a"
      assert code =~ "_ -> value.b"
    end

    test "update applies each function to the field it names" do
      code = rendered(@two_fields, [:a], [], only: [:update])

      assert code =~ "%{a: fun} -> fun.(value.a)"
      assert code =~ "%{b: fun} -> fun.(value.b)"
    end

    test "nothing is assembled through struct/2, Map.update!/3 or a chain of updates" do
      code = rendered(@two_fields, [:a], @a_validator, [])

      refute code =~ "struct("
      refute code =~ "Map.update!"
      refute code =~ "candidate |"
    end

    # A key the struct does not declare is not in the argument type either, so
    # dialyzer reports it where it is written. Looking for one at runtime as well
    # would cost every call the price of a mistake the types already rule out.
    test "no runtime work goes into looking for keys the struct does not declare" do
      code = rendered(@two_fields, [:a], @a_validator, [])

      refute code =~ "map_size"
      refute code =~ "is_map_key"
      refute code =~ "Map.keys"
      refute code =~ "unknown"
    end
  end

  describe "new/1" do
    test "returns {:ok, struct} for a valid map" do
      assert {:ok, %Mixed{base: 1.0, count: 2, label: nil, note: "n"}} =
               Mixed.new(%{base: 1.0, count: 2})
    end

    test "accepts optional fields and applies defaults" do
      assert {:ok, %Mixed{label: "x", note: "other"}} =
               Mixed.new(%{base: 1.0, count: 2, label: "x", note: "other"})
    end

    test "reports missing required keys, all of them at once" do
      assert {:error, [message]} = Mixed.new(%{})
      assert message =~ "missing required key(s)"
      assert message =~ ":base"
      assert message =~ ":count"
    end

    # A key the struct does not declare is not in `new/1`'s argument type, so
    # dialyzer reports it where it is written. Nothing looks for one at runtime.
    test "ignores a key the struct does not declare" do
      assert {:ok, %Mixed{base: 1.0, count: 2}} = Mixed.new(%{base: 1.0, count: 2, typo: 3})
    end

    test "accepts any map when nothing is enforced" do
      assert {:ok, %Optionals{a: nil, b: nil}} = Optionals.new(%{})
    end
  end

  describe "validate/1" do
    test "returns :ok for a struct that satisfies every validator" do
      {:ok, config} = Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 32.0, beta_slow: 1.0})

      assert Validated.validate(config) == :ok
    end

    test "reports failures on a struct built by other means" do
      config = %Validated{base: -1.0, factor: 0.5, beta_fast: 1.0, beta_slow: 32.0}

      assert Validated.validate(config) ==
               {:error,
                [
                  "fn config -> config.base > 0 end",
                  "fn config -> config.factor >= 1.0 end",
                  "&(&1.beta_fast > &1.beta_slow)"
                ]}
    end

    test "raises for a struct of the wrong type" do
      other = Mixed.new!(%{base: 1.0, count: 1})
      assert_raise FunctionClauseError, fn -> Validated.validate(other) end
    end
  end

  describe "validators" do
    test "uses the whole fn as the failure message" do
      assert {:error, ["fn config -> config.factor >= 1.0 end"]} =
               Validated.new(%{base: 10.0, factor: 0.5, beta_fast: 32.0, beta_slow: 1.0})
    end

    test "uses the capture source as the failure message" do
      assert {:error, ["&(&1.beta_fast > &1.beta_slow)"]} =
               Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 1.0, beta_slow: 32.0})
    end

    test "collects every failure rather than stopping at the first" do
      assert {:error, errors} =
               Validated.new(%{base: -1.0, factor: 0.5, beta_fast: 1.0, beta_slow: 32.0})

      assert length(errors) == 3
    end

    test "honours an explicit message" do
      assert {:error, ["a must be positive" | _]} = Messaged.new(%{a: -3})
    end

    test "lets {:error, reason} replace the message" do
      assert {:error, ["3 is not even"]} = Messaged.new(%{a: 3})
    end

    test "validates defaults for fields left out of attrs" do
      assert {:error, ["fn s -> s.limit > 0 end"]} = WithDefaultChecked.new(%{})
      assert {:ok, %WithDefaultChecked{limit: 5}} = WithDefaultChecked.new(%{limit: 5})
    end

    test "does not run validators when a key is missing" do
      assert {:error, [message]} = Validated.new(%{base: -1.0})
      assert message =~ "missing required key(s)"
    end

    test "raises when a validator returns something unexpected" do
      error = assert_raise ArgumentError, fn -> Confused.new(%{a: 1}) end

      assert error.message =~ "returned :maybe"
      assert error.message =~ "expected true, :ok, false, or {:error, reason}"
    end
  end

  describe "new!/1" do
    test "returns the struct directly" do
      assert %Mixed{base: 1.0, count: 2} = Mixed.new!(%{base: 1.0, count: 2})
    end

    test "raises listing every reason" do
      error =
        assert_raise ArgumentError, fn ->
          Validated.new!(%{base: -1.0, factor: 0.5, beta_fast: 1.0, beta_slow: 32.0})
        end

      assert error.message =~ "cannot build"
      assert error.message =~ "* fn config -> config.base > 0 end"
      assert error.message =~ "* fn config -> config.factor >= 1.0 end"
    end

    test "raises on missing keys" do
      assert_raise ArgumentError, ~r/missing required key/, fn -> Mixed.new!(%{}) end
    end

    test "ignores a key the struct does not declare" do
      assert %Mixed{base: 1.0, count: 2} = Mixed.new!(%{base: 1.0, count: 2, typo: 3})
    end
  end

  describe "put/2" do
    setup do
      {:ok, config} = Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 32.0, beta_slow: 1.0})
      {:ok, config: config}
    end

    test "replaces the given fields and leaves the rest alone", %{config: config} do
      assert {:ok, updated} = Validated.put(config, %{factor: 2.0})

      assert updated.factor == 2.0
      assert updated.base == config.base
      assert updated.beta_fast == config.beta_fast
    end

    test "accepts an empty map", %{config: config} do
      assert {:ok, ^config} = Validated.put(config, %{})
    end

    test "revalidates the result", %{config: config} do
      assert {:error, ["fn config -> config.factor >= 1.0 end"]} =
               Validated.put(config, %{factor: 0.5})
    end

    test "catches a cross-field violation introduced by the change", %{config: config} do
      assert {:error, ["&(&1.beta_fast > &1.beta_slow)"]} =
               Validated.put(config, %{beta_slow: 100.0})
    end

    test "ignores a key the struct does not declare", %{config: config} do
      assert {:ok, ^config} = Validated.put(config, %{typo: 1})
    end

    test "requires a struct of the right type" do
      other = Mixed.new!(%{base: 1.0, count: 1})
      assert_raise FunctionClauseError, fn -> Validated.put(other, %{factor: 1.0}) end
    end
  end

  describe "put!/2" do
    setup do
      {:ok, config} = Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 32.0, beta_slow: 1.0})
      {:ok, config: config}
    end

    test "returns the updated struct directly", %{config: config} do
      assert %Validated{factor: 2.0, base: 10.0} = Validated.put!(config, %{factor: 2.0})
    end

    test "raises listing every reason", %{config: config} do
      error =
        assert_raise ArgumentError, fn ->
          Validated.put!(config, %{factor: 0.5, beta_slow: 100.0})
        end

      assert error.message =~ "cannot update"
      assert error.message =~ "* fn config -> config.factor >= 1.0 end"
      assert error.message =~ "* &(&1.beta_fast > &1.beta_slow)"
    end

    test "ignores a key the struct does not declare", %{config: config} do
      assert ^config = Validated.put!(config, %{typo: 1})
    end

    test "requires a struct of the right type" do
      other = Mixed.new!(%{base: 1.0, count: 1})
      assert_raise FunctionClauseError, fn -> Validated.put!(other, %{factor: 1.0}) end
    end
  end

  describe "update/2" do
    setup do
      {:ok, config} = Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 32.0, beta_slow: 1.0})
      {:ok, config: config}
    end

    test "applies each function to its field", %{config: config} do
      assert {:ok, updated} = Validated.update(config, %{factor: &(&1 * 2), base: &(&1 + 1.0)})

      assert updated.factor == 16.0
      assert updated.base == 11.0
      assert updated.beta_fast == config.beta_fast
    end

    test "accepts an empty map", %{config: config} do
      assert {:ok, ^config} = Validated.update(config, %{})
    end

    test "revalidates the result", %{config: config} do
      assert {:error, ["fn config -> config.factor >= 1.0 end"]} =
               Validated.update(config, %{factor: &(&1 * 0.0)})
    end

    test "ignores a key the struct does not declare", %{config: config} do
      assert {:ok, ^config} = Validated.update(config, %{typo: & &1})
    end

    test "requires a struct of the right type" do
      other = Mixed.new!(%{base: 1.0, count: 1})
      assert_raise FunctionClauseError, fn -> Validated.update(other, %{base: & &1}) end
    end
  end

  describe "update!/2" do
    setup do
      {:ok, config} = Validated.new(%{base: 10.0, factor: 8.0, beta_fast: 32.0, beta_slow: 1.0})
      {:ok, config: config}
    end

    test "returns the updated struct directly", %{config: config} do
      assert %Validated{factor: 16.0, base: 11.0} =
               Validated.update!(config, %{factor: &(&1 * 2), base: &(&1 + 1.0)})
    end

    test "raises listing every reason", %{config: config} do
      error =
        assert_raise ArgumentError, fn ->
          Validated.update!(config, %{factor: &(&1 * 0.0), beta_slow: &(&1 * 100.0)})
        end

      assert error.message =~ "cannot update"
      assert error.message =~ "* fn config -> config.factor >= 1.0 end"
      assert error.message =~ "* &(&1.beta_fast > &1.beta_slow)"
    end

    test "ignores a key the struct does not declare", %{config: config} do
      assert ^config = Validated.update!(config, %{typo: & &1})
    end

    test "requires a struct of the right type" do
      other = Mixed.new!(%{base: 1.0, count: 1})
      assert_raise FunctionClauseError, fn -> Validated.update!(other, %{base: & &1}) end
    end
  end
end
