import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

const _entry = EnumEntry(
  schemaKey: 'CRM.Enums.AccountStatus',
  className: 'CrmEnumsAccountStatus',
  fileStem: 'crm_enums_account_status',
  values: [0, 1, 2],
  isIntegerEnum: true,
);

void main() {
  test('emits a dart_mappable enum with generated-code markers', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {0: 'active', 1: 'suspended', 2: 'closed'}),
    );

    expect(source, contains('// GENERATED CODE - DO NOT MODIFY BY HAND'));
    expect(source, contains("part 'crm_enums_account_status.mapper.dart';"));
    expect(source, contains('@MappableEnum()'));
    expect(source, contains('enum CrmEnumsAccountStatus {'));
    expect(source, contains('@MappableValue(0)\n  active,'));
    expect(source, contains('@MappableValue(2)\n  closed;'));
  });

  test('falls back to valueN for values the override does not name', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {0: 'active'}),
    );

    expect(source, contains('active,'));
    expect(source, contains('value1,'));
    expect(source, contains('value2;'));
  });

  test('appends extra values not present in the schema', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {3: 'archived'}, extra: [3]),
    );

    expect(source, contains('@MappableValue(3)\n  archived;'));
  });

  test('escapes members that collide with a reserved word', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {0: 'in'}),
    );

    expect(source, contains(r'in$,'));
  });

  test('quotes string enum values', () {
    const stringEntry = EnumEntry(
      schemaKey: 'CRM.Enums.Currency',
      className: 'CrmEnumsCurrency',
      fileStem: 'crm_enums_currency',
      values: ['USD', 'EUR'],
      isIntegerEnum: false,
    );

    final source = const DartMappableEnumEmitter().emit(
      stringEntry,
      const EnumOverride(),
    );

    expect(source, contains("@MappableValue('USD')\n  usd,"));
    expect(source, contains("@MappableValue('EUR')\n  eur;"));
  });

  test('omits compute helpers by default', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(),
    );

    expect(source, isNot(contains('deserializeCrmEnumsAccountStatus')));
  });

  test('emits compute helpers that use the mapper API', () {
    final source = const DartMappableEnumEmitter(
      useFlutterCompute: true,
    ).emit(_entry, const EnumOverride());

    // The mapper API is required because `enums_to_json: false` removes the
    // `fromJson` constructor and `.json` getter the naive template calls.
    expect(source, contains('CrmEnumsAccountStatusMapper.fromValue(json)'));
    expect(source, contains('object?.toValue() as int?'));
    expect(source, isNot(contains('.fromJson(')));
    expect(source, isNot(contains('?.json')));
  });

  test('uses the names the export declares when no override does', () {
    final source = const DartMappableEnumEmitter().emit(
      const EnumEntry(
        schemaKey: 'CRM.Enums.Tier',
        className: 'CrmEnumsTier',
        fileStem: 'crm_enums_tier',
        values: [0, 1],
        isIntegerEnum: true,
        schemaNames: {0: 'bronze', 1: 'gold'},
      ),
      const EnumOverride(),
    );

    expect(source, contains('@MappableValue(0)\n  bronze,'));
    expect(source, contains('@MappableValue(1)\n  gold;'));
  });

  test('an override outranks the name the export declares', () {
    final source = const DartMappableEnumEmitter().emit(
      const EnumEntry(
        schemaKey: 'CRM.Enums.Tier',
        className: 'CrmEnumsTier',
        fileStem: 'crm_enums_tier',
        values: [0, 1],
        isIntegerEnum: true,
        schemaNames: {0: 'bronze', 1: 'gold'},
      ),
      const EnumOverride(names: {1: 'platinum'}),
    );

    expect(source, contains('bronze,'));
    expect(source, contains('platinum;'));
    expect(source, isNot(contains('gold')));
  });

  test('escapes a dollar sign so the literal is not an interpolation', () {
    final source = const DartMappableEnumEmitter().emit(
      const EnumEntry(
        schemaKey: 'CRM.Enums.Currency',
        className: 'CrmEnumsCurrency',
        fileStem: 'crm_enums_currency',
        values: [r'USD$', 'a\nb'],
        isIntegerEnum: false,
      ),
      const EnumOverride(names: {r'USD$': 'usd', 'a\nb': 'ab'}),
    );

    expect(source, contains(r"@MappableValue('USD\$')"));
    expect(source, contains(r"@MappableValue('a\nb')"));
  });

  test('disambiguates two values that ask for one member name', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {0: 'active', 1: 'active', 2: 'closed'}),
    );

    expect(source, contains('@MappableValue(0)\n  active\$1,'));
    expect(source, contains('@MappableValue(1)\n  active\$2,'));
    expect(source, contains('@MappableValue(2)\n  closed;'));
  });

  test('makes an override name with spaces a legal identifier', () {
    final source = const DartMappableEnumEmitter().emit(
      _entry,
      const EnumOverride(names: {0: 'in progress', 1: '2fa', 2: 'done'}),
    );

    expect(source, contains('in_progress,'));
    expect(source, contains('\$2fa,'));
  });
}
