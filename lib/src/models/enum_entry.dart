import 'package:meta/meta.dart';

/// One enum schema found in an OpenAPI document, paired with the Dart names
/// `swagger_parser` will generate for it.
@immutable
class EnumEntry {
  const EnumEntry({
    required this.schemaKey,
    required this.className,
    required this.fileStem,
    required this.values,
    required this.isIntegerEnum,
    this.schemaNames = const {},
  });

  /// The `components.schemas` key, e.g. `CRM.Enums.AccountStatus`.
  final String schemaKey;

  /// The generated Dart class name, e.g. `CrmEnumsAccountStatus`.
  final String className;

  /// The generated file stem, e.g. `crm_enums_account_status`.
  final String fileStem;

  /// The values declared by the schema, in declaration order.
  final List<Object> values;

  /// Integer enums carry no member names in OpenAPI, so they generate as
  /// `value0`, `value1`, … and need naming from somewhere. String enums take
  /// their member names from the values themselves and never do.
  final bool isIntegerEnum;

  /// Member names the export declares for itself, as `value -> name`.
  ///
  /// OpenAPI has no field for them, but most exporters write them into a
  /// vendor extension anyway — `x-enum-varnames`, `x-enumNames` or
  /// `x-ms-enum`. An `enum_overrides.yaml` entry outranks them, so a project
  /// can still rename what the export got wrong.
  final Map<Object, String> schemaNames;

  /// Whether the export names every value this enum declares, so no override
  /// is needed for it at all.
  bool get isSchemaNamed =>
      values.isNotEmpty && values.every(schemaNames.containsKey);

  @override
  String toString() => 'EnumEntry($schemaKey -> $className)';
}

/// Every enum schema discovered across all parsed OpenAPI documents.
@immutable
class EnumRegistry {
  const EnumRegistry(this.entries);

  const EnumRegistry.empty() : entries = const {};

  /// Keyed by [EnumEntry.fileStem], matching how generated files are named.
  final Map<String, EnumEntry> entries;

  Iterable<EnumEntry> get all => entries.values;

  EnumEntry? byStem(String fileStem) => entries[fileStem];

  EnumEntry? bySchemaKey(String schemaKey) {
    for (final entry in entries.values) {
      if (entry.schemaKey == schemaKey) return entry;
    }
    return null;
  }

  /// Reverse index from schema key to file stem, for override lookups.
  Map<String, String> get stemsBySchemaKey => {
    for (final entry in entries.entries) entry.value.schemaKey: entry.key,
  };

  /// Entries sorted by schema key, for stable report output.
  List<EnumEntry> get sortedBySchemaKey =>
      entries.values.toList()
        ..sort((a, b) => a.schemaKey.compareTo(b.schemaKey));
}
