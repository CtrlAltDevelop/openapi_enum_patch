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
  /// `value0`, `value1`, … and always need an override. String enums take
  /// their member names from the values themselves and never do.
  final bool isIntegerEnum;

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
  List<EnumEntry> get sortedBySchemaKey => entries.values.toList()
    ..sort((a, b) => a.schemaKey.compareTo(b.schemaKey));
}
