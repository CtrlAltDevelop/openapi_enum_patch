import 'package:meta/meta.dart';

import '../config/schema_prep_config.dart';

/// What a preparation pass changed.
@immutable
class PreparationResult {
  const PreparationResult({
    required this.renamedSchemas,
    required this.hoistedEnums,
    required this.droppedRequestBodies,
    required this.strippedEnvelopes,
    required this.unnamedSchemas,
  });

  const PreparationResult.noop()
    : renamedSchemas = 0,
      hoistedEnums = 0,
      droppedRequestBodies = 0,
      strippedEnvelopes = 0,
      unnamedSchemas = const [];

  /// Components given a real name.
  final int renamedSchemas;

  /// Inline enum occurrences replaced by a `$ref`.
  final int hoistedEnums;

  /// Non-JSON request media types dropped.
  final int droppedRequestBodies;

  /// Response envelopes replaced by their payload `$ref`.
  final int strippedEnvelopes;

  /// Components still named after a hash of their shape, in scope and left as
  /// they are because no name was configured for them. Reported so the next
  /// run can name them rather than shipping the hash as a class name.
  final List<String> unnamedSchemas;

  bool get changed =>
      renamedSchemas > 0 ||
      hoistedEnums > 0 ||
      droppedRequestBodies > 0 ||
      strippedEnvelopes > 0;

  /// A one-line description of the change, for run output.
  String describe() {
    final parts = <String>[
      if (renamedSchemas > 0) 'renamed $renamedSchemas schemas',
      if (hoistedEnums > 0) 'hoisted $hoistedEnums inline enums',
      if (droppedRequestBodies > 0)
        'dropped $droppedRequestBodies non-JSON request bodies',
      if (strippedEnvelopes > 0) 'stripped $strippedEnvelopes envelopes',
    ];
    return parts.isEmpty ? 'nothing to prepare' : parts.join(', ');
  }
}

/// Rewrites an OpenAPI document into a shape a generator can make usable code
/// out of, before any generation runs.
///
/// The four passes answer four exporter habits that no generator setting can
/// undo: components named after a hash of their shape, the same enum written
/// inline on several properties, one request body declared under three media
/// types, and a payload wrapped in a transport envelope. Which of them run,
/// and the names the first two need, come from a [SchemaPrep].
///
/// Every pass is idempotent, so re-downloading a schema and re-running is safe.
class SchemaPreparer {
  const SchemaPreparer();

  static const String _refHead = '#/components/schemas/';
  static const String _jsonMedia = 'application/json';
  static final RegExp _hashName = RegExp(r'^[0-9a-f]{32}$');

  /// Applies every configured pass in place on [document].
  ///
  /// [namespacePrefix] is the prefix `normalize` gives this scheme's
  /// components, so a name in [SchemaPrep.renameSchemas] resolves whether or
  /// not that pass has already run.
  PreparationResult prepare(
    Map<String, Object?> document,
    SchemaPrep prep, {
    String? namespacePrefix,
  }) {
    if (prep.isEmpty) return const PreparationResult.noop();

    final schemas = _schemas(document);
    final scope = _componentsInScope(document, schemas, prep.tags);

    final renamed = _renameSchemas(
      document,
      schemas,
      prep.renameSchemas,
      namespacePrefix,
    );
    // Renaming moves components, so the scope is rebuilt before the pass that
    // walks it.
    final rescoped = renamed == 0
        ? scope
        : _componentsInScope(document, _schemas(document), prep.tags);

    return PreparationResult(
      renamedSchemas: renamed,
      hoistedEnums: _hoistEnums(
        _schemas(document),
        rescoped,
        prep.hoistEnums,
        namespacePrefix,
      ),
      droppedRequestBodies: prep.jsonOnlyRequests
          ? _jsonOnlyRequests(document, prep.tags)
          : 0,
      strippedEnvelopes: prep.stripResponseEnvelopes
          ? _stripEnvelopes(document, prep)
          : 0,
      unnamedSchemas: [
        for (final name in rescoped)
          if (_hashName.hasMatch(_bareName(name, namespacePrefix))) name,
      ]..sort(),
    );
  }

  Map<String, Object?> _schemas(Map<String, Object?> document) {
    final components = document['components'];
    if (components is! Map) return {};
    final schemas = components['schemas'];
    return schemas is Map<String, Object?> ? schemas : {};
  }

  String _bareName(String name, String? prefix) =>
      prefix != null && name.startsWith('$prefix.')
      ? name.substring(prefix.length + 1)
      : name;

  /// The components reachable from the operations carrying one of [tags],
  /// transitively. An empty [tags] puts every component in scope.
  Set<String> _componentsInScope(
    Map<String, Object?> document,
    Map<String, Object?> schemas,
    Set<String> tags,
  ) {
    if (tags.isEmpty) return schemas.keys.toSet();

    final seeds = <String>{};
    for (final operation in _operations(document, tags)) {
      _collectRefs(operation, seeds);
    }

    final scope = <String>{};
    final pending = [...seeds];
    while (pending.isNotEmpty) {
      final name = pending.removeLast();
      if (!scope.add(name)) continue;
      final schema = schemas[name];
      if (schema == null) continue;
      final nested = <String>{};
      _collectRefs(schema, nested);
      pending.addAll(nested.where((n) => !scope.contains(n)));
    }
    return scope;
  }

  /// The operations carrying one of [tags], or every operation when empty.
  Iterable<Map<Object?, Object?>> _operations(
    Map<String, Object?> document,
    Set<String> tags,
  ) {
    final paths = document['paths'];
    if (paths is! Map) return const [];
    return [
      for (final operations in paths.values)
        if (operations is Map)
          for (final operation in operations.values)
            if (operation is Map && _hasTag(operation, tags)) operation,
    ];
  }

  bool _hasTag(Map<Object?, Object?> operation, Set<String> tags) {
    if (tags.isEmpty) return true;
    final operationTags = operation['tags'];
    if (operationTags is! List) return false;
    return operationTags.any((tag) => tags.contains(tag?.toString()));
  }

  void _collectRefs(Object? node, Set<String> into) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (entry.key == r'$ref') {
          final value = entry.value;
          if (value is String && value.startsWith(_refHead)) {
            into.add(value.substring(_refHead.length));
          }
        } else {
          _collectRefs(entry.value, into);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _collectRefs(item, into);
      }
    }
  }

  /// Renames components and rewrites every `$ref` that pointed at them.
  ///
  /// A name is looked up qualified first, then bare, so the pass works before
  /// and after `normalize`, and the new name keeps whichever form the old one
  /// had. Two entries may share a target — an exporter emits one component per
  /// occurrence of a shape, so the duplicates collapse onto one definition.
  int _renameSchemas(
    Map<String, Object?> document,
    Map<String, Object?> schemas,
    Map<String, String> renames,
    String? prefix,
  ) {
    if (renames.isEmpty || schemas.isEmpty) return 0;

    final mapping = <String, String>{};
    for (final entry in renames.entries) {
      final qualified = prefix == null ? null : '$prefix.${entry.key}';
      if (qualified != null && schemas.containsKey(qualified)) {
        mapping[qualified] = '$prefix.${entry.value}';
      } else if (schemas.containsKey(entry.key)) {
        mapping[entry.key] = entry.value;
      }
    }
    if (mapping.isEmpty) return 0;

    // Rebuilt rather than mutated so the components keep their document order,
    // with each renamed entry sitting where the old one was.
    final renamed = <String, Object?>{};
    for (final entry in schemas.entries) {
      final name = mapping[entry.key] ?? entry.key;
      renamed.putIfAbsent(name, () => entry.value);
    }
    (document['components']! as Map)['schemas'] = renamed;

    _rewriteRefs(document, mapping);
    return mapping.length;
  }

  void _rewriteRefs(Object? node, Map<String, String> mapping) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        if (key == r'$ref' && value is String && value.startsWith(_refHead)) {
          final target = mapping[value.substring(_refHead.length)];
          if (target != null) node[key] = '$_refHead$target';
        } else {
          _rewriteRefs(value, mapping);
        }
      }
    } else if (node is List) {
      for (final item in node) {
        _rewriteRefs(item, mapping);
      }
    }
  }

  /// Replaces each inline enum in scope with a `$ref` to a named component.
  ///
  /// The component is defined from the first occurrence found, so it keeps the
  /// exporter's own descriptions and extensions.
  int _hoistEnums(
    Map<String, Object?> schemas,
    Set<String> scope,
    Map<String, List<Object?>> hoists,
    String? prefix,
  ) {
    if (hoists.isEmpty || schemas.isEmpty) return 0;

    var hoisted = 0;
    for (final hoist in hoists.entries) {
      final target = prefix == null ? hoist.key : '$prefix.${hoist.key}';
      final wanted = hoist.value.toSet();
      var definition = schemas[target];

      for (final name in scope) {
        final schema = schemas[name];
        if (schema is! Map) continue;
        final properties = schema['properties'];
        if (properties is! Map) continue;

        for (final property in properties.keys.toList()) {
          final value = properties[property];
          if (value is! Map) continue;
          final values = value['enum'];
          if (values is! List || values.toSet().length != wanted.length) {
            continue;
          }
          if (!values.every(wanted.contains)) continue;

          definition ??= Map<String, Object?>.from(
            value.cast<String, Object?>(),
          );
          properties[property] = <String, Object?>{r'$ref': '$_refHead$target'};
          hoisted++;
        }
      }

      if (definition != null) schemas[target] = definition;
    }
    return hoisted;
  }

  /// Drops the media types that duplicate a request body's JSON schema.
  ///
  /// Only exact duplicates go: a media type declaring its own schema describes
  /// a different body and is left alone.
  int _jsonOnlyRequests(Map<String, Object?> document, Set<String> tags) {
    var dropped = 0;
    for (final operation in _operations(document, tags)) {
      final requestBody = operation['requestBody'];
      if (requestBody is! Map) continue;
      final content = requestBody['content'];
      if (content is! Map) continue;

      final json = content[_jsonMedia];
      if (json is! Map) continue;
      final jsonSchema = json['schema'];

      for (final media in content.keys.toList()) {
        if (media == _jsonMedia) continue;
        final entry = content[media];
        if (entry is! Map) continue;
        if (!_sameSchema(entry['schema'], jsonSchema)) continue;
        content.remove(media);
        dropped++;
      }
    }
    return dropped;
  }

  bool _sameSchema(Object? a, Object? b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      return a.entries.every((e) => _sameSchema(e.value, b[e.key]));
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_sameSchema(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  /// Points each response at its payload instead of at the envelope around it.
  ///
  /// A schema qualifies only when every property it declares is a known
  /// envelope field and the payload one is a `$ref`, so a real model is never
  /// mistaken for a wrapper.
  int _stripEnvelopes(Map<String, Object?> document, SchemaPrep prep) {
    var stripped = 0;
    for (final operation in _operations(document, prep.tags)) {
      final responses = operation['responses'];
      if (responses is! Map) continue;

      for (final response in responses.values) {
        if (response is! Map) continue;
        final content = response['content'];
        if (content is! Map) continue;

        for (final media in content.values) {
          if (media is! Map) continue;
          final schema = media['schema'];
          if (schema is! Map) continue;
          final properties = schema['properties'];
          if (properties is! Map || properties.isEmpty) continue;
          if (!properties.keys.every(
            (key) => prep.envelopeKeys.contains(key?.toString()),
          )) {
            continue;
          }

          final payload = properties[prep.envelopeDataKey];
          if (payload is! Map) continue;
          final ref = payload[r'$ref'];
          if (ref is! String) continue;

          media['schema'] = <String, Object?>{r'$ref': ref};
          stripped++;
        }
      }
    }
    return stripped;
  }
}
