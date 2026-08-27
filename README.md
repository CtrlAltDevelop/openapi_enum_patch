# openapi_enum_patch

Prepare an OpenAPI export for code generation, give real names to the integer
enums [`swagger_parser`][sp] generates from it, fill in the enum files it skips,
and audit which enums still need naming.

[sp]: https://pub.dev/packages/swagger_parser

## The problem

OpenAPI carries **no member names for integer enums** — only the numbers. So a
generated client ends up like this:

```dart
if (account.status == CrmEnumsAccountStatus.value2) { … }
```

There is no `swagger_parser` option for it. This package lets you supply the
names once, in a YAML file, and reapplies them automatically after every
regeneration — and where the export kept the names in a vendor extension
(`x-enum-varnames` and friends), it reads them straight out of the schema and
you supply nothing.

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
  openapi_enum_patch: ^1.2.0
  swagger_parser: ^1.44.1   # the generator this wraps
```

then:

```bash
dart pub get      # or: flutter pub get
```

## Use

### The pipeline

Generation is a fixed sequence: two of these commands run before
`swagger_parser`, one after it, and one before `build_runner`.

```bash
dart run openapi_enum_patch prepare                      # 1. shape the exports
dart run openapi_enum_patch normalize                    # 2. paths and names
dart run swagger_parser                                  # 3. generate
dart run openapi_enum_patch patch                        # 4. enums + audit
dart run openapi_enum_patch reorganize                   # 5. group models
dart run build_runner build --delete-conflicting-outputs  # 6. serializers
dart format lib/generated                                # 7. optional
```

| # | Stage | What it does |
| --- | --- | --- |
| 1 | `prepare` | Applies the `schema_prep.yaml` passes to each export: names hash-named components, hoists repeated inline enums, keeps one request media type, points responses at their payload. Schemes with no entry pass straight through |
| 2 | `normalize` | Substitutes `{version}` in path templates and qualifies bare schema names, so `include_paths` matches and services cannot collide |
| 3 | `swagger_parser` | Generates the Retrofit clients and models |
| 4 | `patch` | Writes the enum files the generator skipped, applies `enum_overrides.yaml`, prints the audit |
| 5 | `reorganize` | Groups the flat models into per-namespace folders and strips the now-redundant prefix from their type names |
| 6 | `build_runner` | `dart_mappable` / Retrofit codegen |
| 7 | `dart format` | Neither generator formats what it writes, so without this every run rewrites the tree with different line breaks and buries the real change in whitespace |

`audit` is the odd one out: it prints stage 4's report without writing anything,
so it is safe to run any time — in CI with `--strict`, for instance.

Stages 1, 2, 4 and 5 are all **idempotent**. Re-downloading a schema and
re-running the whole pipeline is the normal way to work.

### As one script

Drop this in `scripts/generate_api.sh` and the whole pipeline becomes
`bash scripts/generate_api.sh` from anywhere in the repo. This is the runner
from the project this package was extracted from:

```bash
#!/usr/bin/env bash
# Regenerate all API clients from the OpenAPI schemas in openapi/.
#
# Usage (from anywhere):  bash scripts/generate_api.sh
#
# Every stage lives in the openapi_enum_patch dev_dependency; openapi/ holds
# only this project's data (schemas + three config files). This script is just
# the running order.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="openapi/swagger_parser.yaml"
OVERRIDES="openapi/enum_overrides.yaml"
PREP="openapi/schema_prep.yaml"

step() { printf '\n==> %s\n' "$1"; }

step "Preparing exports (names, inline enums, media types, envelopes)..."
dart run openapi_enum_patch prepare -c "$CONFIG" -o "$OVERRIDES" -p "$PREP"

step "Normalizing {version} templates and schema names..."
dart run openapi_enum_patch normalize -c "$CONFIG" -o "$OVERRIDES"

step "Generating clients and models..."
dart run swagger_parser -f "$CONFIG"

step "Filling in skipped enums and applying overrides..."
dart run openapi_enum_patch patch -c "$CONFIG" -o "$OVERRIDES"

step "Reorganizing models into per-namespace folders..."
dart run openapi_enum_patch reorganize -c "$CONFIG" -o "$OVERRIDES"

step "Running build_runner (dart_mappable / Retrofit codegen)..."
dart run build_runner build --delete-conflicting-outputs

# Neither swagger_parser nor build_runner formats what it writes, so without
# this every run rewrites the whole tree with different line breaks and buries
# the real change in whitespace.
step "Formatting the generated output..."
dart format lib/generated

step "Done."
```

A run then reads like this — each stage says what it touched, and nothing else:

```
==> Preparing exports (names, inline enums, media types, envelopes)...
  website_service: renamed 10 schemas, hoisted 3 inline enums, dropped 32 non-JSON request bodies, stripped 16 envelopes

==> Normalizing {version} templates and schema names...
  Normalized schema names → WebsiteService.* (108)

==> Filling in skipped enums and applying overrides...
  Generated (missing): crm_enums_account_status.dart
  Overridden (names, +1 values): social_service_copy_trade_type.dart

  ── Enum override audit ──────────────────────────────────────────
  All generated integer enums are fully overridden.
  ─────────────────────────────────────────────────────────────────

==> Reorganizing models into per-namespace folders...
  moved 367 models into 5 namespace folders; renamed 344 classes, kept 23 prefixed to avoid collisions
```

On a second run with nothing changed, stages 1 and 2 report `already prepared`
and `Schemas already normalized.` and write nothing.

### Where things live

Only your own data sits in the repo; every stage above comes from the
dev_dependency:

```
openapi/
├── swagger_parser.yaml    # the generator's config — routes, output dir, options
├── enum_overrides.yaml    # enum member names            (used by patch/audit)
├── schema_prep.yaml       # per-export preparation passes (used by prepare)
└── schemas/
    ├── crm_service.json
    └── website_service.yaml
```

Point the commands at them with `-c`, `-o` and `-p`, or keep the defaults by
running from the directory that holds them. All three paths are resolved
relative to `--root`:

| Option | Default | Used by |
| --- | --- | --- |
| `-r, --root` | `.` | all — the project root the paths below are relative to |
| `-c, --config` | `swagger_parser.yaml` | all |
| `-o, --overrides` | `enum_overrides.yaml` | `patch`, `audit` |
| `-p, --prep` | `schema_prep.yaml` | `prepare` |
| `--strict` | off | `patch`, `audit` — exit non-zero when the audit is not clean |

A missing `enum_overrides.yaml` or `schema_prep.yaml` is not an error: the
commands that read them simply have nothing to do.

The schema list, output directory and `use_flutter_compute` are read straight
out of your `swagger_parser.yaml`, so nothing is configured twice — adding a
service to the generator adds it here too.

### In CI

`audit` re-runs stage 4's report over the current output without writing
anything, and `--strict` turns it into a gate — it exits non-zero while any
integer enum is unnamed:

```bash
dart run openapi_enum_patch audit --strict
```

Pair it with a check that generation is reproducible — run the script and fail
on a dirty tree:

```bash
bash scripts/generate_api.sh
git diff --exit-code -- lib/generated openapi
```

## Schema formats

Schemas may be **JSON or YAML** — every command reads both, and a project can
mix the two:

```yaml
swagger_parser:
  output_directory: lib/api_clients
  schemes:
    - name: crm
      schema_path: api/crm.json
    - name: website
      schema_path: api/website.yaml    # .yaml and .yml work the same
```

The format comes from the file extension (`.yaml`/`.yml` → YAML, `.json` →
JSON). For any other extension the content is sniffed: a document opening with
`{` or `[` is read as JSON, anything else as YAML.

`normalize` writes each schema back in the format it read it in, so a YAML
schema stays YAML. It regenerates the file from the parsed document, which
means **comments and blank lines in a YAML schema are not preserved** — fine
for a downloaded schema, worth knowing if you hand-edit one. Multi-line
`description` fields stay readable as `|-` blocks, and anything that would read
back as a number, a boolean or `null` is quoted.


## Naming enums

Names come from two places, and the first one that has a name for a value wins:

1. **`enum_overrides.yaml`** — what this project decided the members are called.
2. **The export itself** — the member names most exporters write into a vendor
   extension even though OpenAPI has no field for them.

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

Values without a name still generate as `valueN`. String enums never need an
override — their member names come from the values.

Every name is made into a legal identifier before it is emitted: characters
Dart does not allow become `_` (`in progress` → `in_progress`), a leading digit
gets a `$` in front of it (`2fa` → `$2fa`), and a reserved word gets one after
it (`class` → `class$`). Two values asking for the same name are emitted as
`name$1` and `name$2` and reported by the audit — a collision is a naming
mistake to fix, not something to resolve silently.

### Names the export already carries

An integer enum is only nameless because OpenAPI has nowhere to put the names.
Most exporters keep them anyway, in one of three extensions, and `patch` reads
all three — so an export that carries them needs no `enum_overrides.yaml` entry
at all:

```yaml
components:
  schemas:
    CRM.Enums.AccountStatus:
      type: integer
      enum: [0, 1, 2]
      x-enum-varnames: [active, archived, disabled]   # openapi-generator
```

| Extension | Written by |
| --- | --- |
| `x-enum-varnames` | openapi-generator, drf-spectacular |
| `x-enumNames` (or `x-enum-names`) | NSwag and the .NET exporters |
| `x-ms-enum: {values: [{value: 0, name: Active}]}` | AutoRest, Azure |

The list forms run parallel to `enum` and are zipped with it, so a truncated or
partly blank list still names the values it reaches; the audit asks for the
rest. `x-ms-enum` pairs each name with its value, so its order does not matter.

An `enum_overrides.yaml` entry outranks the export value by value, which means a
project can rename just the members it disagrees with and leave the rest to the
exporter. Nothing has to be turned on: an export without these extensions
behaves exactly as before.

## The audit

Every `patch` run ends with a coverage report:

```
  ── Enum override audit ──────────────────────────────────────────
  MISSING OVERRIDE (2): integer enums generate as value0, value1, …
    - CRM.Enums.BSCDepositStatus  (CrmEnumsBscDepositStatus)  values: [0, 1, 2]
    - SocialService.InvestorStatus  (SocialServiceInvestorStatus)  values: [0, 1]
  MISSING NAMES (1): the names given do not cover every value
    - CRM.Enums.AccountStatus  (CrmEnumsAccountStatus)  unnamed: [3]
  STALE NAMES (1): override names a value absent from the schema
    - CRM.Enums.AccountStatus  (CrmEnumsAccountStatus)  unknown: [9]
  DUPLICATE NAMES (1): two values share one member name, emitted as name$1, name$2
    - CRM.Enums.Tier  (CrmEnumsTier)  shared by "gold": [2, 5]
  4 enum(s) took their member names from the export itself; no override needed.
  ─────────────────────────────────────────────────────────────────
```

- **MISSING OVERRIDE** — nothing names it, export included. Add an entry.
- **MISSING NAMES** — the names it does have do not cover every value.
- **STALE NAMES** — names a value the schema dropped, usually after a refresh.
  Remove it, or move it to `extra` if the API still returns it.
- **DUPLICATE NAMES** — two values resolved to one Dart member name, so they
  were emitted as `gold$1` and `gold$2`. Rename one of them.

Only enums actually generated for your project are considered, so unused schema
enums stay quiet. Duplicate names are checked for string enums too, since a
schema declaring both `Draft` and `draft` folds them onto one member without any
override being involved. The audit is report-only unless you pass `--strict`, which
makes it a CI gate.

## What `prepare` fixes

Some exporters — drf-spectacular among them — emit documents that are valid
OpenAPI and still generate code nobody can use. `prepare` answers four of those
habits, and only the ones you turn on, from a `schema_prep.yaml` beside your
`swagger_parser.yaml`:

```yaml
schemas:
  website_service:            # a scheme name from swagger_parser.yaml
    tags: [Calculators]       # limit every pass to these operations
    rename_schemas:
      e36568fca95941d68bfb36b27ea0de7e: PipValueAdditionalInfo
      Row: PivotPointRow
    hoist_enums:
      TradeDirection: [buy, sell]
    json_only_requests: true
    strip_response_envelopes: true
```

**Hash-named components.** An exporter that inlines its nested models names the
resulting component after a hash of its shape, so the generator writes a class
called `E36568fca95941d68bfb36b27ea0de7e`. Only you know what each one means, so
`rename_schemas` supplies the name and every `$ref` is rewritten with it. Two
entries may share a target, which collapses an exporter's duplicate shapes onto
one component. A name resolves whether or not `normalize` has already qualified
it, and a name that would shadow a type from your own framework (`Row`) is
qualified here too.

**Repeated inline enums.** The same enum written inline on three properties is
three anonymous enums to a generator: `Enum0`, `Enum1`, `Enum2`. Every inline
enum in scope whose values match a `hoist_enums` entry becomes a `$ref` to one
named component, defined from the first occurrence so it keeps the exporter's
own descriptions and extensions.

**One body under three media types.** A body declared as JSON, form-encoded and
multipart makes the generator pick the multipart one, turning a plain POST into
a per-field part list with no request model. `json_only_requests` drops the
media types that duplicate the JSON schema exactly; one declaring its own
schema describes a different body and is left alone.

**Response envelopes.** Where every payload is wrapped in
`{code, message, data, is_success}` and the wrapper is already stripped in
transport — an interceptor, a gateway — the generated client should deserialise
what actually reaches it. `strip_response_envelopes` points each response at
its payload `$ref`. A schema qualifies only when *every* property it declares
is a known envelope field (override the set with `envelope_keys`, and the
payload field with `envelope_data_key`), so a model that merely carries a `data`
field is never mistaken for a wrapper.

`tags:` keeps all of this to the routes you have actually implemented: the
component passes only touch the components those operations reach, so a schema
shared with an unimplemented route is never rewritten on its behalf. Anything
in scope that is still hash-named and has no configured name is reported, so
the next run can name it rather than shipping the hash.

Every pass is **idempotent**; a scheme with no entry is skipped entirely.

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

`EnumEntry.schemaNames` carries whatever the export declared for itself and
`EnumEntry.isSchemaNamed` says whether that covers every value;
`AuditReport.schemaNamed` counts the enums that needed no override because of
it. `packageVersion` is the published version, the same string `--version`
prints.

To target a serializer other than `dart_mappable`, implement `EnumEmitter` and
pass it to `EnumPatcher`; the registry, override and audit machinery is
unchanged. `RegistryBuilder`, `EnumAuditor` and `SchemaNormalizer` are all pure
and usable on their own.

`SchemaPreparer` is pure too, so a document can be prepared without touching
the filesystem:

```dart
final preps = SchemaPreps.parse(prepYaml);
final result = const SchemaPreparer().prepare(
  document,
  preps.prepFor('website_service'),
  namespacePrefix: 'WebsiteService',
);
print(result.describe());
```

`SchemaCodec` reads and writes either format directly, and `RegistryBuilder`
has a `buildFromYaml` to match `buildFromJson`:

```dart
const codec = SchemaCodec();

final document = codec.decode(source, source: 'api/website.yaml');
final registry = const RegistryBuilder().build([document]);

const SchemaNormalizer().normalize(document, namespacePrefix: 'Website');
File('api/website.yaml').writeAsStringSync(
  codec.encode(document, SchemaFormat.yaml),
);
```

## Scope

This package covers what is **general to any OpenAPI + `swagger_parser`
project**: export preparation, enum naming, the audit, missing-file synthesis,
schema normalisation and the namespace reorganisation.

Enums are indexed from **`components.schemas` entries that declare an `enum`**
— the named enums `swagger_parser` turns into their own Dart files. Enums
written inline inside a property or a query parameter are not named schemas, so
they have no override key and do not appear in the audit.

It deliberately does **not** ship the regex fix-ups a given project may need for
a specific combination of `swagger_parser`, `retrofit` and `dart_mappable`
versions — those patch bugs that come and go between releases, and applying them
blindly to another project's output would do harm. Keep those in your own repo.

## License

MIT
