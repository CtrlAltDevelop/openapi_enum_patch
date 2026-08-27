import 'models/enum_entry.dart';
import 'naming/dart_naming.dart';
import 'schema/schema_codec.dart';

/// Scans OpenAPI documents for enum schemas and predicts the Dart names
/// `swagger_parser` will generate for each.
class RegistryBuilder {
  const RegistryBuilder();

  /// The parallel-list extensions carrying enum member names, in the order
  /// they are consulted.
  static const _varNameKeys = [
    'x-enum-varnames',
    'x-enumNames',
    'x-enum-names',
  ];

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
        schemaNames: _schemaNames(schema, declared),
      );
    }
    return entries;
  }

  /// The member names [schema] declares for itself, as `value -> name`.
  ///
  /// OpenAPI itself has nowhere to put them, so every exporter that keeps them
  /// picked a vendor extension. Three cover almost all of them, and the first
  /// one that yields a name wins:
  ///
  /// - `x-enum-varnames` — openapi-generator, drf-spectacular
  /// - `x-enumNames` (or `x-enum-names`) — NSwag and the .NET exporters
  /// - `x-ms-enum: {values: [{value: 0, name: Active}]}` — AutoRest, Azure
  ///
  /// The list forms run parallel to `enum`, so they are zipped with it and any
  /// surplus on either side is ignored — a truncated list still names the
  /// values it reaches instead of throwing the whole enum away.
  Map<Object, String> _schemaNames(
    Map<Object?, Object?> schema,
    List<Object> values,
  ) {
    for (final key in _varNameKeys) {
      final names = schema[key];
      if (names is! List) continue;

      final resolved = <Object, String>{};
      for (var i = 0; i < values.length && i < names.length; i++) {
        final name = names[i]?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        resolved[values[i]] = name;
      }
      if (resolved.isNotEmpty) return resolved;
    }
    return _msEnumNames(schema['x-ms-enum']);
  }

  /// `x-ms-enum` pairs each name with its value explicitly, so declaration
  /// order does not matter here.
  Map<Object, String> _msEnumNames(Object? node) {
    if (node is! Map) return const {};
    final entries = node['values'];
    if (entries is! List) return const {};

    final resolved = <Object, String>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final value = entry['value'];
      final name = entry['name']?.toString().trim() ?? '';
      if (value == null || name.isEmpty) continue;
      resolved[value] = name;
    }
    return resolved;
  }

  /// An explicit `"type": "integer"` settles it; otherwise fall back to
  /// inspecting the values, since some exporters omit the type.
  bool _isIntegerEnum(Map<Object?, Object?> schema, List<Object> values) {
    if (schema['type'] == 'integer') return true;
    if (values.isEmpty) return false;
    return values.every((value) => value is int);
  }
}
