import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'yaml_encoder.dart';

/// Thrown when an OpenAPI document cannot be read.
class SchemaFormatException implements Exception {
  const SchemaFormatException(this.message, {this.source});

  final String message;
  final String? source;

  @override
  String toString() =>
      'SchemaFormatException: $message${source == null ? '' : ' (in $source)'}';
}

/// The serialisation an OpenAPI document is written in.
enum SchemaFormat {
  json,
  yaml;

  /// The format [path]'s extension implies, or `null` when it implies none.
  ///
  /// `.yaml` and `.yml` are YAML, `.json` is JSON. Anything else is left for
  /// [sniff] to decide from the content.
  static SchemaFormat? forPath(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.yaml' || '.yml' => SchemaFormat.yaml,
        '.json' => SchemaFormat.json,
        _ => null,
      };

  /// Guesses the format of [content] for files with an unhelpful extension.
  ///
  /// A document opening with `{` or `[` is JSON; everything else is read as
  /// YAML, which — being a superset of JSON — is the safer fallback.
  static SchemaFormat sniff(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      return SchemaFormat.json;
    }
    return SchemaFormat.yaml;
  }

  /// Resolves the format to use for [content] read from [path].
  ///
  /// The extension wins when it is decisive; otherwise the content is sniffed.
  static SchemaFormat resolve({String? path, String? content}) {
    final byPath = path == null ? null : forPath(path);
    if (byPath != null) return byPath;
    return content == null ? SchemaFormat.json : sniff(content);
  }
}

/// Reads and writes OpenAPI documents in either JSON or YAML.
class SchemaCodec {
  const SchemaCodec();

  static const YamlEncoder _yamlEncoder = YamlEncoder();
  static const JsonEncoder _jsonEncoder = JsonEncoder.withIndent('  ');

  /// Decodes [content] into a mutable document tree.
  ///
  /// [source] is the path the content came from: it selects the format when
  /// [format] is omitted, and names the file in any error. The result is always
  /// plain mutable `Map`s and `List`s, never the immutable nodes `loadYaml`
  /// returns, because the normaliser rewrites the tree in place.
  Map<String, Object?> decode(
    String content, {
    String? source,
    SchemaFormat? format,
  }) {
    final resolved =
        format ?? SchemaFormat.resolve(path: source, content: content);

    final Object? decoded;
    switch (resolved) {
      case SchemaFormat.json:
        try {
          decoded = jsonDecode(content);
        } on FormatException catch (e) {
          throw SchemaFormatException(
            'Invalid JSON: ${e.message}',
            source: source,
          );
        }
      case SchemaFormat.yaml:
        final Object? node;
        try {
          node = loadYaml(
            content,
            sourceUrl: source == null ? null : Uri.file(source),
          );
        } on YamlException catch (e) {
          throw SchemaFormatException(
            'Invalid YAML: ${e.message}',
            source: source,
          );
        }
        decoded = _toPlain(node);
    }

    if (decoded is! Map<String, Object?>) {
      throw SchemaFormatException(
        'Expected a ${resolved.name.toUpperCase()} mapping at the root.',
        source: source,
      );
    }
    return decoded;
  }

  /// Encodes [document] back to [format], newline-terminated.
  ///
  /// YAML output is regenerated from the data, so comments and the original
  /// formatting of the source file are not preserved.
  String encode(Map<String, Object?> document, SchemaFormat format) =>
      switch (format) {
        SchemaFormat.json => '${_jsonEncoder.convert(document)}\n',
        SchemaFormat.yaml => _yamlEncoder.convert(document),
      };

  /// Deep-copies a YAML node tree into plain, mutable collections.
  ///
  /// Keys become strings so a YAML document indexes exactly like the decoded
  /// JSON one — an unquoted `200:` response code included.
  static Object? _toPlain(Object? node) {
    if (node is YamlScalar) return node.value;
    if (node is Map) {
      return <String, Object?>{
        for (final entry in node.entries)
          entry.key.toString(): _toPlain(entry.value),
      };
    }
    if (node is List) return <Object?>[for (final item in node) _toPlain(item)];
    return node;
  }
}
