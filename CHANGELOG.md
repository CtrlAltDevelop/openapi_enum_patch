# Changelog

## 1.0.0

First stable release. The API has settled across the `normalize`, `patch`,
`audit` and `reorganize` commands, so the package now commits to semantic
versioning — no breaking changes without a 2.0.0.

- **Breaking:** the SDK constraint is now `^3.13.0`. Verified against Dart
  3.13.0 and Flutter 3.47.0.
- Reformatted the whole package with the Dart 3.7+ formatter ("tall style").
  Formatting only — no behaviour changes.
- Bumped `args`, `meta`, `path`, `yaml`, `lints` and `test` to current.

## 0.2.0

- Added the `reorganize` command: groups the flat models `swagger_parser`
  emits into per-namespace folders, routes enums into an `enums/` subfolder,
  and strips the now-redundant namespace prefix from type names — rewriting
  every relative import, `part` directive, model URI and type reference across
  your sources. Cross-service name collisions keep their prefix so the result
  still compiles. Idempotent.
- Namespace groups are derived from the schema keys via
  `RegistryBuilder.namespacePrefixes`, so nothing has to be hard-coded; pass
  `groups` to `reorganizeModels` to override.
- **Breaking:** the `--config` and `--overrides` defaults are now
  `swagger_parser.yaml` and `enum_overrides.yaml` at the project root, instead
  of paths under a `swagger_tools/` folder. Pass `-c` / `-o` if your files live
  elsewhere.

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
