# Changelog

## 0.1.0

Initial release.

- `patch` command — synthesises the enum files `swagger_parser` skips for
  query-parameter-only enums, and applies `enum_overrides.yaml` to the rest.
- `normalize` command — rewrites `{version}` path templates to a concrete
  version and qualifies bare `components.schemas` names with a namespace
  prefix, rewriting every matching `$ref`. Both passes are idempotent.
- `audit` command — reports integer enums with no override, overrides that do
  not name every value, and overrides naming values the schema dropped.
- `--strict` makes a non-clean audit exit non-zero, for CI.
- Library API — `RegistryBuilder`, `EnumAuditor`, `SchemaNormalizer`,
  `EnumPatcher` — with an `EnumEmitter` interface for non-`dart_mappable`
  back-ends.
- Emitted compute helpers use the `dart_mappable` mapper API
  (`XMapper.fromValue`, `toValue()`), which works when `enums_to_json: false`.
