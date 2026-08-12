import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

void main() {
  test('parses names and extra values', () {
    final overrides = EnumOverrides.parse('''
enums:
  "AIAnalyst.Enums.Analysis.AnalysisModeType":
    names:
      0: fundamental
      1: technical
    extra:
      - 3
''');

    final override = overrides.overrideFor(
      'AIAnalyst.Enums.Analysis.AnalysisModeType',
    );
    expect(override.names, {0: 'fundamental', 1: 'technical'});
    expect(override.extra, [3]);
    expect(override.describe(), 'names, +1 values');
  });

  test('returns an empty override for an unknown key', () {
    const overrides = EnumOverrides.empty();

    expect(overrides.overrideFor('nope').isEmpty, isTrue);
  });

  test('treats a missing enums section as empty', () {
    expect(EnumOverrides.parse('other: 1').isEmpty, isTrue);
    expect(EnumOverrides.parse('').isEmpty, isTrue);
  });

  test('normalises quoted integer keys to ints', () {
    final overrides = EnumOverrides.parse('''
enums:
  "A.B":
    names:
      "0": zero
''');

    expect(overrides.overrideFor('A.B').names[0], 'zero');
  });

  test('accepts extra written as a mapping, using its keys', () {
    final overrides = EnumOverrides.parse('''
enums:
  "CRM.Enums.RealDemoType":
    names:
      0: unknown
    extra:
      3: archived
''');

    expect(overrides.overrideFor('CRM.Enums.RealDemoType').extra, [3]);
  });

  test('rejects a malformed override entry', () {
    expect(
      () => EnumOverrides.parse('enums:\n  "A.B": 5\n'),
      throwsA(isA<EnumOverrideFormatException>()),
    );
    expect(
      () => EnumOverrides.parse('enums:\n  "A.B":\n    names: [1, 2]\n'),
      throwsA(isA<EnumOverrideFormatException>()),
    );
    expect(
      () => EnumOverrides.parse('enums: 5'),
      throwsA(isA<EnumOverrideFormatException>()),
    );
  });
}
