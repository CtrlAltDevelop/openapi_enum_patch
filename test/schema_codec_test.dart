import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

const _codec = SchemaCodec();

const _yaml = '''
openapi: 3.0.3
info:
  title: DeltaFX Website API
  version: 0.1.0
paths:
  /api/account-types/:
    get:
      operationId: apiAccountTypesList
      parameters:
      - in: query
        name: locale
        schema:
          enum:
          - ar
          - en
          type: string
        description: |-
          * `ar` - ar
          * `en` - en
      responses:
        '200':
          description: ''
components:
  schemas:
    CRM.Enums.Platform:
      type: integer
      enum:
      - 1
      - 2
    CRM.Models.Account:
      type: object
''';

const _json = '''
{
  "openapi": "3.0.3",
  "components": {
    "schemas": {
      "CRM.Enums.Platform": {"type": "integer", "enum": [1, 2]}
    }
  }
}
''';

void main() {
  group('format detection', () {
    test('reads the extension', () {
      expect(SchemaFormat.forPath('api/schema.yaml'), SchemaFormat.yaml);
      expect(SchemaFormat.forPath('api/schema.YML'), SchemaFormat.yaml);
      expect(SchemaFormat.forPath('api/schema.json'), SchemaFormat.json);
      expect(SchemaFormat.forPath('api/schema.txt'), isNull);
      expect(SchemaFormat.forPath('schema'), isNull);
    });

    test('sniffs content when the extension says nothing', () {
      expect(SchemaFormat.sniff('  {"openapi": "3.0.3"}'), SchemaFormat.json);
      expect(SchemaFormat.sniff('openapi: 3.0.3\n'), SchemaFormat.yaml);
    });

    test('prefers the extension over the content', () {
      // A JSON document is valid YAML, so a .yaml extension must still win.
      expect(
        SchemaFormat.resolve(path: 'schema.yaml', content: '{"a": 1}'),
        SchemaFormat.yaml,
      );
      expect(
        SchemaFormat.resolve(path: 'schema.txt', content: '{"a": 1}'),
        SchemaFormat.json,
      );
    });
  });

  group('decode', () {
    test('reads a YAML document', () {
      final document = _codec.decode(_yaml, source: 'schema.yaml');

      expect(document['openapi'], '3.0.3');
      expect((document['paths']! as Map).keys, ['/api/account-types/']);
      expect(((document['components']! as Map)['schemas']! as Map).keys, [
        'CRM.Enums.Platform',
        'CRM.Models.Account',
      ]);
    });

    test('picks the format from the source path', () {
      expect(_codec.decode(_json, source: 'schema.json')['openapi'], '3.0.3');
      expect(_codec.decode(_yaml, source: 'schema.yaml')['openapi'], '3.0.3');
    });

    test('returns mutable collections the normalizer can rewrite', () {
      final document = _codec.decode(_yaml, source: 'schema.yaml');
      final schemas = (document['components']! as Map)['schemas']! as Map;

      // `loadYaml` hands back immutable nodes; these must be plain maps.
      expect(() => schemas['Extra'] = <String, Object?>{}, returnsNormally);
      expect(document, isA<Map<String, Object?>>());
      expect(schemas['CRM.Enums.Platform'], isA<Map<String, Object?>>());
      expect(
        (schemas['CRM.Enums.Platform']! as Map)['enum'],
        isA<List<Object?>>(),
      );
    });

    test('stringifies keys so YAML and JSON documents index alike', () {
      final responses =
          ((((_codec.decode(_yaml, source: 'schema.yaml')['paths']!
                          as Map)['/api/account-types/']!
                      as Map)['get']!
                  as Map)['responses']!
              as Map);

      expect(responses.keys, ['200']);
      expect(responses.keys.first, isA<String>());
    });

    test('rejects a YAML document that is not a mapping', () {
      expect(
        () => _codec.decode('- one\n- two\n', source: 'schema.yaml'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('YAML mapping'), contains('schema.yaml')),
          ),
        ),
      );
    });

    test('reports the file and the reason for malformed YAML', () {
      expect(
        () => _codec.decode('a:\n b: 1\n\t c: 2\n', source: 'schema.yaml'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('Invalid YAML'), contains('schema.yaml')),
          ),
        ),
      );
    });

    test('still reports malformed JSON as JSON', () {
      expect(
        () => _codec.decode('{oops', source: 'schema.json'),
        throwsA(
          isA<SchemaFormatException>().having(
            (e) => e.toString(),
            'message',
            contains('Invalid JSON'),
          ),
        ),
      );
    });
  });

  group('encode', () {
    test('round-trips a YAML document', () {
      final document = _codec.decode(_yaml, source: 'schema.yaml');
      final encoded = _codec.encode(document, SchemaFormat.yaml);

      expect(_codec.decode(encoded, source: 'schema.yaml'), document);
    });

    test('round-trips a YAML document through JSON and back', () {
      final document = _codec.decode(_yaml, source: 'schema.yaml');
      final json = _codec.encode(document, SchemaFormat.json);

      expect(_codec.decode(json, source: 'schema.json'), document);
    });

    test('keeps the readable block description', () {
      final document = _codec.decode(_yaml, source: 'schema.yaml');

      expect(
        _codec.encode(document, SchemaFormat.yaml),
        contains('description: |-\n          * `ar` - ar'),
      );
    });

    test('ends with a newline', () {
      final document = _codec.decode(_json, source: 'schema.json');

      expect(_codec.encode(document, SchemaFormat.yaml), endsWith('\n'));
      expect(_codec.encode(document, SchemaFormat.json), endsWith('}\n'));
    });
  });

  group('RegistryBuilder', () {
    test('indexes enums declared in a YAML document', () {
      final registry = const RegistryBuilder().buildFromYaml(_yaml);

      expect(registry.entries.keys, ['crm_enums_platform']);
      expect(registry.byStem('crm_enums_platform')!.values, [1, 2]);
      expect(registry.byStem('crm_enums_platform')!.isIntegerEnum, isTrue);
    });

    test('merges a YAML and a JSON document', () {
      const builder = RegistryBuilder();
      final registry = builder.build([
        builder.decode(_yaml, source: 'a.yaml'),
        builder.decode(_json, source: 'b.json'),
      ]);

      expect(registry.byStem('crm_enums_platform'), isNotNull);
    });

    test('derives namespace prefixes from a YAML document', () {
      const builder = RegistryBuilder();

      expect(
        builder.namespacePrefixes([builder.decode(_yaml, source: 'a.yaml')]),
        {'crm': 'Crm'},
      );
    });
  });
}
