# Changelog

## 1.2.0

- New **`prepare`** command: rewrites an export into a shape a generator can
  make usable code out of, before `normalize` runs. Four opt-in passes, each
  idempotent, driven by a new `schema_prep.yaml`:
  - **`rename_schemas`** — exporters that inline their nested models name the
    resulting component after a hash of its shape
    (`e36568fca95941d68bfb36b27ea0de7e`), which generates a class nobody can
    read or import on purpose. Only the project knows what each one means, so
    the names come from config; every `$ref` is rewritten with them, and two
    entries may share a target so an exporter's duplicate shapes collapse onto
    one component.
  - **`hoist_enums`** — the same enum written inline on several properties
    generates one anonymous `Enum0`, `Enum1`, … per occurrence. Each occurrence
    whose values match becomes a `$ref` to a single named component.
  - **`json_only_requests`** — one request body declared under JSON,
    form-encoded and multipart makes the generator pick multipart, turning a
    plain POST into a per-field part list with no request model. The exact
    duplicates of the JSON schema are dropped; a media type declaring its own
    schema is left alone.
  - **`strip_response_envelopes`** — where the transport already strips a
    `{code, message, data, is_success}` wrapper, the response is pointed at its
    payload `$ref` so the client deserialises what actually reaches it. A
    schema qualifies only when every property it declares is a known envelope
    field, so a real model is never mistaken for a wrapper.
- Passes can be limited with `tags:`; the component passes then only touch the
  components those operations reach, so a schema shared with an unimplemented
  route is never rewritten on its behalf.
- `prepare` reports the hash-named components still in scope that it was given
  no name for, so the next run can name them instead of shipping the hash.
- New `--prep` / `-p` option (defaults to `schema_prep.yaml`; a missing file is
  not an error). New `SchemaPreparer`, `PreparationResult`, `SchemaPrep`,
  `SchemaPreps` and `EnumPatcher.prepareSchemas`, all exported.
- `audit --strict` now exits non-zero when the audit is not clean, as its help
  text always said. Previously `--strict` was honoured by `patch` only, so the
  read-only CI gate silently passed.
- README rewritten around the pipeline: the seven stages in order and what each
  one touches, the `scripts/generate_api.sh` runner to copy, what a run prints
  (first run and second), where the three config files live and which command
  reads which, and how to gate CI on `audit --strict` plus a clean tree.

## 1.1.0

- Schemas may now be **YAML as well as JSON**. Every command reads both, and a
  project can mix the two — the format comes from the file extension
  (`.yaml`/`.yml`/`.json`), falling back to sniffing the content for anything
  else.
- `normalize` writes each schema back in the format it read it in, so a YAML
  schema stays YAML. Multi-line strings are re-emitted as `|-` blocks and
  sequences keep the indentation OpenAPI exporters use, so the rewrite stays a
  small diff. Comments are not preserved.
- New `SchemaCodec`, `SchemaFormat` and `YamlEncoder`, all exported.
  `RegistryBuilder.decode` takes an optional `format`, and there is a
  `buildFromYaml` beside `buildFromJson`.
- `SchemaFormatException` moved from `registry_builder.dart` to
  `schema/schema_codec.dart`. No change if you import the package's single
  public library.
- Fixed `--version` reporting `0.2.0`.

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
