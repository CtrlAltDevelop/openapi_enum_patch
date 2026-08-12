import 'dart:convert';

import 'models/enum_entry.dart';
import 'naming/dart_naming.dart';

/// Thrown when an OpenAPI document cannot be read.
class SchemaFormatException implements Exception {
  const SchemaFormatException(this.message, {this.source});

  final String message;
  final String? source;

  @override
  String toString() =>
      'SchemaFormatException: $message${source == null ? '' : ' (in $source)'}';
}

/// Scans OpenAPI documents for enum schemas and predicts the Dart names
/// `swagger_parser` will generate for each.
class RegistryBuilder {
  const RegistryBuilder();

  /// Builds a registry from several already-decoded OpenAPI documents.
  ///
  /// Later documents override earlier ones on a file-stem collision, matching
  /// the generator's own last-writer-wins behaviour.
  EnumRegistry build(Iterable<Map<String, Object?>> documents) {
    final entries = <String, EnumEntry>{};
    for (final document in documents) {
      entries.addAll(_entriesOf(document));
    }
    return EnumRegistry(entries);
  }

  /// Builds a registry from a single JSON document.
  EnumRegistry buildFromJson(String json, {String? source}) =>
      build([decode(json, source: source)]);

  /// Decodes an OpenAPI document, raising a descriptive error on bad input.
  Map<String, Object?> decode(String json, {String? source}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      throw SchemaFormatException('Invalid JSON: ${e.message}', source: source);
    }
    if (decoded is! Map<String, Object?>) {
      throw SchemaFormatException(
        'Expected a JSON object at the root.',
        source: source,
      );
    }
    return decoded;
  }

  /// The namespace prefix of every component schema, as
  /// `file_prefix -> ClassPrefix` (`crm -> Crm`, `ai_analyst -> AiAnalyst`).
  ///
  /// Taken from the first dotted segment of each `components.schemas` key,
  /// which is exactly what `swagger_parser` folds into the generated file and
  /// class names. Keys with no dot contribute nothing: they are not namespaced,
  /// so there is no prefix to group or strip.
  Map<String, String> namespacePrefixes(
    Iterable<Map<String, Object?>> documents,
  ) {
    final prefixes = <String, String>{};
    for (final document in documents) {
      final components = document['components'];
      if (components is! Map) continue;
      final schemas = components['schemas'];
      if (schemas is! Map) continue;

      for (final key in schemas.keys) {
        final name = key.toString();
        final dot = name.indexOf('.');
        if (dot <= 0) continue;
        final className = DartNaming.toClassName(name.substring(0, dot));
        if (className.isEmpty) continue;
        prefixes[DartNaming.toFileStem(className)] = className;
      }
    }
    return prefixes;
  }

  Map<String, EnumEntry> _entriesOf(Map<String, Object?> document) {
    final components = document['components'];
    if (components is! Map) return const {};
    final schemas = components['schemas'];
    if (schemas is! Map) return const {};

    final entries = <String, EnumEntry>{};
    for (final entry in schemas.entries) {
      final schema = entry.value;
      if (schema is! Map) continue;
      final values = schema['enum'];
      if (values is! List) continue;

      final schemaKey = entry.key.toString();
      final className = DartNaming.toClassName(schemaKey);
      final fileStem = DartNaming.toFileStem(className);
      final declared = values.whereType<Object>().toList(growable: false);

      entries[fileStem] = EnumEntry(
        schemaKey: schemaKey,
        className: className,
        fileStem: fileStem,
        values: declared,
        isIntegerEnum: _isIntegerEnum(schema, declared),
      );
    }
    return entries;
  }

  /// An explicit `"type": "integer"` settles it; otherwise fall back to
  /// inspecting the values, since some exporters omit the type.
  bool _isIntegerEnum(Map<Object?, Object?> schema, List<Object> values) {
    if (schema['type'] == 'integer') return true;
    if (values.isEmpty) return false;
    return values.every((value) => value is int);
  }
}
