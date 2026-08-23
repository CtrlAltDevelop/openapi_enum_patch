/// Serialises a decoded OpenAPI document back to block-style YAML.
///
/// The `yaml` package reads but does not write, and the documents this package
/// normalises are plain JSON-shaped data — maps, lists, strings, numbers,
/// booleans and nulls — so a focused emitter is enough and keeps the dependency
/// list lean.
///
/// The output follows the layout OpenAPI exporters use: sequences sit at the
/// same indentation as the key that owns them, and multi-line strings become
/// `|-` block scalars so long `description` fields stay readable.
///
/// Anything that cannot be represented safely as a plain scalar is quoted, so
/// re-reading the result always yields the same data. Comments and the original
/// formatting are not preserved — this rewrites the document, it does not patch
/// it.
class YamlEncoder {
  const YamlEncoder({this.indent = 2});

  /// Spaces per nesting level.
  final int indent;

  /// Characters that would start a plain scalar off as a YAML indicator.
  static const String _indicators = r'''-?:,[]{}#&*!|>'"%@`''';

  /// Scalars that YAML would read back as something other than a string.
  static const Set<String> _reserved = {
    'true',
    'false',
    'null',
    'yes',
    'no',
    'on',
    'off',
    'y',
    'n',
    '~',
    '.inf',
    '-.inf',
    '+.inf',
    '.nan',
  };

  static final RegExp _numberLike = RegExp(
    r'^[+-]?(\d[\d_]*(\.[\d_]*)?|\.\d[\d_]*)([eE][+-]?\d+)?$',
  );
  static final RegExp _radixLike = RegExp(r'^[+-]?0[bxXoO][0-9a-fA-F_]+$');
  static final RegExp _control = RegExp(r'[\x00-\x08\x0b-\x1f\x7f]');

  /// Renders [value] as a YAML document, newline-terminated.
  String convert(Object? value) {
    final out = StringBuffer();
    if (value is Map && value.isNotEmpty) {
      _writeMap(out, value, 0, null);
    } else if (value is List && value.isNotEmpty) {
      _writeList(out, value, 0);
    } else {
      out.writeln(_inline(value));
    }
    return out.toString();
  }

  /// Writes [map]'s entries at [level]. [firstPrefix] replaces the indentation
  /// of the first line, which is how a mapping is hung off a `- ` bullet.
  void _writeMap(
    StringBuffer out,
    Map<Object?, Object?> map,
    int level,
    String? firstPrefix,
  ) {
    var prefix = firstPrefix;
    for (final entry in map.entries) {
      final pad = prefix ?? _pad(level);
      prefix = null;
      final key = _key(entry.key);
      final value = entry.value;

      if (value is Map && value.isNotEmpty) {
        out.writeln('$pad$key:');
        _writeMap(out, value, level + 1, null);
      } else if (value is List && value.isNotEmpty) {
        // Sequences keep the indentation of their key, matching the style
        // OpenAPI exporters emit.
        out.writeln('$pad$key:');
        _writeList(out, value, level);
      } else if (value is String && _isBlockSafe(value)) {
        out.writeln('$pad$key: |-');
        _writeBlock(out, value, level + 1);
      } else {
        out.writeln('$pad$key: ${_inline(value)}');
      }
    }
  }

  void _writeList(StringBuffer out, List<Object?> list, int level) {
    final pad = _pad(level);
    for (final item in list) {
      if (item is Map && item.isNotEmpty) {
        _writeMap(out, item, level + 1, '$pad- ');
      } else if (item is List && item.isNotEmpty) {
        out.writeln('$pad-');
        _writeList(out, item, level + 1);
      } else if (item is String && _isBlockSafe(item)) {
        out.writeln('$pad- |-');
        _writeBlock(out, item, level + 1);
      } else {
        out.writeln('$pad- ${_inline(item)}');
      }
    }
  }

  void _writeBlock(StringBuffer out, String value, int level) {
    final pad = _pad(level);
    for (final line in value.split('\n')) {
      out.writeln(line.isEmpty ? '' : '$pad$line');
    }
  }

  String _pad(int level) => ' ' * (indent * level);

  String _key(Object? key) {
    final text = key.toString();
    // A key must stay on one line, so a block scalar is never an option.
    return text.contains('\n') ? _doubleQuoted(text) : _scalar(text);
  }

  String _inline(Object? value) => switch (value) {
    null => 'null',
    bool() => value.toString(),
    num() => value.toString(),
    String() => _scalar(value),
    Map() => value.isEmpty ? '{}' : _scalar(value.toString()),
    List() => value.isEmpty ? '[]' : _scalar(value.toString()),
    _ => _scalar(value.toString()),
  };

  String _scalar(String value) {
    if (value.contains('\n')) return _doubleQuoted(value);
    return _needsQuotes(value) ? _singleQuoted(value) : value;
  }

  /// Whether [value] would survive as an unquoted plain scalar.
  ///
  /// Deliberately conservative: quoting a string that did not need it is
  /// harmless, letting an unquoted one read back as a number or a boolean is
  /// not.
  bool _needsQuotes(String value) {
    if (value.isEmpty) return true;
    if (value.trim() != value) return true;
    if (_control.hasMatch(value)) return true;
    if (value.contains('\t')) return true;
    if (_indicators.contains(value[0])) return true;
    if (value.contains(': ') || value.endsWith(':')) return true;
    if (value.contains(' #')) return true;
    if (_reserved.contains(value.toLowerCase())) return true;
    if (_numberLike.hasMatch(value) || _radixLike.hasMatch(value)) return true;
    return false;
  }

  String _singleQuoted(String value) => "'${value.replaceAll("'", "''")}'";

  String _doubleQuoted(String value) {
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll('"', r'\"')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r')
        .replaceAll('\t', r'\t');
    return '"$escaped"';
  }

  /// Whether [value] can round-trip through a `|-` literal block.
  ///
  /// `|-` strips trailing newlines, the block's indentation is read off its
  /// first non-empty line, and trailing spaces are easily lost, so each of
  /// those cases falls back to a double-quoted scalar instead.
  bool _isBlockSafe(String value) {
    if (!value.contains('\n')) return false;
    if (value.endsWith('\n')) return false;
    if (value.contains('\r') || _control.hasMatch(value)) return false;

    final lines = value.split('\n');
    if (lines.first.startsWith(' ')) return false;
    return lines.every((line) => line.trimRight() == line);
  }
}
