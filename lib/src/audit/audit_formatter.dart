import 'enum_audit.dart';

/// Renders an [AuditReport] as the plain-text block printed at the end of a run.
class AuditFormatter {
  const AuditFormatter({this.indent = '  ', this.overridesPath});

  final String indent;

  /// Named in the closing summary so the reader knows which file to edit.
  final String? overridesPath;

  String format(AuditReport report) {
    final buffer = StringBuffer()
      ..writeln()
      ..writeln('$indent── Enum override audit ${'─' * 42}');

    for (final issue in AuditIssue.values) {
      final findings = report.byIssue(issue);
      if (findings.isEmpty) continue;
      buffer.writeln(
        '$indent${issue.shortName} (${findings.length}): ${issue.explanation}',
      );
      for (final finding in findings) {
        buffer.writeln(
          '$indent  - ${finding.entry.schemaKey}  '
          '(${finding.entry.className})  '
          '${_label(issue)}: ${finding.values}',
        );
      }
    }

    if (report.isClean) {
      buffer.writeln(
        '${indent}All generated integer enums are fully overridden.',
      );
    } else {
      final target = overridesPath ?? 'the overrides file';
      buffer.writeln(
        '$indent${report.findings.length} enum(s) need attention in $target.',
      );
    }

    buffer.writeln('$indent${'─' * 65}');
    return buffer.toString();
  }

  String _label(AuditIssue issue) => switch (issue) {
    AuditIssue.missingOverride => 'values',
    AuditIssue.missingNames => 'unnamed',
    AuditIssue.staleNames => 'unknown',
  };
}
