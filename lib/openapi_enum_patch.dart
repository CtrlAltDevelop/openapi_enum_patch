/// Name, complete and audit the integer enums that `swagger_parser` generates
/// from an OpenAPI schema.
///
/// OpenAPI carries no member names for integer enums, so a generated client is
/// full of `value0`, `value1`, … This package applies an `enum_overrides.yaml`
/// on top of the generated output, synthesises the enum files the generator
/// skips, and prints an audit of every enum still missing names.
///
/// ```sh
/// dart run openapi_enum_patch normalize   # before swagger_parser
/// dart run openapi_enum_patch patch       # after swagger_parser
/// ```
library;

export 'src/audit/audit_formatter.dart';
export 'src/audit/enum_audit.dart';
export 'src/config/swagger_parser_config.dart';
export 'src/emitter/dart_mappable_enum_emitter.dart';
export 'src/emitter/enum_emitter.dart';
export 'src/enum_patcher.dart';
export 'src/models/enum_entry.dart';
export 'src/models/enum_override.dart';
export 'src/naming/dart_naming.dart';
export 'src/normalizer/schema_normalizer.dart';
export 'src/output_scanner.dart';
export 'src/registry_builder.dart';
export 'src/reorganizer/model_reorganizer.dart';
