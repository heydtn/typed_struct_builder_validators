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
  only once the struct can be built at all: if a key is missing or unknown,
  `new/1` reports that and does not run them.

  Because the predicate is inlined, it must be a pure function of the struct; it
  cannot close over variables from the surrounding scope.
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
  def field(name, type, _opts, env) do
    Module.put_attribute(env.module, @fields_attribute, {name, type})
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

  # A field as `field/4` recorded it: its name and the AST of its type.
  @typep field_definition :: {atom(), Macro.t()}

  # A validator as `validator/1` recorded it: its AST and failure message.
  @typep validator_definition :: {Macro.t(), String.t()}

  # Whether a generated function is defined publicly or privately.
  @typep function_visibility :: :def | :defp

  # The option naming one of the three generated argument types.
  @typep type_name_option :: :fields_type_name | :changes_type_name | :updates_type_name

  @typep map_type :: {:%{}, [], [Macro.t()]}

  # What to generate for each `@generated`: the name to define it under and
  # its visibility, or nil when it is not generated at all. Every key is always
  # present; `plan/1` builds the map from `@generated`.
  @typep plan_config :: {atom(), function_visibility()} | nil
  @typep plan :: %{
           validate: plan_config(),
           new: plan_config(),
           new!: plan_config(),
           put: plan_config(),
           put!: plan_config(),
           update: plan_config(),
           update!: plan_config()
         }

  @doc false
  @spec __functions__([field_definition()], [atom()], [validator_definition()], keyword()) ::
          Macro.t()
  def __functions__(fields, enforced, validators, opts \\ []) do
    plan = plan(opts)
    known = for {name, _type} <- fields, do: name
    required = for {name, _type} <- fields, name in enforced, do: name

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
        new_fun(attrs, required, known, plan),
        new_bang_fun(attrs, required, known, plan),
        put_fun(changes, known, plan),
        put_bang_fun(changes, known, plan),
        update_fun(updates, known, plan),
        update_bang_fun(updates, known, plan)
      ]
      |> Enum.reject(&is_nil/1)

    {:__block__, [], definitions}
  end

  # Plans function visibility and naming of the methods.
  # When `:only` isn't specified, every one of the helpers is generated. When `:only` is present,
  # only the needed functions are compiled into the module. `validate/1` is used by many
  # of the other methods, this one is the only one which may show up in a private method form
  # in order to implement the others.
  @spec plan(keyword()) :: plan()
  defp plan(opts) do
    allowed = @type_names ++ [:only] ++ @generated
    given = Keyword.keys(opts)

    case given -- allowed do
      [] ->
        :ok

      unknown ->
        raise ArgumentError,
              "unknown option(s) #{inspect(unknown)} given to TypedStructBuilderValidators " <>
                "(expected any of: #{inspect(allowed)})"
    end

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

    @generated
    |> Map.new(fn default ->
      definition = if default in asked_for, do: {Map.fetch!(names, default), :def}
      {default, definition}
    end)
    |> Map.put(:validate, validate)
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
    {required, optional} = Enum.split_with(fields, fn {name, _type} -> name in enforced end)

    # Keyword-shorthand entries are only legal at the end of a map, so the
    # optional ones go first and the required ones render as `name: type()`.
    entries =
      for({name, type} <- optional, do: {{:optional, [], [name]}, type}) ++
        for({name, type} <- required, do: {name, type})

    {:%{}, [], entries}
  end

  @spec changes_type([field_definition()]) :: map_type()
  defp changes_type(fields) do
    {:%{}, [], for({name, type} <- fields, do: {{:optional, [], [name]}, type})}
  end

  @spec updates_type([field_definition()]) :: map_type()
  defp updates_type(fields) do
    entries =
      for {name, type} <- fields do
        {{:optional, [], [name]}, [{:->, [], [[type], type]}]}
      end

    {:%{}, [], entries}
  end

  @spec validate_fun([validator_definition()], plan()) :: Macro.t() | nil
  defp validate_fun(_validators, %{validate: nil}), do: nil

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
        case List.flatten(unquote(checks)) do
          [] -> :ok
          errors -> {:error, errors}
        end
      end
    end
    |> emit(kind)
  end

  # Builds the expression a generated function's body reduces to.
  # Rejects any key the struct does not declare, assembles the struct,
  # runs the validators over it, and finally evaluates to `{:ok, struct}`
  # or `{:error, reasons}`.
  # Only the assembly step differs — `built` starts from a bare map of attributes,
  # `replaced` overwrites fields on an existing struct, and `changed` passes
  # each named field through a function.
  @spec built([atom()], atom(), Macro.t()) :: Macro.t()
  defp built(known, validate, attrs) do
    candidate = Macro.var(:candidate, __MODULE__)

    quote do
      TypedStructBuilderValidators.__apply__(
        unquote(attrs),
        unquote(known),
        fn unquote(candidate) -> unquote(validate)(unquote(candidate)) end,
        fn -> struct(__MODULE__, unquote(attrs)) end
      )
    end
  end

  @spec replaced([atom()], atom(), Macro.t(), Macro.t()) :: Macro.t()
  defp replaced(known, validate, value, changes) do
    candidate = Macro.var(:candidate, __MODULE__)

    quote do
      TypedStructBuilderValidators.__apply__(
        unquote(changes),
        unquote(known),
        fn unquote(candidate) -> unquote(validate)(unquote(candidate)) end,
        fn -> struct(unquote(value), unquote(changes)) end
      )
    end
  end

  @spec changed([atom()], atom(), Macro.t(), Macro.t()) :: Macro.t()
  defp changed(known, validate, value, updates) do
    candidate = Macro.var(:candidate, __MODULE__)

    quote do
      TypedStructBuilderValidators.__apply__(
        unquote(updates),
        unquote(known),
        fn unquote(candidate) -> unquote(validate)(unquote(candidate)) end,
        fn ->
          Enum.reduce(unquote(updates), unquote(value), fn {key, fun}, acc ->
            Map.update!(acc, key, fun)
          end)
        end
      )
    end
  end

  @spec raising(Macro.t(), String.t()) :: Macro.t()
  defp raising(expression, action) do
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

  @spec enforced_pattern([atom()]) :: Macro.t()
  defp enforced_pattern(required_names) do
    {:%{}, [], for(name <- required_names, do: {name, Macro.var(:_, __MODULE__)})}
  end

  @spec new_fun(Macro.t(), [atom()], [atom()], plan()) :: Macro.t() | nil
  defp new_fun(_attrs_type, _required_names, _known, %{new: nil}), do: nil

  defp new_fun(attrs_type, required_names, known, %{new: {new, kind}, validate: {validate, _}})
       when is_atom(new) and is_atom(validate) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    required_pattern = enforced_pattern(required_names)
    body = built(known, validate, attrs)
    missing = missing_clause(required_names, new, attrs)

    quote do
      @spec unquote(new)(unquote(attrs_type)) :: {:ok, t()} | {:error, [String.t()]}
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

  @spec new_bang_fun(map_type(), [atom()], [atom()], plan()) :: Macro.t() | nil
  defp new_bang_fun(_attrs_type, _required_names, _known, %{new!: nil}), do: nil

  defp new_bang_fun(attrs_type, _required_names, _known, %{new!: {new!, kind}, new: {new, _}})
       when is_atom(new!) and is_atom(new) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    delegated = quote(do: unquote(new)(unquote(attrs)))
    body = raising(delegated, "build")

    quote do
      @spec unquote(new!)(unquote(attrs_type)) :: t()
      def unquote(new!)(unquote(attrs)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp new_bang_fun(attrs_type, required_names, known, %{
         new!: {new!, kind},
         new: nil,
         validate: {validate, _}
       })
       when is_atom(new!) and is_atom(validate) and kind in [:def, :defp] do
    attrs = Macro.var(:attrs, __MODULE__)
    required_pattern = enforced_pattern(required_names)
    missing = missing_bang_clause(required_names, new!, attrs)

    body =
      known
      |> built(validate, attrs)
      |> raising("build")

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

  @spec put_fun(map_type(), [atom()], plan()) :: Macro.t() | nil
  defp put_fun(_changes_type, _known, %{put: nil}), do: nil

  defp put_fun(changes_type, known, %{put: {put, kind}, validate: {validate, _}})
       when is_atom(put) and is_atom(validate) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)
    body = replaced(known, validate, value, changes)

    quote do
      @spec unquote(put)(t(), unquote(changes_type)) :: {:ok, t()} | {:error, [String.t()]}
      def unquote(put)(%__MODULE__{} = unquote(value), unquote(changes))
          when is_map(unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec put_bang_fun(map_type(), [atom()], plan()) :: Macro.t() | nil
  defp put_bang_fun(_changes_type, _known, %{put!: nil}), do: nil

  defp put_bang_fun(changes_type, _known, %{put!: {put!, kind}, put: {put, _}})
       when is_atom(put!) and is_atom(put) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)
    delegated = quote(do: unquote(put)(unquote(value), unquote(changes)))
    body = raising(delegated, "update")

    quote do
      @spec unquote(put!)(t(), unquote(changes_type)) :: t()
      def unquote(put!)(%__MODULE__{} = unquote(value), unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp put_bang_fun(changes_type, known, %{put!: {put!, kind}, put: nil, validate: {validate, _}})
       when is_atom(put!) and is_atom(validate) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    changes = Macro.var(:changes, __MODULE__)

    body =
      known
      |> replaced(validate, value, changes)
      |> raising("update")

    quote do
      @spec unquote(put!)(t(), unquote(changes_type)) :: t()
      def unquote(put!)(%__MODULE__{} = unquote(value), unquote(changes))
          when is_map(unquote(changes)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec update_fun(map_type(), [atom()], plan()) :: Macro.t() | nil
  defp update_fun(_updates_type, _known, %{update: nil}), do: nil

  defp update_fun(updates_type, known, %{update: {update, kind}, validate: {validate, _}})
       when is_atom(update) and is_atom(validate) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)
    body = changed(known, validate, value, updates)

    quote do
      @spec unquote(update)(t(), unquote(updates_type)) :: {:ok, t()} | {:error, [String.t()]}
      def unquote(update)(%__MODULE__{} = unquote(value), unquote(updates))
          when is_map(unquote(updates)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  @spec update_bang_fun(map_type(), [atom()], plan()) :: Macro.t() | nil
  defp update_bang_fun(_updates_type, _known, %{update!: nil}), do: nil

  defp update_bang_fun(updates_type, _known, %{update!: {update!, kind}, update: {update, _}})
       when is_atom(update!) and is_atom(update) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)
    delegated = quote(do: unquote(update)(unquote(value), unquote(updates)))
    body = raising(delegated, "update")

    quote do
      @spec unquote(update!)(t(), unquote(updates_type)) :: t()
      def unquote(update!)(%__MODULE__{} = unquote(value), unquote(updates)) do
        unquote(body)
      end
    end
    |> emit(kind)
  end

  defp update_bang_fun(updates_type, known, %{
         update!: {update!, kind},
         update: nil,
         validate: {validate, _}
       })
       when is_atom(update!) and is_atom(validate) and kind in [:def, :defp] do
    value = Macro.var(:value, __MODULE__)
    updates = Macro.var(:updates, __MODULE__)

    body =
      known
      |> changed(validate, value, updates)
      |> raising("update")

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
  @spec __apply__(map(), [atom()], (struct() -> :ok | {:error, [String.t()]}), (-> struct())) ::
          {:ok, struct()} | {:error, [String.t()]}
  def __apply__(given, known, validate, build)
      when is_function(validate, 1) and is_function(build, 0) do
    case Map.keys(given) -- known do
      [] ->
        value = build.()

        case validate.(value) do
          :ok -> {:ok, value}
          {:error, reasons} -> {:error, reasons}
        end

      unknown ->
        {:error, __unknown_keys__(unknown, known)}
    end
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
  @spec __unknown_keys__([atom()], [atom()]) :: [String.t()]
  def __unknown_keys__(unknown, known) do
    [
      "unknown key(s): #{Enum.map_join(unknown, ", ", &inspect/1)} " <>
        "(expected any of: #{Enum.map_join(known, ", ", &inspect/1)})"
    ]
  end

  @doc false
  @spec __message__(module(), String.t(), [String.t()]) :: String.t()
  def __message__(module, action, reasons) do
    "cannot #{action} #{inspect(module)}:\n" <> Enum.map_join(reasons, "\n", &("  * " <> &1))
  end
end
