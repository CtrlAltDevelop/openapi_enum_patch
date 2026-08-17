import 'package:meta/meta.dart';

import '../models/enum_entry.dart';
import '../models/enum_override.dart';

/// The kind of problem an [AuditFinding] reports.
enum AuditIssue {
  /// No override entry at all — the enum generates as `value0`, `value1`, …
  missingOverride,

  /// An override exists but its `names` map does not cover every value.
  missingNames,

  /// `names` maps a value the schema no longer declares.
  staleNames;

  /// A short human label used as the report section heading.
  String get shortName => switch (this) {
    AuditIssue.missingOverride => 'MISSING OVERRIDE',
    AuditIssue.missingNames => 'MISSING NAMES',
    AuditIssue.staleNames => 'STALE NAMES',
  };

  /// One line explaining why the issue matters.
  String get explanation => switch (this) {
    AuditIssue.missingOverride => 'integer enums generate as value0, value1, …',
    AuditIssue.missingNames => 'override exists but does not name every value',
    AuditIssue.staleNames => 'override names a value absent from the schema',
  };
}

/// One problem found for one enum.
@immutable
class AuditFinding {
  const AuditFinding({
    required this.issue,
    required this.entry,
    this.values = const [],
  });

  final AuditIssue issue;
  final EnumEntry entry;

  /// The values the finding is about: all schema values for
  /// [AuditIssue.missingOverride], the unnamed ones for
  /// [AuditIssue.missingNames], the unknown ones for [AuditIssue.staleNames].
  final List<Object> values;

  @override
  String toString() =>
      '${issue.shortName}: ${entry.schemaKey} (${entry.className}) $values';
}

/// The full result of an audit run.
@immutable
class AuditReport {
  const AuditReport(this.findings);

  final List<AuditFinding> findings;

  bool get isClean => findings.isEmpty;

  List<AuditFinding> byIssue(AuditIssue issue) =>
      findings.where((finding) => finding.issue == issue).toList();
}

/// Checks that every generated integer enum is fully named by an override.
///
/// Only enums that were actually generated are considered, so unused schema
/// enums never produce noise.
class EnumAuditor {
  const EnumAuditor();

  /// [generatedStems] is the set of file stems that exist in the output tree.
  /// Pass `null` to audit every enum in [registry] regardless of generation.
  AuditReport audit({
    required EnumRegistry registry,
    required EnumOverrides overrides,
    Set<String>? generatedStems,
  }) {
    final findings = <AuditFinding>[];

    for (final entry in registry.sortedBySchemaKey) {
      if (generatedStems != null && !generatedStems.contains(entry.fileStem)) {
        continue;
      }
      // String enums take member names from their values, so they are always
      // correctly named without an override.
      if (!entry.isIntegerEnum) continue;

      final override = overrides.overrideFor(entry.schemaKey);
      if (override.names.isEmpty) {
        findings.add(
          AuditFinding(
            issue: AuditIssue.missingOverride,
            entry: entry,
            values: entry.values,
          ),
        );
        continue;
      }

      final effective = <Object>[
        ...entry.values,
        ...override.extra.where((value) => !entry.values.contains(value)),
      ];

      final unnamed = effective
          .where((value) => !override.names.containsKey(value))
          .toList(growable: false);
      if (unnamed.isNotEmpty) {
        findings.add(
          AuditFinding(
            issue: AuditIssue.missingNames,
            entry: entry,
            values: unnamed,
          ),
        );
      }

      final stale = override.names.keys
          .where((value) => !effective.contains(value))
          .toList(growable: false);
      if (stale.isNotEmpty) {
        findings.add(
          AuditFinding(
            issue: AuditIssue.staleNames,
            entry: entry,
            values: stale,
          ),
        );
      }
    }

    return AuditReport(findings);
  }
}
