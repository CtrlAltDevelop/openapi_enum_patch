import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

/// A document shaped like a drf-spectacular export: hash-named components for
/// the inline serializers, the same enum inlined twice, one body under three
/// media types, and a response envelope around the payload.
///
/// Decoded from JSON on every call, so each test gets a fresh tree in exactly
/// the shape [SchemaCodec] hands the preparer in a real run.
Map<String, Object?> document() => const SchemaCodec().decode(_export);

const _export = '''
{
  "openapi": "3.0.3",
  "info": {"title": "Website", "version": "0.1.0"},
  "paths": {
    "/api/calculator/profit/": {
      "post": {
        "operationId": "apiCalculatorProfitCreate",
        "tags": ["Calculators"],
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {"\u0024ref": "#/components/schemas/ProfitInput"}
            },
            "application/x-www-form-urlencoded": {
              "schema": {"\u0024ref": "#/components/schemas/ProfitInput"}
            },
            "multipart/form-data": {
              "schema": {"\u0024ref": "#/components/schemas/ProfitInput"}
            }
          },
          "required": true
        },
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "code": {"type": "integer"},
                    "is_success": {"type": "boolean"},
                    "data": {"\u0024ref": "#/components/schemas/ProfitOutput"}
                  },
                  "required": ["code", "data", "is_success"]
                }
              }
            }
          }
        }
      }
    },
    "/api/blog/news/": {
      "get": {
        "operationId": "apiBlogNewsList",
        "tags": ["Blog / News"],
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "type": "object",
                  "properties": {
                    "code": {"type": "integer"},
                    "is_success": {"type": "boolean"},
                    "data": {"\u0024ref": "#/components/schemas/NewsOutput"}
                  }
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "ProfitInput": {
        "type": "object",
        "properties": {
          "lot_size": {"type": "number"},
          "direction": {
            "enum": ["buy", "sell"],
            "type": "string",
            "x-spec-enum-id": "abc123"
          }
        }
      },
      "ProfitOutput": {
        "type": "object",
        "properties": {
          "profit": {"type": "number"},
          "direction": {
            "enum": ["buy", "sell"],
            "type": "string",
            "x-spec-enum-id": "abc123"
          },
          "additional_info": {
            "\u0024ref": "#/components/schemas/e36568fca95941d68bfb36b27ea0de7e"
          }
        }
      },
      "e36568fca95941d68bfb36b27ea0de7e": {
        "type": "object",
        "properties": {"one_pip": {"type": "number"}}
      },
      "NewsOutput": {
        "type": "object",
        "properties": {
          "categories": {
            "\u0024ref": "#/components/schemas/d84ee9c27d3d444fb27df1dbeaa3184d"
          }
        }
      },
      "d84ee9c27d3d444fb27df1dbeaa3184d": {
        "type": "object",
        "properties": {"title": {"type": "string"}}
      }
    }
  }
}
''';

const prep = SchemaPrep(
  tags: {'Calculators'},
  renameSchemas: {'e36568fca95941d68bfb36b27ea0de7e': 'PipValueAdditionalInfo'},
  hoistEnums: {
    'TradeDirection': ['buy', 'sell'],
  },
  jsonOnlyRequests: true,
  stripResponseEnvelopes: true,
);

Map<String, Object?> schemasOf(Map<String, Object?> doc) =>
    ((doc['components']! as Map)['schemas']! as Map).cast<String, Object?>();

Map<String, Object?> operationOf(Map<String, Object?> doc, String path) =>
    (((doc['paths']! as Map)[path]! as Map).values.first as Map)
        .cast<String, Object?>();

void main() {
  group('SchemaPreparer', () {
    test('renames a hash-named component and every ref to it', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.renamedSchemas, 1);
      final schemas = schemasOf(doc);
      expect(schemas, contains('PipValueAdditionalInfo'));
      expect(schemas, isNot(contains('e36568fca95941d68bfb36b27ea0de7e')));
      expect(
        ((schemas['ProfitOutput']! as Map)['properties']!
            as Map)['additional_info'],
        {r'$ref': '#/components/schemas/PipValueAdditionalInfo'},
      );
    });

    test('resolves a rename written without the namespace prefix', () {
      final doc = document();
      final schemas = schemasOf(doc);
      // Stand in for a document `normalize` has already qualified.
      (doc['components']! as Map)['schemas'] = {
        for (final entry in schemas.entries)
          'Website.${entry.key}': entry.value,
      };

      final result = const SchemaPreparer().prepare(
        doc,
        prep,
        namespacePrefix: 'Website',
      );

      expect(result.renamedSchemas, 1);
      expect(schemasOf(doc), contains('Website.PipValueAdditionalInfo'));
    });

    test('collapses two hash components sharing one name', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(
        doc,
        const SchemaPrep(
          renameSchemas: {
            'e36568fca95941d68bfb36b27ea0de7e': 'Extra',
            'd84ee9c27d3d444fb27df1dbeaa3184d': 'Extra',
          },
        ),
      );

      expect(result.renamedSchemas, 2);
      final schemas = schemasOf(doc);
      expect(schemas.keys.where((k) => k == 'Extra'), hasLength(1));
      expect(schemas, isNot(contains('e36568fca95941d68bfb36b27ea0de7e')));
      expect(schemas, isNot(contains('d84ee9c27d3d444fb27df1dbeaa3184d')));
    });

    test('hoists every matching inline enum onto one component', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.hoistedEnums, 2);
      final schemas = schemasOf(doc);
      expect((schemas['TradeDirection']! as Map)['enum'], ['buy', 'sell']);
      // The definition keeps the exporter's own extensions.
      expect((schemas['TradeDirection']! as Map)['x-spec-enum-id'], 'abc123');
      for (final owner in ['ProfitInput', 'ProfitOutput']) {
        expect(((schemas[owner]! as Map)['properties']! as Map)['direction'], {
          r'$ref': '#/components/schemas/TradeDirection',
        });
      }
    });

    test('keeps only the JSON twin of a duplicated request body', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.droppedRequestBodies, 2);
      final content =
          ((operationOf(doc, '/api/calculator/profit/')['requestBody']!
                  as Map)['content']!
              as Map);
      expect(content.keys, ['application/json']);
    });

    test('leaves a media type that declares a different schema', () {
      final doc = document();
      final content =
          ((operationOf(doc, '/api/calculator/profit/')['requestBody']!
                  as Map)['content']!
              as Map);
      content['multipart/form-data'] = {
        'schema': {r'$ref': '#/components/schemas/ProfitOutput'},
      };

      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.droppedRequestBodies, 1);
      expect(content.keys, contains('multipart/form-data'));
    });

    test('replaces a response envelope with its payload ref', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.strippedEnvelopes, 1);
      final schema =
          ((((operationOf(doc, '/api/calculator/profit/')['responses']!
                          as Map)['200']!
                      as Map)['content']!
                  as Map)['application/json']!
              as Map)['schema'];
      expect(schema, {r'$ref': '#/components/schemas/ProfitOutput'});
    });

    test('leaves a response whose properties are not all envelope fields', () {
      final doc = document();
      final envelope =
          ((((operationOf(doc, '/api/calculator/profit/')['responses']!
                              as Map)['200']!
                          as Map)['content']!
                      as Map)['application/json']!
                  as Map)['schema']!
              as Map;
      (envelope['properties']! as Map)['total_count'] = {'type': 'integer'};

      final result = const SchemaPreparer().prepare(doc, prep);

      expect(result.strippedEnvelopes, 0);
    });

    test('touches nothing outside the configured tags', () {
      final doc = document();
      const SchemaPreparer().prepare(doc, prep);

      final schemas = schemasOf(doc);
      // The news component is hash-named too, but no Calculators route reaches
      // it, so it is left exactly as exported.
      expect(schemas, contains('d84ee9c27d3d444fb27df1dbeaa3184d'));
      final newsSchema =
          (((operationOf(doc, '/api/blog/news/')['responses']! as Map)['200']!
                  as Map)['content']!
              as Map)['application/json']!;
      expect((newsSchema as Map)['schema'], contains('properties'));
    });

    test('reports the hash-named components it was given no name for', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(
        doc,
        const SchemaPrep(tags: {'Calculators'}, stripResponseEnvelopes: true),
      );

      expect(result.unnamedSchemas, ['e36568fca95941d68bfb36b27ea0de7e']);
    });

    test('is a no-op the second time', () {
      final doc = document();
      const SchemaPreparer().prepare(doc, prep);
      final second = const SchemaPreparer().prepare(doc, prep);

      expect(second.changed, isFalse);
      expect(second.describe(), 'nothing to prepare');
    });

    test('does nothing for a prep that turns nothing on', () {
      final doc = document();
      final before = schemasOf(doc).keys.toList();

      final result = const SchemaPreparer().prepare(doc, const SchemaPrep());

      expect(result.changed, isFalse);
      expect(schemasOf(doc).keys, before);
    });

    test('applies every pass across the whole document when no tag is set', () {
      final doc = document();
      final result = const SchemaPreparer().prepare(
        doc,
        const SchemaPrep(stripResponseEnvelopes: true),
      );

      expect(result.strippedEnvelopes, 2);
    });
  });

  group('SchemaPreps.parse', () {
    test('reads every pass of a scheme', () {
      final preps = SchemaPreps.parse('''
schemas:
  website_service:
    tags: [Calculators]
    rename_schemas:
      36306f9579e14754966f345278617b8c: FibonacciLevel
      Row: PivotPointRow
    hoist_enums:
      TradeDirection: [buy, sell]
    json_only_requests: true
    strip_response_envelopes: true
''');

      final prep = preps.prepFor('website_service');
      expect(prep.tags, {'Calculators'});
      expect(prep.renameSchemas, {
        '36306f9579e14754966f345278617b8c': 'FibonacciLevel',
        'Row': 'PivotPointRow',
      });
      expect(prep.hoistEnums, {
        'TradeDirection': ['buy', 'sell'],
      });
      expect(prep.jsonOnlyRequests, isTrue);
      expect(prep.stripResponseEnvelopes, isTrue);
      expect(prep.envelopeKeys, SchemaPrep.defaultEnvelopeKeys);
      expect(prep.envelopeDataKey, 'data');
    });

    test('an unlisted scheme prepares nothing', () {
      final preps = SchemaPreps.parse('schemas:\n  website_service:\n');

      expect(preps.prepFor('crm_service').isEmpty, isTrue);
      expect(preps.prepFor('website_service').isEmpty, isTrue);
    });

    test('an envelope can be described by other field names', () {
      final preps = SchemaPreps.parse('''
schemas:
  website_service:
    strip_response_envelopes: true
    envelope_keys: [status, payload]
    envelope_data_key: payload
''');

      final prep = preps.prepFor('website_service');
      expect(prep.envelopeKeys, {'status', 'payload'});
      expect(prep.envelopeDataKey, 'payload');
    });

    test('an empty or absent document prepares nothing', () {
      expect(SchemaPreps.parse('').isEmpty, isTrue);
      expect(SchemaPreps.parse('# only a comment\n').isEmpty, isTrue);
      expect(SchemaPreps.parse('enums: {}\n').isEmpty, isTrue);
    });

    test('rejects a document it cannot read', () {
      expect(
        () => SchemaPreps.parse('schemas: [website_service]'),
        throwsA(isA<SchemaPrepFormatException>()),
      );
      expect(
        () => SchemaPreps.parse('- website_service'),
        throwsA(isA<SchemaPrepFormatException>()),
      );
      expect(
        () => SchemaPreps.parse(
          'schemas:\n  website_service:\n    hoist_enums:\n      Side: buy\n',
        ),
        throwsA(isA<SchemaPrepFormatException>()),
      );
    });
  });
}
