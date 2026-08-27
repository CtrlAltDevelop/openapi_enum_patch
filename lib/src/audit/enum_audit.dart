import 'package:meta/meta.dart';

import '../emitter/enum_emitter.dart';
import '../models/enum_entry.dart';
import '../models/enum_override.dart';

/// The kind of problem an [AuditFinding] reports.
enum AuditIssue {
  /// Nothing names this enum — neither the export nor an override — so it
  /// generates as `value0`, `value1`, …
  missingOverride,

  /// Names exist but do not cover every value.
  missingNames,

  /// `names` maps a value the schema no longer declares.
  staleNames,

  /// Two values resolve to one Dart member name.
  duplicateNames;

  /// A short human label used as the report section heading.
  String get shortName => switch (this) {
    AuditIssue.missingOverride => 'MISSING OVERRIDE',
    AuditIssue.missingNames => 'MISSING NAMES',
    AuditIssue.staleNames => 'STALE NAMES',
    AuditIssue.duplicateNames => 'DUPLICATE NAMES',
  };

  /// One line explaining why the issue matters.
  String get explanation => switch (this) {
    AuditIssue.missingOverride => 'integer enums generate as value0, value1, …',
    AuditIssue.missingNames => 'the names given do not cover every value',
    AuditIssue.staleNames => 'override names a value absent from the schema',
    AuditIssue.duplicateNames =>
      'two values share one member name, emitted '
          r'as name$1, name$2',
  };
}

/// One problem found for one enum.
@immutable
class AuditFinding {
  const AuditFinding({
    required this.issue,
    required this.entry,
    this.values = const [],
    this.detail,
  });

  final AuditIssue issue;
  final EnumEntry entry;

  /// The values the finding is about: all schema values for
  /// [AuditIssue.missingOverride], the unnamed ones for
  /// [AuditIssue.missingNames], the unknown ones for [AuditIssue.staleNames],
  /// and the colliding ones for [AuditIssue.duplicateNames].
  final List<Object> values;

  /// The member name at issue, where one value alone does not identify the
  /// problem — the shared identifier for [AuditIssue.duplicateNames].
  final String? detail;

  @override
  String toString() =>
      '${issue.shortName}: ${entry.schemaKey} (${entry.className}) '
      '${detail == null ? '' : '$detail '}$values';
}

/// The full result of an audit run.
@immutable
class AuditReport {
  const AuditReport(this.findings, {this.schemaNamed = 0});

  final List<AuditFinding> findings;

  /// How many audited integer enums took member names from the export's own
  /// vendor extension, so they needed no override entry.
  final int schemaNamed;

  bool get isClean => findings.isEmpty;

  List<AuditFinding> byIssue(AuditIssue issue) =>
      findings.where((finding) => finding.issue == issue).toList();
}

/// Checks that every generated integer enum is fully named, whether by the
/// export itself or by an override.
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
    var schemaNamed = 0;

    for (final entry in registry.sortedBySchemaKey) {
      if (generatedStems != null && !generatedStems.contains(entry.fileStem)) {
        continue;
      }

      final override = overrides.overrideFor(entry.schemaKey);

      // Collisions are checked for every enum, string ones included: a string
      // enum declaring both `Draft` and `draft` lowercases them onto one
      // member name without any override being involved.
      final resolved = ResolvedMembers.resolve(entry, override);
      for (final collision in resolved.collisions.entries) {
        findings.add(
          AuditFinding(
            issue: AuditIssue.duplicateNames,
            entry: entry,
            values: collision.value,
            detail: collision.key,
          ),
        );
      }

      // String enums take member names from their values, so they are always
      // correctly named without an override.
      if (!entry.isIntegerEnum) continue;

      // The export's own names count as coverage; an override outranks them
      // value by value, so a project can fix just the ones it disagrees with.
      final named = <Object, String>{...entry.schemaNames, ...override.names};
      if (named.isEmpty) {
        findings.add(
          AuditFinding(
            issue: AuditIssue.missingOverride,
            entry: entry,
            values: entry.values,
          ),
        );
        continue;
      }
      if (entry.schemaNames.isNotEmpty) schemaNamed++;

      final effective = <Object>[
        ...entry.values,
        ...override.extra.where((value) => !entry.values.contains(value)),
      ];

      final unnamed = effective
          .where((value) => !named.containsKey(value))
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

      // Only the override's own keys can go stale: the export's names are
      // zipped against the values it declares, so they cannot outlive them.
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

    return AuditReport(findings, schemaNamed: schemaNamed);
  }
}
