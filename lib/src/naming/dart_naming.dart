/// Reproduces the identifier conventions `swagger_parser` uses, so this package
/// can predict the class name and file name it will emit for a given OpenAPI
/// component key without re-running the generator.
abstract final class DartNaming {
  static final RegExp _keySeparators = RegExp(r'[.`\[\],\s]+');
  static final RegExp _acronymBoundary = RegExp(r'([A-Z]+)([A-Z][a-z])');
  static final RegExp _wordBoundary = RegExp(r'([a-z\d])([A-Z])');
  static final RegExp _nonIdentifier = RegExp(r'[^A-Za-z0-9_$]+');

  /// Dart reserved words that cannot appear bare as an enum member name.
  static const reservedWords = <String>{
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'set',
    'show',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'type',
    'typedef',
    'var',
    'void',
    'when',
    'while',
    'with',
    'yield',
  };

  /// `AIAnalyst.Enums.Analysis.ModeType` → `AiAnalystEnumsAnalysisModeType`.
  static String toClassName(String schemaKey) => schemaKey
      .split(_keySeparators)
      .where((segment) => segment.isNotEmpty)
      .map(_normalizeSegment)
      .join();

  /// `AiAnalystEnumsModeType` → `ai_analyst_enums_mode_type`.
  static String toFileStem(String className) => className
      .replaceAllMapped(_acronymBoundary, (m) => '${m[1]}_${m[2]}')
      .replaceAllMapped(_wordBoundary, (m) => '${m[1]}_${m[2]}')
      .toLowerCase();

  /// Turns [name] into an identifier that compiles as an enum member.
  ///
  /// Override and schema-declared names are hand-written or exporter-written
  /// text, so they may carry spaces, hyphens or a leading digit — all of which
  /// generate a file the analyser rejects. Runs of characters Dart does not
  /// allow become a single `_`, a leading digit gets a `$` in front of it, and
  /// a reserved word gets one after it.
  static String safeMemberName(String name) {
    final cleaned = name.trim().replaceAll(_nonIdentifier, '_');
    if (cleaned.isEmpty) return r'$unnamed';
    final identifier = _startsWithDigit(cleaned) ? '\$$cleaned' : cleaned;
    return reservedWords.contains(identifier) ? '$identifier\$' : identifier;
  }

  static bool _startsWithDigit(String value) {
    final code = value.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  static String _normalizeSegment(String segment) => segment
      .replaceAllMapped(_acronymBoundary, (m) => '${m[1]}_${m[2]}')
      .replaceAllMapped(_wordBoundary, (m) => '${m[1]}_${m[2]}')
      .split('_')
      .where((word) => word.isNotEmpty)
      .map(_capitalize)
      .join();

  /// Matches Python's `str.capitalize()`: first letter up, the rest down —
  /// which is why `AIAnalyst` becomes `AiAnalyst` and not `AIAnalyst`.
  static String _capitalize(String word) =>
      word[0].toUpperCase() + word.substring(1).toLowerCase();
}
