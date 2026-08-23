import 'models/enum_entry.dart';
import 'naming/dart_naming.dart';
import 'schema/schema_codec.dart';

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
      build([decode(json, source: source, format: SchemaFormat.json)]);

  /// Builds a registry from a single YAML document.
  EnumRegistry buildFromYaml(String yaml, {String? source}) =>
      build([decode(yaml, source: source, format: SchemaFormat.yaml)]);

  /// Decodes a JSON or YAML OpenAPI document, raising a descriptive error on
  /// bad input.
  ///
  /// When [format] is omitted it is taken from [source]'s extension, falling
  /// back to sniffing [content].
  Map<String, Object?> decode(
    String content, {
    String? source,
    SchemaFormat? format,
  }) => const SchemaCodec().decode(content, source: source, format: format);

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
