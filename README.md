# openapi_enum_patch

Give real names to the integer enums [`swagger_parser`][sp] generates, fill in
the enum files it skips, and audit which enums still need naming.

[sp]: https://pub.dev/packages/swagger_parser

## The problem

OpenAPI carries **no member names for integer enums** — only the numbers. So a
generated client ends up like this:

```dart
if (account.status == CrmEnumsAccountStatus.value2) { … }
```

There is no way to fix that from the schema alone, and no `swagger_parser`
option for it. This package lets you supply the names once, in a YAML file, and
reapplies them automatically after every regeneration.

```dart
if (account.status == CrmEnumsAccountStatus.disabled) { … }
```

It also tells you which enums you have **not** named yet — the part that
otherwise silently rots as the API grows.

## Requirements

Dart SDK `^3.13.0` — verified against Dart 3.13.0 and Flutter 3.47.0. This is a
pure Dart CLI package, so it carries no Flutter SDK constraint and works from
either a `dart` or a `flutter` project.

## Install

```bash
dart pub add --dev openapi_enum_patch
```

Or add it to `pubspec.yaml` yourself. It is a build-time tool, so it belongs in
`dev_dependencies` — it never ships in your app:

```yaml
dev_dependencies:
  openapi_enum_patch: ^1.0.0
  swagger_parser: ^1.44.1   # the generator this wraps
```

then:

```bash
dart pub get      # or: flutter pub get
```

## Use

Two commands wrap your existing generation step:

```bash
dart run openapi_enum_patch normalize          # before swagger_parser
dart run swagger_parser
dart run openapi_enum_patch patch              # after swagger_parser
dart run openapi_enum_patch reorganize         # before build_runner
dart run build_runner build --delete-conflicting-outputs
```

| Command | When | What it does |
| --- | --- | --- |
| `normalize` | Before | Fixes `{version}` path templates and bare schema names |
| `patch` | After | Writes skipped enum files, applies overrides, prints the audit |
| `reorganize` | After `patch` | Groups flat models into per-namespace folders |
| `audit` | Any time | Prints the audit only, changing nothing |

| Option | Default |
| --- | --- |
| `-r, --root` | `.` |
| `-c, --config` | `swagger_parser.yaml` |
| `-o, --overrides` | `enum_overrides.yaml` |
| `--strict` | off — exit non-zero when the audit is not clean |

The schema list, output directory and `use_flutter_compute` are read straight
out of your `swagger_parser.yaml`, so nothing is configured twice.

## Naming enums

```yaml
enums:
  "CRM.Enums.AccountStatus":
    names:
      0: active
      1: archived
      2: disabled
    extra:        # values the API returns but the schema does not declare yet
      - 3
```

Values without a name still generate as `valueN`. Names colliding with a Dart
reserved word get a `$` suffix. String enums never need an override — their
member names come from the values.

## The audit

Every `patch` run ends with a coverage report:

```
  ── Enum override audit ──────────────────────────────────────────
  MISSING OVERRIDE (2): integer enums generate as value0, value1, …
    - CRM.Enums.BSCDepositStatus  (CrmEnumsBscDepositStatus)  values: [0, 1, 2]
    - SocialService.InvestorStatus  (SocialServiceInvestorStatus)  values: [0, 1]
  MISSING NAMES (1): override exists but does not name every value
    - CRM.Enums.AccountStatus  (CrmEnumsAccountStatus)  unnamed: [3]
  STALE NAMES (1): override names a value absent from the schema
    - CRM.Enums.AccountStatus  (CrmEnumsAccountStatus)  unknown: [9]
  ─────────────────────────────────────────────────────────────────
```

- **MISSING OVERRIDE** — no entry at all. Add one.
- **MISSING NAMES** — the entry exists but does not cover every value.
- **STALE NAMES** — names a value the schema dropped, usually after a refresh.
  Remove it, or move it to `extra` if the API still returns it.

Only enums actually generated for your project are considered, so unused schema
enums stay quiet. The audit is report-only unless you pass `--strict`, which
makes it a CI gate.

## What `normalize` fixes

**`{version}` path templates.** Some services export
`/api/v{version}/Plan/List` with a required `version` path parameter. An
`include_paths` filter written with a concrete version never matches the
templated key, so the route is silently skipped — and if it did match,
`{version}` would leak into every generated method signature. `normalize`
substitutes the concrete version (read from `info.version`) and drops the
parameter.

**Bare schema names.** Most services export fully-qualified component names
(`IBService.AccountTypes.AccountTypeResult`), which become prefixed file names.
Services that export bare names (`AccountData`) produce unprefixed files that
collide with another service's models. `normalize` prepends `<SchemeName>.` to
every schema and rewrites all matching `$ref`s.

> `replacement_rules` cannot do this: it applies to class definitions but not to
> `$ref`-resolved type names, so definitions and references would diverge and
> imports would break.

Both passes are **idempotent** — re-downloading a schema and re-running is safe.

## What `reorganize` fixes

`swagger_parser` names every model after its full namespace and writes them all
into one flat folder:

```
models/crm_account_types_admin_dtos_account_type_feature_dto.dart
class CrmAccountTypesAdminDtosAccountTypeFeatureDto
```

`reorganize` groups them by namespace and drops the prefix that the folder now
carries:

```
models/crm/account_types_admin_dtos_account_type_feature_dto.dart
class AccountTypesAdminDtosAccountTypeFeatureDto
```

Enums additionally lose their `Enums` segment, since they land in an `enums/`
subfolder: `crm_enums_account_status` becomes `crm/enums/account_status.dart`
holding `AccountStatus`.

It rewrites everything that pointed at the old names — relative imports and
`part` directives inside the generated tree, and model URIs plus type
references (including dart_mappable's `Mapper` / `CopyWith` derivatives) across
`lib/` and `test/`.

Groups come from the first dotted segment of each schema key, so nothing is
hard-coded. When two namespaces define the same type name, **both keep their
prefix** — the files never collide because they are in different folders, but
the types would, so stripping is skipped for exactly those.

Run it after `patch` and before `build_runner`; the `.mapper.dart` parts move
with their source and are regenerated afterwards. Re-running is a no-op.

## Why `patch` generates files at all

`swagger_parser` only emits model files for schemas used in a request or
response **body**. An enum used solely as a **query parameter** gets imported by
the generated client but never written, which fails the build. `patch` detects
those dangling imports and synthesises the file from the schema.

## Library API

```dart
import 'package:openapi_enum_patch/openapi_enum_patch.dart';

final config = SwaggerParserConfig.parse(configYaml);
final overrides = EnumOverrides.parse(overridesYaml);
final patcher = EnumPatcher(root: '.', config: config);

final result = patcher.patch(overrides);
print(const AuditFormatter().format(result.report));
```

To target a serializer other than `dart_mappable`, implement `EnumEmitter` and
pass it to `EnumPatcher`; the registry, override and audit machinery is
unchanged. `RegistryBuilder`, `EnumAuditor` and `SchemaNormalizer` are all pure
and usable on their own.

## Scope

This package covers what is **general to any OpenAPI + `swagger_parser`
project**: enum naming, the audit, missing-file synthesis, schema
normalisation and the namespace reorganisation.

It deliberately does **not** ship the regex fix-ups a given project may need for
a specific combination of `swagger_parser`, `retrofit` and `dart_mappable`
versions — those patch bugs that come and go between releases, and applying them
blindly to another project's output would do harm. Keep those in your own repo.

## License

MIT
