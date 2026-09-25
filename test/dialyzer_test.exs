defmodule TypedStructBuilderValidators.DialyzerTest do
  @moduledoc """
  Checks that dialyzer can still see through the code the plugin generates.

  The unit tests assert what the generated functions do; these assert what
  dialyzer can prove about them. Both matter, because the specs are only worth
  something if the generated bodies keep their types visible: assembling a
  struct through `struct/2` or `Map.update!/3` compiles and behaves identically
  while quietly reducing every spec to a promise nothing checks.

  Excluded by default, since it needs a PLT. Run `mix dialyzer --plt` once, then
  `mix test --only dialyzer`.
  """

  use ExUnit.Case, async: false

  @moduletag :dialyzer
  @moduletag timeout: :timer.minutes(10)

  @fixtures "test/support/dialyzer_fixtures"

  # Every mistake in the fixture that dialyzer is expected to catch.
  @mistakes [
    :new_with_wrong_field_type,
    :new_without_an_enforced_field,
    :new_with_an_unknown_key,
    :new_bang_with_wrong_field_type,
    :put_with_wrong_field_type,
    :put_bang_with_an_unknown_key,
    :read_name_as_an_integer,
    :read_put_result_as_a_map,
    :read_validate_as_a_boolean,
    :update_with_an_updater_of_the_wrong_arity,
    :update_with_an_updater_that_is_not_a_function
  ]

  setup_all do
    # `:overspecs` is the one flag that compares each spec against what dialyzer
    # actually inferred, so it gets its own pass.
    {:ok, warnings: analyze([]), provable: analyze([:overspecs])}
  end

  describe "correct usage" do
    test "draws no warnings at all", %{warnings: warnings} do
      assert located(warnings, "correct.ex") == []
    end

    test "leaves the generated struct module clean", %{warnings: warnings} do
      assert located(warnings, "thing.ex") == []
    end

    # A struct with no validators generates a `validate/1` that can only answer
    # `:ok`, which is the shape most likely to leave an unreachable error branch
    # behind in the functions that call it.
    test "leaves a struct with no validators clean", %{warnings: warnings} do
      assert located(warnings, "plain.ex") == []
    end

    test "leaves the plugin itself clean", %{warnings: warnings} do
      assert located(warnings, "typed_struct_builder_validators.ex") == []
    end
  end

  describe "misuse of the generated functions" do
    test "is reported for every case the specs forbid", %{warnings: warnings} do
      reported = reported_functions(warnings)

      for mistake <- @mistakes do
        assert mistake in reported, """
        dialyzer did not report #{mistake}/_.

        The generated specs no longer rule it out, which means the generated
        code stopped carrying its types. Reported instead: #{inspect(reported)}
        """
      end
    end

    test "is not reported anywhere unexpected", %{warnings: warnings} do
      unexpected = reported_functions(warnings) -- @mistakes

      assert unexpected == [], """
      dialyzer reported functions the fixture does not expect to be wrong:
      #{inspect(unexpected)}
      """
    end
  end

  describe "the types dialyzer infers for the generated code" do
    # This is the one thing a passing spec does not tell you. `struct/2` and
    # `Map.update!/3` assemble the same struct at runtime, but reduce what
    # dialyzer infers to `(map()) -> {:ok, %{__struct__: atom()}}` — compatible
    # with every generated spec, and proof of none of them. Callers would not
    # notice, because dialyzer reads a remote function's spec rather than its
    # inferred type, so the misuse fixtures above stay just as red either way.
    # Only comparing the two directly catches it.
    test "prove the specs the plugin generated, rather than merely allowing them",
         %{provable: warnings} do
      lost =
        warnings
        |> Enum.filter(fn {tag, location, _payload} ->
          tag == :warn_contract_subtype and basename(location) in ["thing.ex", "plain.ex"]
        end)
        |> Enum.reject(&assembles_nothing?/1)
        |> Enum.filter(&result_lost_types?/1)
        |> Enum.map(&describe_contract/1)

      assert lost == [], """
      dialyzer cannot see what the generated code returns:

      #{Enum.join(lost, "\n")}
      The result it inferred has lost the struct, or the type of one of its
      fields. Check that the bodies still name every field they assemble, and
      that they still carry the assembled struct through a function specced to
      take `t()` — without that call, a field carried over from the struct in
      hand reads as `any()`.
      """
    end
  end

  # Runs the analysis over the fixtures and the plugin, with the warning flags
  # `mix dialyzer` uses plus whatever the caller adds.
  @spec analyze([atom()]) :: [tuple()]
  defp analyze(extra_flags) do
    :dialyzer.run(
      init_plt: plt(),
      files: beams(),
      warnings: Mix.Project.config()[:dialyzer][:flags] ++ extra_flags
    )
  rescue
    error in ErlangError ->
      case error.original do
        {:dialyzer_error, message} ->
          flunk("""
          dialyzer could not run:

          #{message}
          """)

        _other ->
          reraise(error, __STACKTRACE__)
      end
  end

  @spec plt() :: charlist()
  defp plt do
    in_plt_dir =
      case System.get_env("PLT_DIR") do
        nil -> []
        dir -> Path.wildcard(Path.join(dir, "*.plt"))
      end

    # dialyxir names the one holding the dependencies for `deps`.
    case Enum.filter(in_plt_dir ++ Path.wildcard("_build/*/*.plt"), &(&1 =~ ~r/deps|#{app()}/)) do
      [plt | _rest] ->
        String.to_charlist(plt)

      [] ->
        flunk("""
        no PLT to analyze against.

        Build one with `mix dialyzer --plt`, then run this suite again.
        """)
    end
  end

  @spec beams() :: [charlist()]
  defp beams do
    "_build/#{Mix.env()}/lib/#{app()}/ebin/*.beam"
    |> Path.wildcard()
    |> Enum.map(&String.to_charlist/1)
  end

  defp app, do: Mix.Project.config()[:app]

  # The fixture file a warning points at, if any.
  @spec located([tuple()], String.t()) :: [String.t()]
  defp located(warnings, wanted) do
    for {_tag, location, _payload} <- warnings,
        basename(location) == wanted,
        do: describe_warning(location)
  end

  @spec basename(tuple()) :: String.t()
  defp basename(location), do: location |> elem(0) |> to_string() |> Path.basename()

  # `validate/1` is the one generated function that assembles no struct, so it is
  # not what this test is about, and it is the one whose argument dialyzer is
  # bound to read as wider than the spec: its head is `%__MODULE__{}`, which tags
  # the struct without saying anything about the fields, while `t()` gives all of
  # them. Everything that does assemble a struct stays held to no warning at all,
  # on the argument side as much as the result — that is where the type would be
  # lost, and both halves say so. `validate/1` keeps its cover from the tests
  # above: a spec contradicting its body, or a clause it could never reach, is
  # reported with or without `:overspecs`.
  # Whether what dialyzer inferred has lost sight of the struct being assembled.
  #
  # Only the result is asked about. A narrower argument is what a strict spec
  # looks like from dialyzer's side: `put/2` declares the fields it accepts while
  # the body would survive any map, and rejects nothing at runtime because the
  # spec already ruled it out. Counting that against the generated code would
  # mean widening the specs until the bodies could be proven to match them, which
  # is the wrong direction — see CLAUDE.md.
  #
  # What the result must never lose is the struct itself or the type of a field.
  # That is what `struct/2` and `Map.update!/3` cost when they assemble it, and
  # it is what no longer holding the struct through a `t()`-specced call costs.
  @spec result_lost_types?(tuple()) :: boolean()
  defp result_lost_types?({_tag, _location, {_kind, [module, _name, _arity, _spec, inferred]}}) do
    result = result_of(inferred)

    not String.contains?(result, "'__struct__':='#{module}'") or
      Regex.match?(~r/(:=|=>)_[,}\s]/, result)
  end

  defp result_lost_types?(_warning), do: true

  # What a function type returns: its arguments are the leading parenthesized
  # group, so any other arrow — a `fun((...) -> ...)` among them — sits deeper.
  @spec result_of(charlist() | String.t()) :: String.t()
  defp result_of(type), do: type |> to_string() |> String.to_charlist() |> past_arguments(0)

  @spec past_arguments(charlist(), non_neg_integer()) :: String.t()
  defp past_arguments([?( | rest], depth), do: past_arguments(rest, depth + 1)

  defp past_arguments([?) | rest], 1),
    do: rest |> to_string() |> String.trim() |> String.trim_leading("->") |> String.trim()

  defp past_arguments([?) | rest], depth), do: past_arguments(rest, depth - 1)
  defp past_arguments([_other | rest], depth), do: past_arguments(rest, depth)
  defp past_arguments([], _depth), do: ""

  @spec assembles_nothing?(tuple()) :: boolean()
  defp assembles_nothing?({_tag, _location, {_kind, [_module, :validate, 1, _spec, _inferred]}}),
    do: true

  defp assembles_nothing?(_warning), do: false

  # A contract_subtype warning carries the spec and the inferred type as text.
  @spec describe_contract(tuple()) :: String.t()
  defp describe_contract({_tag, _location, {_kind, [module, name, arity, spec, inferred]}}) do
    """
      #{inspect(module)}.#{name}/#{arity}
        spec:     #{spec}
        inferred: #{inferred}
    """
  end

  defp describe_contract(warning), do: inspect(warning)

  # The fixture functions dialyzer named in a warning.
  #
  # A warning about a spec names its function in the payload but is located at
  # the `@spec` line, which sits above the `def` and so would be attributed to
  # the function before it. A warning about a call names the function being
  # called, not the one calling it, but is located inside the caller's body. So
  # the payload is preferred whenever it names a function the fixture defines,
  # and the line is only a fallback.
  @spec reported_functions([tuple()]) :: [atom()]
  defp reported_functions(warnings) do
    definitions = definitions()
    defined = MapSet.new(definitions, fn {_line, name} -> name end)

    warnings
    |> Enum.filter(fn {_tag, location, _payload} ->
      Path.basename(to_string(elem(location, 0))) == "mistakes.ex"
    end)
    |> Enum.map(fn {_tag, location, {_kind, args}} ->
      Enum.find(args, &(is_atom(&1) and MapSet.member?(defined, &1))) ||
        enclosing(definitions, line(location))
    end)
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  # `{line, name}` for every function head in the mistakes fixture.
  @spec definitions() :: [{pos_integer(), atom()}]
  defp definitions do
    Path.join(@fixtures, "mistakes.ex")
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {source, number} ->
      case Regex.run(~r/^\s*def ([a-z_][a-zA-Z0-9_?!]*)/, source) do
        [_match, name] -> [{number, String.to_atom(name)}]
        nil -> []
      end
    end)
  end

  @spec enclosing([{pos_integer(), atom()}], pos_integer()) :: atom() | nil
  defp enclosing(definitions, line) do
    definitions
    |> Enum.filter(fn {defined, _name} -> defined <= line end)
    |> List.last()
    |> case do
      {_defined, name} -> name
      nil -> nil
    end
  end

  defp line(location),
    do: location |> elem(1) |> then(&if(is_tuple(&1), do: elem(&1, 0), else: &1))

  defp describe_warning(location), do: "#{basename(location)}:#{line(location)}"
end
