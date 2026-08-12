import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

/// One `schemes:` entry from a `swagger_parser.yaml`.
@immutable
class SchemeConfig {
  const SchemeConfig({required this.name, required this.schemaPath});

  /// The scheme name, also the source of the namespace prefix.
  final String name;

  /// Path to the OpenAPI document, relative to the project root.
  final String schemaPath;
}

/// The subset of `swagger_parser.yaml` this package needs.
///
/// Reading the generator's own config means the schema list, output directory
/// and compute setting are never duplicated and cannot drift.
@immutable
class SwaggerParserConfig {
  const SwaggerParserConfig({
    required this.outputDirectory,
    required this.useFlutterCompute,
    required this.schemes,
  });

  final String outputDirectory;
  final bool useFlutterCompute;
  final List<SchemeConfig> schemes;

  /// Where `swagger_parser` writes model files.
  String get modelsSubdirectory => 'models';

  factory SwaggerParserConfig.parse(String yamlSource) {
    final document = loadYaml(yamlSource);
    if (document is! Map) {
      throw const FormatException('Expected a YAML mapping at the root.');
    }
    final root = document['swagger_parser'];
    if (root is! Map) {
      throw const FormatException('Missing a "swagger_parser" section.');
    }

    final rawSchemes = root['schemes'];
    final schemes = <SchemeConfig>[];
    if (rawSchemes is List) {
      for (final scheme in rawSchemes) {
        if (scheme is! Map) continue;
        final schemaPath = scheme['schema_path']?.toString();
        if (schemaPath == null || schemaPath.isEmpty) continue;
        schemes.add(
          SchemeConfig(
            name: scheme['name']?.toString() ?? '',
            schemaPath: schemaPath,
          ),
        );
      }
    }

    return SwaggerParserConfig(
      outputDirectory:
          root['output_directory']?.toString() ?? 'lib/api_clients',
      useFlutterCompute: root['use_flutter_compute'] == true,
      schemes: schemes,
    );
  }
}
