import 'dart:io';

import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _yamlSchema = '''
openapi: 3.0.3
info:
  title: Website API
  version: v2.1
paths:
  /api/v{version}/account-types/:
    get:
      operationId: list
      parameters:
      - in: path
        name: version
        required: true
        schema:
          type: string
      - in: query
        name: locale
        schema:
          type: string
        description: |-
          * `ar` - ar
          * `en` - en
components:
  schemas:
    Platform:
      type: integer
      enum:
      - 1
      - 2
    Account:
      type: object
      properties:
        platform:
          \$ref: '#/components/schemas/Platform'
''';

/// A patcher rooted at a throwaway directory holding [schemaName].
({EnumPatcher patcher, File schema}) _setUp(
  Directory root,
  String schemaName,
  String contents,
) {
  final schema = File(p.join(root.path, schemaName))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  return (
    patcher: EnumPatcher(
      root: root.path,
      config: SwaggerParserConfig.parse('''
swagger_parser:
  output_directory: lib/api
  schemes:
    - name: website
      schema_path: $schemaName
'''),
    ),
    schema: schema,
  );
}

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('oep_yaml_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('builds a registry from a YAML schema', () {
    final registry = _setUp(
      root,
      'schema.yaml',
      _yamlSchema,
    ).patcher.buildRegistry();

    expect(registry.entries.keys, ['platform']);
    expect(registry.byStem('platform')!.values, [1, 2]);
  });

  test('normalizes a YAML schema and writes it back as YAML', () {
    final (:patcher, :schema) = _setUp(root, 'schema.yaml', _yamlSchema);

    final results = patcher.normalizeSchemas();
    expect(results, hasLength(1));
    expect(results.single.rewrittenPaths, 1);
    expect(results.single.prefixedSchemas, 2);

    final written = schema.readAsStringSync();
    expect(written, startsWith('openapi: 3.0.3\n'), reason: 'still YAML');
    expect(written, isNot(startsWith('{')));
    expect(written, contains('  /api/v2.1/account-types/:'));
    expect(written, contains('    Website.Platform:'));
    expect(
      written,
      contains(r"          $ref: '#/components/schemas/Website.Platform'"),
    );
    // The version path parameter is gone, the query one stays.
    expect(written, isNot(contains('name: version')));
    expect(written, contains('name: locale'));
    // Multi-line descriptions stay readable rather than becoming "\n" escapes.
    expect(written, contains('description: |-'));
  });

  test('is idempotent over a YAML schema', () {
    final (:patcher, :schema) = _setUp(root, 'schema.yaml', _yamlSchema);

    patcher.normalizeSchemas();
    final once = schema.readAsStringSync();

    expect(patcher.normalizeSchemas(), isEmpty);
    expect(schema.readAsStringSync(), once);
  });

  test('normalizes a JSON schema and writes it back as JSON', () {
    final (:patcher, :schema) = _setUp(
      root,
      'schema.json',
      '{"info":{"version":"v3"},"paths":{"/api/v{version}/x/":{"get":{}}},'
          '"components":{"schemas":{"Platform":{"enum":[1,2]}}}}',
    );

    expect(patcher.normalizeSchemas(), hasLength(1));

    final written = schema.readAsStringSync();
    expect(written, startsWith('{\n'), reason: 'still JSON');
    expect(written, contains('"/api/v3/x/"'));
    expect(written, contains('"Website.Platform"'));
  });

  test('reads a schema whose extension gives nothing away', () {
    final registry = _setUp(
      root,
      'schema.txt',
      _yamlSchema,
    ).patcher.buildRegistry();

    expect(registry.entries.keys, ['platform']);
  });

  test('derives namespace groups from a YAML schema', () {
    final (:patcher, schema: _) = _setUp(root, 'schema.yaml', _yamlSchema);
    patcher.normalizeSchemas();

    // Nothing generated to move, but the prefix must have been discovered.
    expect(patcher.reorganizeModels(rewriteRoots: const []), isNotNull);
    expect(
      const RegistryBuilder().namespacePrefixes([
        const SchemaCodec().decode(
          File(p.join(root.path, 'schema.yaml')).readAsStringSync(),
          source: 'schema.yaml',
        ),
      ]),
      {'website': 'Website'},
    );
  });
}
