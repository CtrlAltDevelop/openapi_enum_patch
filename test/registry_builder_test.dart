import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

const _builder = RegistryBuilder();

const _schema = '''
{
  "components": {
    "schemas": {
      "CRM.Enums.AccountStatus": {"type": "integer", "enum": [0, 1, 2]},
      "CRM.Enums.Currency": {"type": "string", "enum": ["usd", "eur"]},
      "CRM.Models.Account": {"type": "object"},
      "CRM.Enums.Untyped": {"enum": [0, 1]}
    }
  }
}
''';

void main() {
  test('indexes only schemas that declare an enum', () {
    final registry = _builder.buildFromJson(_schema);

    expect(
      registry.entries.keys,
      containsAll(<String>[
        'crm_enums_account_status',
        'crm_enums_currency',
        'crm_enums_untyped',
      ]),
    );
    expect(registry.byStem('crm_models_account'), isNull);
  });

  test('predicts the generated class name and file stem', () {
    final entry = _builder
        .buildFromJson(_schema)
        .bySchemaKey('CRM.Enums.AccountStatus');

    expect(entry, isNotNull);
    expect(entry!.className, 'CrmEnumsAccountStatus');
    expect(entry.fileStem, 'crm_enums_account_status');
    expect(entry.values, [0, 1, 2]);
  });

  test('classifies integer and string enums', () {
    final registry = _builder.buildFromJson(_schema);

    expect(registry.byStem('crm_enums_account_status')!.isIntegerEnum, isTrue);
    expect(registry.byStem('crm_enums_currency')!.isIntegerEnum, isFalse);
  });

  test('infers an integer enum from its values when type is absent', () {
    final registry = _builder.buildFromJson(_schema);

    expect(registry.byStem('crm_enums_untyped')!.isIntegerEnum, isTrue);
  });

  test('merges several documents', () {
    final registry = _builder.build([
      _builder.decode(_schema),
      _builder.decode(
        '{"components": {"schemas": '
        '{"SocialService.InvestorStatus": {"type": "integer", "enum": [0]}}}}',
      ),
    ]);

    expect(registry.byStem('social_service_investor_status'), isNotNull);
    expect(registry.byStem('crm_enums_account_status'), isNotNull);
  });

  test('tolerates a document with no components', () {
    expect(_builder.buildFromJson('{}').all, isEmpty);
  });

  test('reports the source on malformed JSON', () {
    expect(
      () => _builder.buildFromJson('{oops', source: 'crm.json'),
      throwsA(
        isA<SchemaFormatException>().having(
          (e) => e.toString(),
          'message',
          contains('crm.json'),
        ),
      ),
    );
  });

  group('schema-declared member names', () {
    test('reads x-enum-varnames zipped against the values', () {
      final registry = const RegistryBuilder().buildFromJson('''
{
  "components": {
    "schemas": {
      "CRM.Enums.AccountStatus": {
        "type": "integer",
        "enum": [0, 1, 2],
        "x-enum-varnames": ["Active", "Suspended", "Closed"]
      }
    }
  }
}
''');

      final entry = registry.byStem('crm_enums_account_status')!;
      expect(entry.schemaNames, {0: 'Active', 1: 'Suspended', 2: 'Closed'});
      expect(entry.isSchemaNamed, isTrue);
    });

    test('reads the NSwag x-enumNames spelling', () {
      final registry = const RegistryBuilder().buildFromYaml('''
components:
  schemas:
    CRM.Enums.Platform:
      type: integer
      enum: [1, 2]
      x-enumNames: [Web, Mobile]
''');

      expect(registry.byStem('crm_enums_platform')!.schemaNames, {
        1: 'Web',
        2: 'Mobile',
      });
    });

    test('reads x-ms-enum, which pairs each name with its value', () {
      final registry = const RegistryBuilder().buildFromYaml('''
components:
  schemas:
    CRM.Enums.Tier:
      type: integer
      enum: [10, 20]
      x-ms-enum:
        name: Tier
        values:
          - value: 20
            name: Gold
          - value: 10
            name: Silver
''');

      expect(registry.byStem('crm_enums_tier')!.schemaNames, {
        20: 'Gold',
        10: 'Silver',
      });
    });

    test('names the values a truncated list reaches and no more', () {
      final registry = const RegistryBuilder().buildFromYaml('''
components:
  schemas:
    CRM.Enums.Partial:
      type: integer
      enum: [0, 1, 2]
      x-enum-varnames: [First, '']
''');

      final entry = registry.byStem('crm_enums_partial')!;
      expect(entry.schemaNames, {0: 'First'});
      expect(entry.isSchemaNamed, isFalse);
    });

    test('leaves schemaNames empty when the export declares none', () {
      final registry = const RegistryBuilder().buildFromYaml('''
components:
  schemas:
    CRM.Enums.Bare:
      type: integer
      enum: [0, 1]
''');

      expect(registry.byStem('crm_enums_bare')!.schemaNames, isEmpty);
      expect(registry.byStem('crm_enums_bare')!.isSchemaNamed, isFalse);
    });
  });
}
