import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';

const _auditor = EnumAuditor();

EnumRegistry _registry(List<EnumEntry> entries) =>
    EnumRegistry({for (final entry in entries) entry.fileStem: entry});

const _accountStatus = EnumEntry(
  schemaKey: 'CRM.Enums.AccountStatus',
  className: 'CrmEnumsAccountStatus',
  fileStem: 'crm_enums_account_status',
  values: [0, 1, 2],
  isIntegerEnum: true,
);

const _currency = EnumEntry(
  schemaKey: 'CRM.Enums.Currency',
  className: 'CrmEnumsCurrency',
  fileStem: 'crm_enums_currency',
  values: ['usd'],
  isIntegerEnum: false,
);

void main() {
  test('flags an integer enum with no override', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides.empty(),
    );

    expect(report.byIssue(AuditIssue.missingOverride), hasLength(1));
    expect(report.byIssue(AuditIssue.missingOverride).single.values, [0, 1, 2]);
  });

  test('never flags a string enum', () {
    final report = _auditor.audit(
      registry: _registry([_currency]),
      overrides: const EnumOverrides.empty(),
    );

    expect(report.isClean, isTrue);
  });

  test('flags values the override does not name', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides({
        'CRM.Enums.AccountStatus': EnumOverride(names: {0: 'a', 1: 'b'}),
      }),
    );

    expect(report.byIssue(AuditIssue.missingNames).single.values, [2]);
  });

  test('flags names for values the schema no longer declares', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides({
        'CRM.Enums.AccountStatus': EnumOverride(
          names: {0: 'a', 1: 'b', 2: 'c', 9: 'gone'},
        ),
      }),
    );

    expect(report.byIssue(AuditIssue.staleNames).single.values, [9]);
  });

  test('an extra value counts as declared, so naming it is not stale', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides({
        'CRM.Enums.AccountStatus': EnumOverride(
          names: {0: 'a', 1: 'b', 2: 'c', 3: 'd'},
          extra: [3],
        ),
      }),
    );

    expect(report.isClean, isTrue);
  });

  test('an unnamed extra value is reported as missing', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides({
        'CRM.Enums.AccountStatus': EnumOverride(
          names: {0: 'a', 1: 'b', 2: 'c'},
          extra: [3],
        ),
      }),
    );

    expect(report.byIssue(AuditIssue.missingNames).single.values, [3]);
  });

  test('ignores enums that were never generated', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides.empty(),
      generatedStems: const {},
    );

    expect(report.isClean, isTrue);
  });

  test('formats a clean report', () {
    final text = const AuditFormatter(
      overridesPath: 'enum_overrides.yaml',
    ).format(const AuditReport([]));

    expect(text, contains('All generated integer enums are fully named.'));
  });

  test('formats findings with their section headings', () {
    final report = _auditor.audit(
      registry: _registry([_accountStatus]),
      overrides: const EnumOverrides.empty(),
    );

    final text = const AuditFormatter(
      overridesPath: 'enum_overrides.yaml',
    ).format(report);

    expect(text, contains('MISSING OVERRIDE (1)'));
    expect(text, contains('CRM.Enums.AccountStatus'));
    expect(text, contains('CrmEnumsAccountStatus'));
    expect(text, contains('values: [0, 1, 2]'));
    expect(text, contains('enum_overrides.yaml'));
  });

  group('schema-declared names', () {
    const namedByExport = EnumEntry(
      schemaKey: 'CRM.Enums.Tier',
      className: 'CrmEnumsTier',
      fileStem: 'crm_enums_tier',
      values: [0, 1],
      isIntegerEnum: true,
      schemaNames: {0: 'bronze', 1: 'gold'},
    );

    test('an enum the export names needs no override', () {
      final report = _auditor.audit(
        registry: _registry([namedByExport]),
        overrides: const EnumOverrides.empty(),
      );

      expect(report.isClean, isTrue);
      expect(report.schemaNamed, 1);
    });

    test('the export covering only some values still flags the rest', () {
      final report = _auditor.audit(
        registry: _registry([
          const EnumEntry(
            schemaKey: 'CRM.Enums.Tier',
            className: 'CrmEnumsTier',
            fileStem: 'crm_enums_tier',
            values: [0, 1, 2],
            isIntegerEnum: true,
            schemaNames: {0: 'bronze'},
          ),
        ]),
        overrides: const EnumOverrides.empty(),
      );

      expect(report.byIssue(AuditIssue.missingNames).single.values, [1, 2]);
      expect(report.byIssue(AuditIssue.missingOverride), isEmpty);
    });

    test('an override fills the values the export left unnamed', () {
      final report = _auditor.audit(
        registry: _registry([
          const EnumEntry(
            schemaKey: 'CRM.Enums.Tier',
            className: 'CrmEnumsTier',
            fileStem: 'crm_enums_tier',
            values: [0, 1],
            isIntegerEnum: true,
            schemaNames: {0: 'bronze'},
          ),
        ]),
        overrides: const EnumOverrides({
          'CRM.Enums.Tier': EnumOverride(names: {1: 'gold'}),
        }),
      );

      expect(report.isClean, isTrue);
    });

    test('extra values the override adds are still audited', () {
      final report = _auditor.audit(
        registry: _registry([namedByExport]),
        overrides: const EnumOverrides({
          'CRM.Enums.Tier': EnumOverride(extra: [2]),
        }),
      );

      expect(report.byIssue(AuditIssue.missingNames).single.values, [2]);
    });
  });

  group('duplicate member names', () {
    test('flags two values an override maps onto one name', () {
      final report = _auditor.audit(
        registry: _registry([_accountStatus]),
        overrides: const EnumOverrides({
          'CRM.Enums.AccountStatus': EnumOverride(
            names: {0: 'active', 1: 'active', 2: 'closed'},
          ),
        }),
      );

      final finding = report.byIssue(AuditIssue.duplicateNames).single;
      expect(finding.detail, 'active');
      expect(finding.values, [0, 1]);
    });

    test('flags a string enum whose values lowercase onto one name', () {
      final report = _auditor.audit(
        registry: _registry([
          const EnumEntry(
            schemaKey: 'CRM.Enums.State',
            className: 'CrmEnumsState',
            fileStem: 'crm_enums_state',
            values: ['Draft', 'draft'],
            isIntegerEnum: false,
          ),
        ]),
        overrides: const EnumOverrides.empty(),
      );

      expect(report.byIssue(AuditIssue.duplicateNames).single.values, [
        'Draft',
        'draft',
      ]);
    });

    test('names that differ only by an illegal character collide', () {
      final report = _auditor.audit(
        registry: _registry([_accountStatus]),
        overrides: const EnumOverrides({
          'CRM.Enums.AccountStatus': EnumOverride(
            names: {0: 'in progress', 1: 'in-progress', 2: 'done'},
          ),
        }),
      );

      expect(
        report.byIssue(AuditIssue.duplicateNames).single.detail,
        'in_progress',
      );
    });

    test('stays quiet when every name is distinct', () {
      final report = _auditor.audit(
        registry: _registry([_accountStatus]),
        overrides: const EnumOverrides({
          'CRM.Enums.AccountStatus': EnumOverride(
            names: {0: 'a', 1: 'b', 2: 'c'},
          ),
        }),
      );

      expect(report.isClean, isTrue);
    });

    test('the report names the identifier that is shared', () {
      final report = _auditor.audit(
        registry: _registry([_accountStatus]),
        overrides: const EnumOverrides({
          'CRM.Enums.AccountStatus': EnumOverride(
            names: {0: 'active', 1: 'active', 2: 'closed'},
          ),
        }),
      );

      final text = const AuditFormatter().format(report);
      expect(text, contains('DUPLICATE NAMES (1)'));
      expect(text, contains('shared by "active": [0, 1]'));
    });
  });
}
