defmodule TypedStructBuilderValidators do
  @moduledoc ~S"""
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

  `new/1`, `put/2` and `update/2` all perform `validate/1`, as do the raising
  variants.

  ## Specs

  Each generated function carries a `@spec` built from the declared field types:

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

  For `new/1`, fields that `TypedStruct` enforces are required keys and the rest
  are optional. For `put/2` and `update/2` every field is optional.

  `validate/1` collects all the problems it finds and returns them
  together, rather than stopping at the first.

  ## Naming the argument types

  If you'd like to use the type signatures used by any of the methods, you can
  provide a name to declare the type with that the spec then refers to:

      typedstruct module: Config, enforce: true do
        plugin TypedStructBuilderValidators, fields_type_name: :my_fields_type

        field :field1, String.t(), enforce: false
        field :field2, float()
      end

      # Generated
      @type my_fields_type :: %{optional(:field1) => String.t(), field2: float()}
      @spec new(my_fields_type()) :: {:ok, t()} | {:error, [String.t()]}

  so that you can use it elsewhere:

      @spec init(Config.my_fields_type()) :: t()

  The three maps are named separately:

    * `:fields_type_name` — the `new/1` argument
    * `:changes_type_name` — the `put/2` and `put!/2` argument
    * `:updates_type_name` — the `update/2` and `update!/2` argument

  Each takes a bare name, which defines a `@type`, or a `{name, kind}` pair
  where `kind` is one of `[:type, :typep, :opaque]`:

      plugin TypedStructBuilderValidators,
        fields_type_name: :attrs,
        changes_type_name: {:changes, :typep}

  ## Renaming the generated functions

  Any of these methods can be renamed by passing its default name as an option.
  The ones you leave out keep their defaults:

      typedstruct module: Config, enforce: true do
        plugin TypedStructBuilderValidators, new!: :build!, validate: :check

        field :field1, String.t()
      end

      Config.build!(%{field1: "x"})
      Config.check(config)
      Config.put(config, %{field1: "y"})

  ## Generating only some of them

  `:only` narrows the set to the methods you name:

      plugin TypedStructBuilderValidators, only: [:put, :put!]

  ## Validators

  `validator/1` takes a predicate on the completed struct:

      typedstruct enforce: true do
        plugin TypedStructBuilderValidators

        field :foo, float()
        field :bar, float()
        field :baz, non_neg_integer()

        validator fn c -> c.baz > 0 end
        validator &(&1.foo > &1.bar)
      end

  `validator/1` is a macro. The predicate is inlined into the final
  `validate/1` method. Its source doubles as the default failure message.
  The two above report `"fn c -> c.baz > 0 end"` and `"&(&1.foo > &1.bar)"`.
  Pass your own message as a second argument when the source is not self-explanatory:

      validator &(&1.foo > &1.bar), "foo must name a higher value than bar"

  A validator passes by returning `true` or `:ok`, and fails by returning
  `false` or `{:error, reason}`. Any other return raises, on the grounds that a
  validator returning something unexpected is a bug rather than a rejection.
  Returning `{:error, reason}` replaces the message, which is how to build one
  that quotes the offending value.

  Validators run against a built struct, so a field left out of `attrs` is
  checked with its declared default rather than skipped. In `new/1` they run
  only once the struct can be built at all: a missing enforced key is reported
  without running them.

  A key the struct does not declare is not in the argument types at all, so
  dialyzer reports it at the line that writes it. Nothing looks for one at
  runtime, and one that reaches a generated function anyway is ignored.

  Because the predicate is inlined, it must be a pure function of the struct; it
  cannot close over variables from the surrounding scope.
  With no `validator/1` declared there is nothing that can fail, so `validate/1`
  is generated as `@spec validate(t()) :: :ok` and the other functions skip the
  call. Matching on `{:error, reasons}` from it is then a branch dialyzer reports
  as unreachable, until the first validator is declared.
  """

  use TypedStruct.Plugin

  @prefix "tsbuildervalidators"

  @fields_attribute :"#{@prefix}_fields"
  @validators_attribute :"#{@prefix}_validators"
  @private_validate :"__#{@prefix}_validate__"

  @attributes [@fields_attribute, @validators_attribute]

  @impl true
  @spec init(keyword()) :: Macro.t()
  defmacro init(_opts) do
    quote do
      import TypedStructBuilderValidators, only: [validator: 1, validator: 2]

      Enum.each(unquote(@attributes), fn attribute ->
        Module.register_attribute(__MODULE__, attribute, accumulate: true)
      end)
    end
  end

  @doc """
  Registers a validator, using its own source as the failure message.
  """
  @spec validator(Macro.t()) :: Macro.t()
  defmacro validator(fun) do
    store(fun, Macro.to_string(fun))
  end

  @doc """
  Registers a validator with an explicit failure message.
  """
  @spec validator(Macro.t(), Macro.t()) :: Macro.t()
  defmacro validator(fun, message) do
    store(fun, message)
  end

  @spec store(Macro.t(), Macro.t()) :: Macro.t()
  defp store(fun, message) do
    quote do
      Module.put_attribute(
        __MODULE__,
        unquote(@validators_attribute),
        {unquote(Macro.escape(fun)), unquote(message)}
      )
    end
  end

  # TypedStruct runs the plugin callbacks from a @before_compile macro, so the
  # name and type arrive here as values during expansion. Recording them now,
  # rather than emitting code that records them later, is what lets
  # `__define__/1` read them back while it can still expand into definitions.
  @impl true
  @spec field(atom(), any(), keyword(), Macro.Env.t()) :: Macro.t()
  def field(name, type, opts, env) do
    # The default comes along so that `new/1` can name it for a field the given
    # attributes leave out. `TypedStruct` passes `nil` to `defstruct` when a field
    # declares no default, so reading it the same way keeps the two in step.
    default = Keyword.get(opts, :default)
    Module.put_attribute(env.module, @fields_attribute, {name, type, default})
    nil
  end

  # TypedStruct hands this callback the plugin options but not the module, so it
  # cannot reach the fields and validators that `field/4` and `validator/1`
  # accumulated. Expanding a macro instead gets us `__CALLER__`, and with it
  # those attributes as values, in the one phase where returned AST still
  # becomes definitions.
  @impl true
  @spec after_definition(keyword()) :: Macro.t()
  def after_definition(opts) do
    quote do
      require TypedStructBuilderValidators
      TypedStructBuilderValidators.__define__(unquote(Macro.escape(opts)))
    end
  end

  @doc false
  @spec __define__(keyword()) :: Macro.t()
  defmacro __define__(opts) do
    module = __CALLER__.module

    fields =
      module
      |> Module.get_attribute(@fields_attribute, [])
      |> Enum.reverse()

    validators =
      module
      |> Module.get_attribute(@validators_attribute, [])
      |> Enum.reverse()

    enforced = Module.get_attribute(module, :enforce_keys, [])

    # Clean up helper module attributes.
    Enum.each(@attributes, &Module.delete_attribute(module, &1))

    __functions__(fields, enforced, validators, opts)
  end

  @type_kinds [:type, :typep, :opaque]
  @type_names [:fields_type_name, :changes_type_name, :updates_type_name]
  @generated [:validate, :new, :new!, :put, :put!, :update, :update!]
  @bang %{new!: :new, put!: :put, update!: :update}

  # A field as `field/4` recorded it: its name, the AST of its type, and the
  # default it falls back to.
  @typep field_definition :: {atom(), Macro.t(), term()}

  # A validator as `validator/1` recorded it: its AST and failure message.
  @typep validator_definition :: {Macro.t(), String.t()}

  # Whether a generated function is defined publicly or privately.
  @typep function_visibility :: :def | :defp

  # The option naming one of the three generated argument types.
  @typep type_name_option :: :fields_type_name | :changes_type_name | :updates_type_name

  @typep map_type :: {:%{}, [], [Macro.t()]}

  # What to generate for each `@generated`: the name to define it under and
  # its visibility, or nil when it is not generated at all. Every key is always
  # present; `plan/3` builds the map from `@generated`.
  @typep plan_config :: {atom(), function_visibility()} | nil

  # What gets generated, under what names, and what its types can say.
  #
  # `:check` names the validate function every assembling body calls. The two
  # flags say whether there is anything for it to report: `:assembly_fallible?`
  # of an assembled struct, and `:new_fallible?` of `new/1`, which also answers
  # for a key missing from the attributes it was given.
  @typep plan :: %{
           validate: plan_config(),
           new: plan_config(),
           new!: plan_config(),
           put: plan_config(),
           put!: plan_config(),
           update: plan_config(),
           update!: plan_config(),
           check: atom() | nil,
           new_fallible?: boolean(),
           assembly_fallible?: boolean()
         }

  @doc false
  @spec __functions__([field_definition()], [atom()], [validator_definition()], keyword()) ::
          Macro.t()
  def __functions__(fields, enforced, validators, opts \\ []) do
    required = for {name, _type, _default} <- fields, name in enforced, do: name
    plan = plan(opts, validators, required)

    {attrs_type, attrs} =
      fields
      |> attrs_type(enforced)
      |> declare(opts, :fields_type_name)

    {changes_type, changes} =
      fields
      |> changes_type()
      |> declare(opts, :changes_type_name)

    {updates_type, updates} =
      fields
      |> updates_type()
      |> declare(opts, :updates_type_name)

    definitions =
      [
        attrs_type,
        changes_type,
        updates_type,
        validate_fun(validators, plan),
        new_fun(attrs, required, fields, plan),
        new_bang_fun(attrs, required, fields, plan),
        put_fun(changes, fields, plan),
        put_bang_fun(changes, fields, plan),
        update_fun(updates, fields, plan),
        update_bang_fun(updates, fields, plan)
      ]
      |> Enum.reject(&is_nil/1)

    {:__block__, [], definitions}
  end

  # Plans function visibility and naming of the methods.
  # When `:only` isn't specified, every one of the helpers is generated. When `:only` is present,
  # only the needed functions are compiled into the module. `validate/1` is used by many
  # of the other methods, this one is the only one which may show up in a private method form
  # in order to implement the others.
  @spec plan(keyword(), [validator_definition()], [atom()]) :: plan()
  defp plan(opts, validators, required) do
    recognized!(opts)
    asked_for = asked_for(opts)
    names = names(opts, asked_for)
    operations = Map.keys(@bang) ++ Map.values(@bang)
    validating? = Enum.any?(operations, &(&1 in asked_for))

    validate =
      cond do
        :validate in asked_for -> {Map.fetch!(names, :validate), :def}
        validating? -> {@private_validate, :defp}
        true -> nil
      end

    check =
      case validate do
        {name, _kind} -> name
        nil -> nil
      end

    @generated
    |> Map.new(fn default ->
      definition = if default in asked_for, do: {Map.fetch!(names, default), :def}
      {default, definition}
    end)
    |> Map.put(:validate, validate)
    |> Map.put(:check, check)
    |> Map.put(:assembly_fallible?, validators != [])
    |> Map.put(:new_fallible?, validators != [] or required != [])
  end

  @spec recognized!(keyword()) :: :ok
  defp recognized!(opts) do
    allowed = @type_names ++ [:only] ++ @generated

    case Keyword.keys(opts) -- allowed do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown option(s) #{inspect(unknown)} given to TypedStructBuilderValidators " <>
                "(expected any of: #{inspect(allowed)})"
    end
  end

  @spec asked_for(keyword()) :: [atom()]
  defp asked_for(opts) do
    case Keyword.get(opts, :only, @generated) do
      only when is_list(only) ->
        case only -- @generated do
          [] ->
            only

          unknown ->
            raise ArgumentError,
                  "expected only to name generated functions, got: #{inspect(unknown)} " <>
                    "(expected any of: #{inspect(@generated)})"
        end

      other ->
        raise ArgumentError,
              "expected only to be a list of function names, got: #{inspect(other)}"
    end
  end

  @spec names(keyword(), [atom()]) :: %{atom() => atom()}
  defp names(opts, asked_for) do
    renamed =
      opts
      |> Keyword.take(@generated)
      |> Keyword.keys()

    case renamed -- asked_for do
      [] ->
        :ok

      excluded ->
        raise ArgumentError,
              "cannot rename #{Enum.map_join(excluded, ", ", &inspect/1)}: " <>
                "not named in only"
    end

    names =
      Map.new(@generated, fn default ->
        case Keyword.get(opts, default, default) do
          name when is_atom(name) and name not in [nil, true, false] ->
            {default, name}

          other ->
            raise ArgumentError,
                  "expected #{default} to be renamed to an atom, got: #{inspect(other)}"
        end
      end)

    # Two functions sharing a name would otherwise fail much later, as a
    # clause-ordering or arity error in the generated module.
    duplicates =
      names
      |> Map.take(asked_for)
      |> Map.values()
      |> Enum.frequencies()
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> Enum.map(fn {name, _count} -> name end)

    if duplicates != [] do
      raise ArgumentError,
            "TypedStructBuilderValidators would define #{Enum.map_join(duplicates, ", ", &inspect/1)} " <>
              "more than once; give each renamed function a distinct name"
    end

    names
  end

  @spec emit(Macro.t(), function_visibility()) :: Macro.t()
  defp emit(ast, :def), do: ast
  defp emit(ast, :defp), do: Macro.prewalk(ast, &privatize/1)

  @spec privatize(Macro.t()) :: Macro.t()
  defp privatize({:def, meta, args}), do: {:defp, meta, args}
  defp privatize(other), do: other

  @spec declare(map_type(), keyword(), type_name_option()) ::
          {Macro.t() | nil, Macro.t()}
  defp declare(type, opts, key) do
    case Keyword.get(opts, key) do
      nil ->
        {nil, type}

      name when is_atom(name) ->
        {definition(:type, name, type), reference(name)}

      {name, kind} when is_atom(name) and kind in @type_kinds ->
        {definition(kind, name, type), reference(name)}

      other ->
        raise ArgumentError,
              "expected #{key} to be a type name, or a {name, kind} pair with kind " <>
                "in #{inspect(@type_kinds)}, got: #{inspect(other)}"
    end
  end

  @spec definition(atom(), atom(), Macro.t()) :: Macro.t()
  defp definition(kind, name, type) do
    {:@, [], [{kind, [], [{:"::", [], [reference(name), type]}]}]}
  end

  @spec reference(atom()) :: Macro.t()
  defp reference(name), do: {name, [], []}

  @spec attrs_type([field_definition()], [atom()]) :: map_type()
  defp attrs_type(fields, enforced) do
    {required, optional} = Enum.split_with(fields, fn {name, _type, _d} -> name in enforced end)

    # Keyword-shorthand entries are only legal at the end of a map, so the
    # optional ones go first and the required ones render as `name: type()`.
    entries =
      for({name, type, _d} <- optional, do: {{:optional, [], [name]}, type}) ++
        for({name, type, _d} <- required, do: {name, type})

    {:%{}, [], entries}
  end

  @spec changes_type([field_definition()]) :: map_type()
  defp changes_type(fields) do
    {:%{}, [], for({name, type, _d} <- fields, do: {{:optional, [], [name]}, type})}
  end

  @spec updates_type([field_definition()]) :: map_type()
  defp updates_type(fields) do
    entries =
      for {name, type, _default} <- fields do
        {{:optional, [], [name]}, [{:->, [], [[type], type]}]}
      end

    {:%{}, [], entries}
  end

  @spec validate_fun([validator_definition()], plan()) :: Macro.t() | nil
  defp validate_fun(_validators, %{validate: nil}), do: nil

  defp validate_fun([], %{validate: {validate, kind}})
       when is_atom(validate) and kind in [:def, :defp] do
    quote do
      @spec unquote(validate)(t()) :: :ok
      def unquote(validate)(%__MODULE__{}), do: :ok
    end
    |> emit(kind)
  end

  defp validate_fun(validators, %{validate: {validate, kind}})
       when is_atom(validate) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)

    checks =
      for {fun, message} <- validators do
        quote do
          TypedStructBuilderValidators.__error__(
            unquote(message),
            unquote(fun).(unquote(value))
          )
        end
      end

    quote do
      @spec unquote(validate)(t()) :: :ok | {:error, [String.t()]}
      def unquote(validate)(%__MODULE__{} = unquote(value)) do
        case unquote(collected(checks)) do
          [] -> :ok
          errors -> {:error, errors}
        end
      end
    end
    |> emit(kind)
  end

  # Joins what the validators reported. Each one answers with a list of none or
  # one message, so concatenating right to left costs nothing when they all pass:
  # `[] ++ x` is `x`. Collecting them in a list and flattening it, by contrast,
  # allocates a cons cell per validator on every call, passing or not.
  @spec collected([Macro.t(), ...]) :: Macro.t()
  defp collected(checks) do
    checks
    |> Enum.reverse()
    |> Enum.reduce(&quote(do: unquote(&1) ++ unquote(&2)))
  end

  # Builds the expression a generated function's body reduces to.
  # Rejects any key the struct does not declare, assembles the struct,
  # runs the validators over it, and finally evaluates to `{:ok, struct}`
  # or `{:error, reasons}`.
  # Only the assembly step differs — `built` starts from a bare map of attributes,
  # `replaced` overwrites fields on an existing struct, and `changed` passes
  # each named field through a function.
  #
  # All three assemble the struct as one literal that names every field, rather
  # than updating a candidate field by field. The literal keeps each field's
  # declared type in front of dialyzer, as `struct/2` and `Map.update!/3` would
  # not, and it allocates once: a struct update copies the whole struct, so
  # applying several of them in a row copies it several times over. On an
  # eight-field struct given every field, one literal measured 37ns against
  # 178ns for six chained updates.
  @spec built([field_definition()], [atom()], atom(), Macro.t(), boolean()) :: Macro.t()
  defp built(fields, required, check, attrs, fallible?) do
    entries =
      for {name, _type, default} <- fields do
        if name in required do
          {name, enforced_var(name)}
        else
          {name, taken(attrs, name, Macro.escape(default))}
        end
      end

    applied(check, entries, fallible?)
  end

  @spec replaced([field_definition()], atom(), Macro.t(), Macro.t(), boolean()) :: Macro.t()
  defp replaced(fields, check, value, changes, fallible?) do
    entries =
      for {name, _type, _default} <- fields do
        {name, taken(changes, name, access(value, name))}
      end

    applied(check, entries, fallible?)
  end

  @spec changed([field_definition()], atom(), Macro.t(), Macro.t(), boolean()) :: Macro.t()
  defp changed(fields, check, value, updates, fallible?) do
    entries =
      for {name, _type, _default} <- fields do
        {name, mapped(updates, name, access(value, name))}
      end

    applied(check, entries, fallible?)
  end

  # Wraps an assembly in the validation that follows it, which is the same
  # whichever way the struct was assembled.
  #
  # A key the struct does not declare is not in the argument type either, so
  # dialyzer reports it where it is written and nothing is spent looking for one
  # at runtime. A struct that declares no validators has nothing to check at all,
  # and says so by answering `{:ok, struct}` directly.
  @spec applied(atom(), keyword(Macro.t()), boolean()) :: Macro.t()
  defp applied(check, entries, true) do
    candidate = Macro.var(:candidate, __MODULE__)

    quote do
      unquote(candidate) = %__MODULE__{unquote_splicing(entries)}

      case unquote(check)(unquote(candidate)) do
        :ok -> {:ok, unquote(candidate)}
        {:error, reasons} -> {:error, reasons}
      end
    end
  end

  defp applied(check, entries, false) do
    candidate = Macro.var(:candidate, __MODULE__)

    quote do
      unquote(candidate) = %__MODULE__{unquote_splicing(entries)}
      :ok = unquote(check)(unquote(candidate))
      {:ok, unquote(candidate)}
    end
  end

  # `case given do %{name => field} -> field; _ -> absent end`, the value one
  # field of the literal takes.
  @spec taken(Macro.t(), atom(), Macro.t()) :: Macro.t()
  defp taken(given, name, absent) do
    field = Macro.var(:field, __MODULE__)

    quote do
      case unquote(given) do
        %{unquote(name) => unquote(field)} -> unquote(field)
        _ -> unquote(absent)
      end
    end
  end

  # The same, for `update/2`: the field's current value goes through the given
  # function. Reading from the original struct keeps each field independent of
  # the order they are assembled in.
  @spec mapped(Macro.t(), atom(), Macro.t()) :: Macro.t()
  defp mapped(updates, name, current) do
    fun = Macro.var(:fun, __MODULE__)

    quote do
      case unquote(updates) do
        %{unquote(name) => unquote(fun)} -> unquote(fun).(unquote(current))
        _ -> unquote(current)
      end
    end
  end

  # `value.name`
  @spec access(Macro.t(), atom()) :: Macro.t()
  defp access(value, name), do: {{:., [], [value, name]}, [no_parens: true], []}

  # The raising counterpart of an expression that evaluates to `{:ok, struct}` or
  # `{:error, reasons}`. Nothing raises when nothing can be reported, and then
  # matching the success is the whole of it.
  @spec raising(Macro.t(), String.t(), boolean()) :: Macro.t()
  defp raising(expression, action, true) do
    value = Macro.var(:value, __MODULE__)

    quote do
      case unquote(expression) do
        {:ok, unquote(value)} ->
          unquote(value)

        {:error, reasons} ->
          raise ArgumentError,
                TypedStructBuilderValidators.__message__(__MODULE__, unquote(action), reasons)
      end
    end
  end

  defp raising(expression, _action, false) do
    value = Macro.var(:value, __MODULE__)

    quote do
      {:ok, unquote(value)} = unquote(expression)
      unquote(value)
    end
  end

  # What a generated function's spec says it evaluates to.
  @spec outcome(boolean()) :: Macro.t()
  defp outcome(true), do: quote(do: {:ok, t()} | {:error, [String.t()]})
  defp outcome(false), do: quote(do: {:ok, t()})

  # Binds each enforced key in the function head, so the struct can be built
  # with those values in place instead of copied in afterwards.
  @spec enforced_pattern([atom()]) :: Macro.t()
  defp enforced_pattern(required_names) do
    {:%{}, [], for(name <- required_names, do: {name, enforced_var(name)})}
  end

  @spec enforced_var(atom()) :: Macro.t()
  defp enforced_var(name), do: Macro.var(:"enforced_#{name}", __MODULE__)

  @spec new_fun(Macro.t(), [atom()], [field_definition()], plan()) :: Macro.t() | nil
  defp new_fun(_attrs_type, _required_names, _fields, %{new: nil}), do: nil

  defp new_fun(attrs_type, required_names, fields, %{
         new: {new, kind},
         check: check,
         new_fallible?: reportable?,
         assembly_fallible?: fallible?
       })
       when is_atom(new) and is_atom(check) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    required_pattern = enforced_pattern(required_names)
    body = built(fields, required_names, check, attrs, fallible?)
    missing = missing_clause(required_names, new, attrs)

    quote do
      @spec unquote(new)(unquote(attrs_type)) :: unquote(outcome(reportable?))
      def unquote(new)(unquote(required_pattern) = unquote(attrs)) do
        unquote(body)
      end

      unquote(missing)
    end
    |> emit(kind)
  end

  # With nothing enforced the head above is `%{}`, which already matches every
  # map, so a fallback clause would be unreachable.
  @spec missing_clause([atom()], atom(), Macro.t()) :: Macro.t() | nil
  defp missing_clause([], _new, _attrs), do: nil

  defp missing_clause(required_names, new, attrs) do
    quote do
      def unquote(new)(unquote(attrs)) when is_map(unquote(attrs)) do
        {:error,
         TypedStructBuilderValidators.__missing_keys__(unquote(attrs), unquote(required_names))}
      end
    end
  end

  @spec new_bang_fun(map_type(), [atom()], [field_definition()], plan()) :: Macro.t() | nil
  defp new_bang_fun(_attrs_type, _required_names, _fields, %{new!: nil}), do: nil

  defp new_bang_fun(attrs_type, _required_names, _fields, %{
         new!: {new!, kind},
         new: {new, _},
         new_fallible?: fallible?
       })
       when is_atom(new!) and is_atom(new) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    delegated = quote(do: unquote(new)(unquote(attrs)))
    body = raising(delegated, "build", fallible?)

    quote do
      @spec unquote(new!)(unquote(attrs_type)) :: t()
      def unquote(new!)(unquote(attrs)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp new_bang_fun(attrs_type, required_names, fields, %{
         new!: {new!, kind},
         new: nil,
         check: check,
         assembly_fallible?: fallible?
       })
       when is_atom(new!) and is_atom(check) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    required_pattern = enforced_pattern(required_names)
    missing = missing_bang_clause(required_names, new!, attrs)

    body =
      fields
      |> built(required_names, check, attrs, fallible?)
      |> raising("build", fallible?)

    quote do
      @spec unquote(new!)(unquote(attrs_type)) :: t()
      def unquote(new!)(unquote(required_pattern) = unquote(attrs)) do
        unquote(body)
      end

      unquote(missing)
    end
    |> emit(kind)
  end

  @spec missing_bang_clause([atom()], atom(), Macro.t()) :: Macro.t() | nil
  defp missing_bang_clause([], _new!, _attrs), do: nil

  defp missing_bang_clause(required_names, new!, attrs) do
    quote do
      def unquote(new!)(unquote(attrs)) when is_map(unquote(attrs)) do
        raise ArgumentError,
              TypedStructBuilderValidators.__message__(
                __MODULE__,
                "build",
                TypedStructBuilderValidators.__missing_keys__(
                  unquote(attrs),
                  unquote(required_names)
                )
              )
      end
    end
  end

  @spec put_fun(map_type(), [field_definition()], plan()) :: Macro.t() | nil
  defp put_fun(_changes_type, _fields, %{put: nil}), do: nil

  defp put_fun(changes_type, fields, %{
         put: {put, kind},
         check: check,
         assembly_fallible?: fallible?
       })
       when is_atom(put) and is_atom(check) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)
    body = replaced(fields, check, value, changes, fallible?)

    quote do
      @spec unquote(put)(t(), unquote(changes_type)) :: unquote(outcome(fallible?))
      def unquote(put)(%__MODULE__{} = unquote(value), unquote(changes))
          when is_map(unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec put_bang_fun(map_type(), [field_definition()], plan()) :: Macro.t() | nil
  defp put_bang_fun(_changes_type, _fields, %{put!: nil}), do: nil

  defp put_bang_fun(changes_type, _fields, %{
         put!: {put!, kind},
         put: {put, _},
         assembly_fallible?: fallible?
       })
       when is_atom(put!) and is_atom(put) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)
    delegated = quote(do: unquote(put)(unquote(value), unquote(changes)))
    body = raising(delegated, "update", fallible?)

    quote do
      @spec unquote(put!)(t(), unquote(changes_type)) :: t()
      def unquote(put!)(%__MODULE__{} = unquote(value), unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp put_bang_fun(changes_type, fields, %{
         put!: {put!, kind},
         put: nil,
         check: check,
         assembly_fallible?: fallible?
       })
       when is_atom(put!) and is_atom(check) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)

    body =
      fields
      |> replaced(check, value, changes, fallible?)
      |> raising("update", fallible?)

    quote do
      @spec unquote(put!)(t(), unquote(changes_type)) :: t()
      def unquote(put!)(%__MODULE__{} = unquote(value), unquote(changes))
          when is_map(unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec update_fun(map_type(), [field_definition()], plan()) :: Macro.t() | nil
  defp update_fun(_updates_type, _fields, %{update: nil}), do: nil

  defp update_fun(updates_type, fields, %{
         update: {update, kind},
         check: check,
         assembly_fallible?: fallible?
       })
       when is_atom(update) and is_atom(check) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)
    body = changed(fields, check, value, updates, fallible?)

    quote do
      @spec unquote(update)(t(), unquote(updates_type)) :: unquote(outcome(fallible?))
      def unquote(update)(%__MODULE__{} = unquote(value), unquote(updates))
          when is_map(unquote(updates)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec update_bang_fun(map_type(), [field_definition()], plan()) :: Macro.t() | nil
  defp update_bang_fun(_updates_type, _fields, %{update!: nil}), do: nil

  defp update_bang_fun(updates_type, _fields, %{
         update!: {update!, kind},
         update: {update, _},
         assembly_fallible?: fallible?
       })
       when is_atom(update!) and is_atom(update) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)
    delegated = quote(do: unquote(update)(unquote(value), unquote(updates)))
    body = raising(delegated, "update", fallible?)

    quote do
      @spec unquote(update!)(t(), unquote(updates_type)) :: t()
      def unquote(update!)(%__MODULE__{} = unquote(value), unquote(updates)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp update_bang_fun(updates_type, fields, %{
         update!: {update!, kind},
         update: nil,
         check: check,
         assembly_fallible?: fallible?
       })
       when is_atom(update!) and is_atom(check) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)

    body =
      fields
      |> changed(check, value, updates, fallible?)
      |> raising("update", fallible?)

    quote do
      @spec unquote(update!)(t(), unquote(updates_type)) :: t()
      def unquote(update!)(%__MODULE__{} = unquote(value), unquote(updates))
          when is_map(unquote(updates)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @doc false
  @spec __error__(String.t(), term()) :: [String.t()]
  def __error__(_message, result) when result in [true, :ok], do: []
  def __error__(message, false), do: [message]
  def __error__(_message, {:error, reason}), do: [to_string(reason)]

  def __error__(message, other) do
    raise ArgumentError,
          "the validator #{inspect(message)} returned #{inspect(other)}; " <>
            "expected true, :ok, false, or {:error, reason}"
  end

  @doc false
  @spec __missing_keys__(map(), [atom()]) :: [String.t()]
  def __missing_keys__(attrs, required) do
    missing = Enum.reject(required, &Map.has_key?(attrs, &1))

    ["missing required key(s): #{Enum.map_join(missing, ", ", &inspect/1)}"]
  end

  @doc false
  @spec __message__(module(), String.t(), [String.t()]) :: String.t()
  def __message__(module, action, reasons) do
    "cannot #{action} #{inspect(module)}:\n" <> Enum.map_join(reasons, "\n", &("  * " <> &1))
  end
end
