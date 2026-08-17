import 'package:meta/meta.dart';

/// What a normalisation pass changed.
@immutable
class NormalizationResult {
  const NormalizationResult({
    required this.rewrittenPaths,
    required this.prefixedSchemas,
    required this.version,
    required this.prefix,
  });

  /// Number of path keys whose `{version}` template was made concrete.
  final int rewrittenPaths;

  /// Number of `components.schemas` keys that were namespace-qualified.
  final int prefixedSchemas;

  /// The concrete version substituted for `{version}`.
  final String version;

  /// The namespace prefix applied, when any.
  final String? prefix;

  bool get changed => rewrittenPaths > 0 || prefixedSchemas > 0;

  /// A one-line description of the change, for run output.
  String describe() {
    final parts = <String>[
      if (rewrittenPaths > 0) '{version} → v$version ($rewrittenPaths paths)',
      if (prefixedSchemas > 0) 'schema names → $prefix.* ($prefixedSchemas)',
    ];
    return parts.join(', ');
  }
}

/// Pre-processes an OpenAPI document to work around two export quirks that
/// `swagger_parser` configuration alone cannot fix.
///
/// Both passes are idempotent, so re-downloading a schema and re-running is
/// safe.
class SchemaNormalizer {
  const SchemaNormalizer({this.defaultVersion = '1'});

  static final RegExp _versionDigits = RegExp(r'\d+(?:\.\d+)*');
  static final RegExp _prefixSeparators = RegExp(r'[_\s-]+');
  static const String _refHead = '#/components/schemas/';
  static const String _versionTemplate = '{version}';

  /// Used when `info.version` carries no number.
  final String defaultVersion;

  /// Applies both passes in place on [document].
  NormalizationResult normalize(
    Map<String, Object?> document, {
    String? namespacePrefix,
  }) {
    final version = detectVersion(document);
    return NormalizationResult(
      rewrittenPaths: _rewriteVersionPaths(document, version),
      prefixedSchemas: namespacePrefix == null || namespacePrefix.isEmpty
          ? 0
          : _prefixSchemaNames(document, namespacePrefix),
      version: version,
      prefix: namespacePrefix,
    );
  }

  /// Reads the concrete version from `info.version` (`"v1"` → `"1"`).
  ///
  /// The path template already contains a literal `v` (`/api/v{version}/`), so
  /// only the numeric part is substituted.
  String detectVersion(Map<String, Object?> document) {
    final info = document['info'];
    if (info is! Map) return defaultVersion;
    final raw = info['version']?.toString().trim() ?? '';
    return _versionDigits.firstMatch(raw)?.group(0) ?? defaultVersion;
  }

  /// `social_service` → `SocialService`.
  static String toNamespacePrefix(String schemeName) => schemeName
      .split(_prefixSeparators)
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join();

  /// Replaces `{version}` in every path key with the concrete [version] and
  /// drops the now-unused `version` path parameter.
  ///
  /// Without this, an `include_paths` filter written with a concrete version
  /// never matches the templated key, and the route is silently skipped.
  int _rewriteVersionPaths(Map<String, Object?> document, String version) {
    final paths = document['paths'];
    if (paths is! Map) return 0;

    var rewritten = 0;
    for (final key in paths.keys.toList()) {
      final path = key.toString();
      if (!path.contains(_versionTemplate)) continue;

      final operations = paths.remove(key);
      if (operations is Map) _dropVersionParameter(operations);

      final newKey = path.replaceAll(_versionTemplate, version);
      final existing = paths[newKey];
      if (existing is Map && operations is Map) {
        existing.addAll(operations);
      } else {
        paths[newKey] = operations;
      }
      rewritten++;
    }
    return rewritten;
  }

  void _dropVersionParameter(Map<Object?, Object?> operations) {
    for (final operation in operations.values) {
      if (operation is! Map) continue;
      final parameters = operation['parameters'];
      if (parameters is! List) continue;
      operation['parameters'] = parameters
          .where(
            (parameter) =>
                !(parameter is Map &&
                    parameter['in'] == 'path' &&
                    parameter['name'] == 'version'),
          )
          .toList();
    }
  }

  /// Qualifies bare `components.schemas` names with `<prefix>.` and rewrites
  /// every matching `$ref`.
  ///
  /// Services that export bare names (`AccountData`) otherwise produce
  /// unprefixed files that collide with another service's models.
  /// `replacement_rules` cannot do this: it is applied to class definitions but
  /// not to `$ref`-resolved type names, so the two would diverge.
  int _prefixSchemaNames(Map<String, Object?> document, String prefix) {
    final components = document['components'];
    if (components is! Map) return 0;
    final schemas = components['schemas'];
    if (schemas is! Map || schemas.isEmpty) return 0;

    // Any dotted key means the export is already qualified — leave it alone.
    if (schemas.keys.any((key) => key.toString().contains('.'))) return 0;

    final originalNames = schemas.keys.map((k) => k.toString()).toSet();
    components['schemas'] = {
      for (final entry in schemas.entries) '$prefix.${entry.key}': entry.value,
    };

    _rewriteRefs(document, prefix, originalNames);
    return originalNames.length;
  }

  void _rewriteRefs(Object? node, String prefix, Set<String> known) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        if (key == r'$ref' && value is String && value.startsWith(_refHead)) {
          final target = value.substring(_refHead.length);
          if (known.contains(target)) {
            node[key] = '$_refHead$prefix.$target';
          }
        } else {
          _rewriteRefs(value, prefix, known);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _rewriteRefs(item, prefix, known);
      }
    }
  }
}
