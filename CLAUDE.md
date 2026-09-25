# TypedStructBuilderValidators

A `TypedStruct` plugin that generates typed, validating constructors and updaters.

## Types are never relaxed to make something pass

Never weaken a type, a spec, a validator, or a test rule in order to get a test
or a check to pass. Not the generated `@spec`s, not the plugin's own types, not
the rules the test suite holds the generated code to. If a check fails, the
generated code is what changes.

The types this plugin generates must be as precise and as strict as they can be
made. Where there is a choice between two correct designs, take the one that
catches more at compile time, even when it costs more to generate or to
maintain. A spec that accepts less than the body tolerates is the goal, not a
defect: the spec is what callers are held to, and the runtime is only what
survives a caller who ignored it.

Two consequences worth naming, because both have been got wrong here before:

  * Do not widen a generated spec so that dialyzer can prove it. Make the
    generated body carry the type instead. `struct/2`, `Map.update!/3`,
    `Map.get/3` and friends take a field name as a runtime value and hand back
    an untyped result; naming every field keeps the types in front of dialyzer.
    Carrying the assembled struct through a function specced to take `t()` is
    what tells dialyzer it is one.
  * Do not loosen an assertion in `test/dialyzer_test.exs` to accommodate a
    warning. That suite exists to catch exactly the kind of regression that
    still compiles, still passes every unit test, and quietly costs dialyzer
    its grip on the generated code.

## Runtime checks

Callers of this library are using `TypedStruct` and types, and the generated
specs already reject an undeclared key, a wrongly typed field and a missing
enforced key where they are written. Do not spend runtime work re-checking what
the types cover. Validators are the exception: they are the invariants a type
cannot state, which is the whole point of the library.

## Checks before handing work back

  * `mix test` — the unit suite, which reads the generated AST as well as
    running it
  * `mix test --only dialyzer` — needs a PLT; run `mix dialyzer --plt` once
  * `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`

A clean compile matters as much as a passing suite: the generated code lands in
the user's module, so a warning it provokes is a warning in their build. Check
with a forced rebuild (`rm -rf _build/test && mix test`), since warnings are
only emitted on compile.
