import 'dart:convert';

import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

const _normalizer = SchemaNormalizer();

Map<String, Object?> _doc(String json) =>
    jsonDecode(json) as Map<String, Object?>;

void main() {
  group('version templates', () {
    test('rewrites {version} using info.version and drops the parameter', () {
      final document = _doc('''
      {
        "info": {"version": "v2"},
        "paths": {
          "/api/v{version}/Plan/List": {
            "get": {
              "parameters": [
                {"in": "path", "name": "version", "required": true},
                {"in": "query", "name": "page"}
              ]
            }
          }
        }
      }
      ''');

      final result = _normalizer.normalize(document);

      expect(result.version, '2');
      expect(result.rewrittenPaths, 1);
      final paths = document['paths']! as Map;
      expect(paths.keys, ['/api/v2/Plan/List']);
      final params =
          (paths['/api/v2/Plan/List'] as Map)['get']['parameters'] as List;
      expect(params, hasLength(1));
      expect((params.single as Map)['name'], 'page');
    });

    test('falls back to version 1 when info.version has no number', () {
      final document = _doc('{"paths": {"/api/v{version}/X": {"get": {}}}}');

      final result = _normalizer.normalize(document);

      expect(result.version, '1');
      expect((document['paths']! as Map).keys, ['/api/v1/X']);
    });

    test('is idempotent on an already concrete path', () {
      final document = _doc('{"paths": {"/api/v1/X": {"get": {}}}}');

      expect(_normalizer.normalize(document).changed, isFalse);
    });

    test('merges into a concrete key that already exists', () {
      final document = _doc('''
      {
        "info": {"version": "1"},
        "paths": {
          "/api/v1/X": {"get": {}},
          "/api/v{version}/X": {"post": {}}
        }
      }
      ''');

      _normalizer.normalize(document);

      final operations = (document['paths']! as Map)['/api/v1/X'] as Map;
      expect(operations.keys, containsAll(<String>['get', 'post']));
    });
  });

  group('schema name prefixing', () {
    test('qualifies bare names and rewrites matching refs', () {
      final document = _doc('''
      {
        "components": {
          "schemas": {
            "AccountData": {
              "properties": {
                "status": {"\$ref": "#/components/schemas/InvestorStatus"}
              }
            },
            "InvestorStatus": {"type": "integer", "enum": [0]}
          }
        }
      }
      ''');

      final result = _normalizer.normalize(
        document,
        namespacePrefix: 'SocialService',
      );

      expect(result.prefixedSchemas, 2);
      final schemas =
          (document['components']! as Map)['schemas'] as Map<String, Object?>;
      expect(
        schemas.keys,
        containsAll(<String>[
          'SocialService.AccountData',
          'SocialService.InvestorStatus',
        ]),
      );
      final ref =
          ((schemas['SocialService.AccountData']! as Map)['properties']
                  as Map)['status']
              as Map;
      expect(ref[r'$ref'], '#/components/schemas/SocialService.InvestorStatus');
    });

    test('leaves already-qualified schemas untouched', () {
      final document = _doc(
        '{"components": {"schemas": {"CRM.Enums.Status": {"enum": [0]}}}}',
      );

      final result = _normalizer.normalize(document, namespacePrefix: 'Crm');

      expect(result.prefixedSchemas, 0);
      expect(((document['components']! as Map)['schemas'] as Map).keys, [
        'CRM.Enums.Status',
      ]);
    });

    test('leaves refs to unknown schemas alone', () {
      final document = _doc('''
      {
        "components": {
          "schemas": {
            "A": {"\$ref": "#/components/schemas/Elsewhere"}
          }
        }
      }
      ''');

      _normalizer.normalize(document, namespacePrefix: 'Svc');

      final schemas = (document['components']! as Map)['schemas'] as Map;
      expect(
        (schemas['Svc.A']! as Map)[r'$ref'],
        '#/components/schemas/Elsewhere',
      );
    });
  });

  test('toNamespacePrefix pascal-cases a scheme name', () {
    expect(
      SchemaNormalizer.toNamespacePrefix('social_service'),
      'SocialService',
    );
    expect(SchemaNormalizer.toNamespacePrefix('crm'), 'Crm');
  });
}
