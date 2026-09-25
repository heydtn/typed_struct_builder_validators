# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-24

### Changed

  * The generated functions assemble the struct as a single literal that names
    every field, where they used to call `struct/2`, `Map.update!/3` and
    `Enum.reduce/3`. Those take a field name as a runtime value and hand back a
    bare `struct()`, so dialyzer could see neither the module nor any field type
    through them, and every generated `@spec` was a promise it took on faith
    rather than one it checked. The assembled struct is also carried through
    `validate/1`, which is specced to take `t()`, so a field copied from the
    struct in hand keeps its declared type instead of reading as `any()`.
  * `validate/1` is generated as `@spec validate(t()) :: :ok` for a struct that
    declares no validators, since there is nothing it could report. On such a
    struct `put/2`, `put!/2`, `update/2` and `update!/2` are typed as
    `{:ok, t()}` and have nothing to raise, and `new/1` keeps its error half for
    as long as a key can be missing from the attributes it is given. Matching on
    `{:error, reasons}` from any of them is then a clause the compiler reports as
    unreachable.
  * `update/2` applies its functions in field declaration order rather than the
    order the updates map happens to iterate in. Each function still receives
    the value its own field held before the update, so this is only visible to
    functions with side effects.
  * Together these cut the work per call considerably: on an eight-field struct
    with two validators, `new/1` went from 268ns to 58ns given every field, and
    from 87ns to 45ns given only the two enforced ones. One struct is allocated
    per call rather than one per field written, and a passing `validate/1` now
    allocates nothing.

### Removed

  * The runtime rejection of a key the struct does not declare. Such a key is not
    in the generated argument types, so dialyzer reports it at the line that
    writes it, and paying for the same answer again on every call is work the
    types already did. A key that reaches a generated function anyway is ignored,
    where it used to come back as `{:error, ["unknown key(s): ..."]}`.

    This is the one change here that can break a caller: code matching on that
    error, or relying on an undeclared key being refused at runtime, no longer
    gets it. A missing *enforced* key is still reported as before.

## [0.1.0] - 2026-09-22

Initial release.

  * `plugin TypedStructBuilderValidators` generates `new/1`, `new!/1`,
    `validate/1`, `put/2`, `put!/2`, `update/2` and `update!/2` on a
    `typedstruct` block, each with a `@spec` built from the declared field types.
  * `validator/1` and `validator/2` declare predicates on the completed struct,
    inlined into `validate/1`, with the predicate's source as the default
    failure message.
  * `:only` narrows the generated set; passing a default name as an option
    renames that function.
  * `:fields_type_name`, `:changes_type_name` and `:updates_type_name` declare
    named types for the generated argument maps.

[0.2.0]: https://github.com/heydtn/typed_struct_builder_validators/releases/tag/v0.2.0
[0.1.0]: https://github.com/heydtn/typed_struct_builder_validators/releases/tag/v0.1.0
