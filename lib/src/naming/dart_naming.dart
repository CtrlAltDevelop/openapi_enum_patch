/// Reproduces the identifier conventions `swagger_parser` uses, so this package
/// can predict the class name and file name it will emit for a given OpenAPI
/// component key without re-running the generator.
abstract final class DartNaming {
  static final RegExp _keySeparators = RegExp(r'[.`\[\],\s]+');
  static final RegExp _acronymBoundary = RegExp(r'([A-Z]+)([A-Z][a-z])');
  static final RegExp _wordBoundary = RegExp(r'([a-z\d])([A-Z])');
  static final RegExp _nonIdentifier = RegExp(r'[^A-Za-z0-9_$]+');

  /// Dart reserved words, which cannot appear bare as an enum member name.
  ///
  /// Built-in and contextual identifiers (`type`, `get`, `on`, `required`, …)
  /// are legal member names and are deliberately absent.
  static const reservedWords = <String>{
    'assert',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'default',
    'do',
    'else',
    'enum',
    'extends',
    'false',
    'final',
    'finally',
    'for',
    'if',
    'in',
    'is',
    'new',
    'null',
    'rethrow',
    'return',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'var',
    'void',
    'while',
    'with',
  };

  /// Names an enum member cannot take because every enum already has a member
  /// or static of that name — `values` is declared by the language, the rest
  /// are inherited from `Enum`/`Object` — or because the emitter declares it.
  static const enumMemberClashes = <String>{
    'values',
    'index',
    'hashCode',
    'runtimeType',
    'toString',
    'noSuchMethod',
    'toJson',
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
  /// allow become a single `_` (a non-ASCII letter becomes `u` and its code
  /// point in hex, so distinct characters stay distinct), a leading digit gets a `$` in front of it, and
  /// a reserved word or a name every enum already owns (`values`, `index`, …)
  /// gets one after it.
  static String safeMemberName(String name) {
    final cleaned = _spellNonAscii(name.trim()).replaceAll(_nonIdentifier, '_');
    if (cleaned.isEmpty) return r'$unnamed';
    final identifier = _startsWithDigit(cleaned) ? '\$$cleaned' : cleaned;
    return reservedWords.contains(identifier) ||
            enumMemberClashes.contains(identifier)
        ? '$identifier\$'
        : identifier;
  }

  /// `Étoile` → `u00c9toile`. Only letters are spelled out; punctuation and
  /// whitespace still collapse to `_` afterwards.
  static String _spellNonAscii(String value) => value.runes
      .map(
        (rune) => rune > 0x7f && _isLetter(rune)
            ? 'u${rune.toRadixString(16).padLeft(4, '0')}'
            : String.fromCharCode(rune),
      )
      .join();

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  static bool _isLetter(int rune) =>
      _letter.hasMatch(String.fromCharCode(rune));

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
