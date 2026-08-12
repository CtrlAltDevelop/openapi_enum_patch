/// Reproduces the identifier conventions `swagger_parser` uses, so this package
/// can predict the class name and file name it will emit for a given OpenAPI
/// component key without re-running the generator.
abstract final class DartNaming {
  static final RegExp _keySeparators = RegExp(r'[.`\[\],\s]+');
  static final RegExp _acronymBoundary = RegExp(r'([A-Z]+)([A-Z][a-z])');
  static final RegExp _wordBoundary = RegExp(r'([a-z\d])([A-Z])');

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

  /// Appends `$` when [name] collides with a Dart reserved word.
  static String safeMemberName(String name) =>
      reservedWords.contains(name) ? '$name\$' : name;

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
