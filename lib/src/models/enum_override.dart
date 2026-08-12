import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// A single entry from `enum_overrides.yaml`.
@immutable
class EnumOverride {
  const EnumOverride({this.names = const {}, this.extra = const []});

  /// Maps a schema value to the Dart member name it should generate as.
  final Map<Object, String> names;

  /// Values the API returns but the schema does not yet declare.
  final List<Object> extra;

  bool get isEmpty => names.isEmpty && extra.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// A short human label of what this override contributes, for run output.
  String describe() {
    final parts = <String>[
      if (names.isNotEmpty) 'names',
      if (extra.isNotEmpty) '+${extra.length} values',
    ];
    return parts.join(', ');
  }
}

/// Thrown when an overrides document cannot be read.
class EnumOverrideFormatException implements Exception {
  const EnumOverrideFormatException(this.message);

  final String message;

  @override
  String toString() => 'EnumOverrideFormatException: $message';
}

/// The whole `enum_overrides.yaml` document, keyed by OpenAPI schema key.
@immutable
class EnumOverrides {
  const EnumOverrides(this.bySchemaKey);

  const EnumOverrides.empty() : bySchemaKey = const {};

  final Map<String, EnumOverride> bySchemaKey;

  EnumOverride overrideFor(String schemaKey) =>
      bySchemaKey[schemaKey] ?? const EnumOverride();

  bool get isEmpty => bySchemaKey.isEmpty;

  /// Parses the YAML form:
  ///
  /// ```yaml
  /// enums:
  ///   "CRM.Enums.AccountStatus":
  ///     names:
  ///       0: active
  ///       1: suspended
  ///     extra:
  ///       - 3
  /// ```
  factory EnumOverrides.parse(String yamlSource) {
    final Object? document;
    try {
      document = loadYaml(yamlSource);
    } on YamlException catch (e) {
      throw EnumOverrideFormatException('Invalid YAML: ${e.message}');
    }
    if (document == null) return const EnumOverrides.empty();
    if (document is! Map) {
      throw const EnumOverrideFormatException(
        'Expected a YAML mapping at the root.',
      );
    }

    final enums = document['enums'];
    if (enums == null) return const EnumOverrides.empty();
    if (enums is! Map) {
      throw const EnumOverrideFormatException(
        'The "enums" key must be a mapping of schema key to override.',
      );
    }

    final result = <String, EnumOverride>{};
    for (final entry in enums.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is! Map) {
        throw EnumOverrideFormatException(
          'Override for "$key" must be a mapping.',
        );
      }
      result[key] = EnumOverride(
        names: _parseNames(key, value['names']),
        extra: _parseExtra(key, value['extra']),
      );
    }
    return EnumOverrides(result);
  }

  static Map<Object, String> _parseNames(String key, Object? raw) {
    if (raw == null) return const {};
    if (raw is! Map) {
      throw EnumOverrideFormatException(
        '"names" for "$key" must be a mapping of value to member name.',
      );
    }
    return {
      for (final entry in raw.entries)
        _normalizeValue(entry.key): entry.value.toString(),
    };
  }

  static List<Object> _parseExtra(String key, Object? raw) {
    if (raw == null) return const [];
    if (raw is List) return raw.map(_normalizeValue).toList(growable: false);
    // A mapping is accepted for its keys: hand-written overrides sometimes
    // mirror the `names:` shape here, and only the values ever mattered.
    if (raw is Map) {
      return raw.keys.map(_normalizeValue).toList(growable: false);
    }
    throw EnumOverrideFormatException(
      '"extra" for "$key" must be a list of values.',
    );
  }

  /// YAML may produce an int or a string for the same conceptual value
  /// depending on quoting; normalising keeps lookups consistent with the
  /// values decoded from the JSON schema.
  static Object _normalizeValue(Object? raw) {
    if (raw is int) return raw;
    final text = raw.toString();
    return int.tryParse(text) ?? text;
  }
}
