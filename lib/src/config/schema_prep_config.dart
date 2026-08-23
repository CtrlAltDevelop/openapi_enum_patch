import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// Thrown when a preparation document cannot be read.
class SchemaPrepFormatException implements Exception {
  const SchemaPrepFormatException(this.message);

  final String message;

  @override
  String toString() => 'SchemaPrepFormatException: $message';
}

/// The preparation to apply to one scheme's OpenAPI document.
///
/// Every pass is opt-in: an entry that sets nothing is [isEmpty] and the
/// document is left exactly as exported.
@immutable
class SchemaPrep {
  const SchemaPrep({
    this.tags = const {},
    this.renameSchemas = const {},
    this.hoistEnums = const {},
    this.jsonOnlyRequests = false,
    this.stripResponseEnvelopes = false,
    this.envelopeKeys = defaultEnvelopeKeys,
    this.envelopeDataKey = 'data',
  });

  /// The envelope fields recognised when [stripResponseEnvelopes] is on.
  ///
  /// A response schema counts as an envelope only when every one of its
  /// properties is in this set, so a payload that merely happens to carry a
  /// `data` field is never mistaken for one.
  static const Set<String> defaultEnvelopeKeys = {
    'code',
    'message',
    'data',
    'is_success',
    'isSuccess',
    'reference_id',
    'referenceId',
  };

  /// Operation tags the passes are limited to; empty means the whole document.
  ///
  /// Component passes ([renameSchemas], [hoistEnums]) are limited to the
  /// components these operations reach, so a schema shared with an
  /// unimplemented route is never rewritten on its behalf.
  final Set<String> tags;

  /// Component name (bare or namespace-qualified) to the name it takes.
  ///
  /// Exporters that inline their nested models name the resulting component
  /// after a hash of its shape, which generates a class nobody can read or
  /// import on purpose. Only the project knows what each one means, so the
  /// names come from here.
  final Map<String, String> renameSchemas;

  /// Component name to the enum values it collects.
  ///
  /// An enum written inline on several properties generates one anonymous
  /// `Enum0`, `Enum1`, … per occurrence. Every inline enum in scope whose
  /// values match is replaced by a `$ref` to a single named component.
  final Map<String, List<Object?>> hoistEnums;

  /// Whether to drop the non-JSON twins of a request body that declares the
  /// same schema under several media types.
  ///
  /// Generators pick one media type, and a multipart pick turns a plain POST
  /// into a per-field part list with no request model.
  final bool jsonOnlyRequests;

  /// Whether to replace a response envelope with a `$ref` to its payload.
  ///
  /// Use this where the envelope is stripped in transport (an interceptor,
  /// a gateway) so the generated client deserialises what actually reaches it.
  final bool stripResponseEnvelopes;

  final Set<String> envelopeKeys;

  /// The envelope property holding the payload. It must be a `$ref` for the
  /// envelope to be replaced by it.
  final String envelopeDataKey;

  bool get isEmpty =>
      renameSchemas.isEmpty &&
      hoistEnums.isEmpty &&
      !jsonOnlyRequests &&
      !stripResponseEnvelopes;

  bool get isNotEmpty => !isEmpty;
}

/// The whole `schema_prep.yaml` document, keyed by `swagger_parser` scheme name.
@immutable
class SchemaPreps {
  const SchemaPreps(this.bySchemeName);

  const SchemaPreps.empty() : bySchemeName = const {};

  final Map<String, SchemaPrep> bySchemeName;

  SchemaPrep prepFor(String schemeName) =>
      bySchemeName[schemeName] ?? const SchemaPrep();

  bool get isEmpty => bySchemeName.isEmpty;

  /// Parses the YAML form:
  ///
  /// ```yaml
  /// schemas:
  ///   website_service:
  ///     tags: [Calculators]
  ///     rename_schemas:
  ///       36306f9579e14754966f345278617b8c: FibonacciLevel
  ///       Row: PivotPointRow
  ///     hoist_enums:
  ///       TradeDirection: [buy, sell]
  ///     json_only_requests: true
  ///     strip_response_envelopes: true
  /// ```
  factory SchemaPreps.parse(String yamlSource) {
    final Object? document;
    try {
      document = loadYaml(yamlSource);
    } on YamlException catch (e) {
      throw SchemaPrepFormatException('Invalid YAML: ${e.message}');
    }
    if (document == null) return const SchemaPreps.empty();
    if (document is! Map) {
      throw const SchemaPrepFormatException(
        'Expected a YAML mapping at the root.',
      );
    }

    final schemas = document['schemas'];
    if (schemas == null) return const SchemaPreps.empty();
    if (schemas is! Map) {
      throw const SchemaPrepFormatException(
        'Expected "schemas" to be a mapping of scheme name to its passes.',
      );
    }

    return SchemaPreps({
      for (final entry in schemas.entries)
        entry.key.toString(): _parsePrep(entry.key.toString(), entry.value),
    });
  }

  static SchemaPrep _parsePrep(String scheme, Object? node) {
    if (node == null) return const SchemaPrep();
    if (node is! Map) {
      throw SchemaPrepFormatException(
        'Expected "$scheme" to be a mapping of passes.',
      );
    }

    final envelopeKeys = _stringSet(scheme, node['envelope_keys']);

    return SchemaPrep(
      tags: _stringSet(scheme, node['tags']),
      renameSchemas: _stringMap(scheme, node['rename_schemas']),
      hoistEnums: _valueListMap(scheme, node['hoist_enums']),
      jsonOnlyRequests: node['json_only_requests'] == true,
      stripResponseEnvelopes: node['strip_response_envelopes'] == true,
      envelopeKeys: envelopeKeys.isEmpty
          ? SchemaPrep.defaultEnvelopeKeys
          : envelopeKeys,
      envelopeDataKey: node['envelope_data_key']?.toString() ?? 'data',
    );
  }

  static Set<String> _stringSet(String scheme, Object? node) {
    if (node == null) return const {};
    if (node is! List) {
      throw SchemaPrepFormatException('Expected "$scheme" list of strings.');
    }
    return {for (final value in node) value.toString()};
  }

  static Map<String, String> _stringMap(String scheme, Object? node) {
    if (node == null) return const {};
    if (node is! Map) {
      throw SchemaPrepFormatException(
        'Expected "$scheme" mapping of name to name.',
      );
    }
    return {
      for (final entry in node.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }

  static Map<String, List<Object?>> _valueListMap(String scheme, Object? node) {
    if (node == null) return const {};
    if (node is! Map) {
      throw SchemaPrepFormatException(
        'Expected "$scheme" mapping of name to its values.',
      );
    }
    return {
      for (final entry in node.entries)
        entry.key.toString(): switch (entry.value) {
          final List<Object?> values => [
            for (final value in values)
              value is YamlScalar ? value.value : value,
          ],
          _ => throw SchemaPrepFormatException(
            'Expected "$scheme.${entry.key}" to list the enum values.',
          ),
        },
    };
  }
}
