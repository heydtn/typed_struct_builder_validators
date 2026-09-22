# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/heydtn/typed_struct_builder_validators/releases/tag/v0.1.0
