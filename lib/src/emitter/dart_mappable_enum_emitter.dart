import '../models/enum_entry.dart';
import '../models/enum_override.dart';
import 'enum_emitter.dart';

/// Emits a `dart_mappable` enum, matching the shape `swagger_parser` produces
/// so the generated file drops straight into the existing output tree.
class DartMappableEnumEmitter implements EnumEmitter {
  const DartMappableEnumEmitter({this.useFlutterCompute = false});

  /// Mirrors `swagger_parser`'s `use_flutter_compute` option: when enabled the
  /// generator expects top-level `serialize…`/`deserialize…` helpers to exist
  /// alongside each enum, so they are emitted too.
  final bool useFlutterCompute;

  @override
  String emit(EnumEntry entry, EnumOverride override) {
    final resolved = ResolvedMembers.resolve(entry, override);
    final dartType = entry.isIntegerEnum ? 'int' : 'String';

    final buffer = StringBuffer()
      ..writeln('// coverage:ignore-file')
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND')
      ..writeln(
        '// ignore_for_file: type=lint, unused_import, '
        'invalid_annotation_target, unnecessary_import',
      )
      ..writeln()
      ..writeln("import 'dart:async';")
      ..writeln()
      ..writeln("import 'package:dart_mappable/dart_mappable.dart';")
      ..writeln()
      ..writeln("part '${entry.fileStem}.mapper.dart';")
      ..writeln()
      ..writeln('@MappableEnum()')
      ..writeln('enum ${entry.className} {');

    for (var i = 0; i < resolved.members.length; i++) {
      final member = resolved.members[i];
      final terminator = i == resolved.members.length - 1 ? ';' : ',';
      if (i > 0) buffer.writeln();
      buffer
        ..writeln('  @MappableValue(${_literal(member.value)})')
        ..writeln('  ${member.name}$terminator');
    }

    buffer
      ..writeln()
      ..writeln('  String toJson() => toValue().toString();')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  String toString() => toValue().toString();')
      ..writeln('}');

    if (useFlutterCompute) {
      _writeComputeHelpers(buffer, entry.className, dartType);
    }

    return buffer.toString();
  }

  void _writeComputeHelpers(
    StringBuffer buffer,
    String className,
    String dartType,
  ) {
    buffer
      ..writeln()
      ..writeln('// Flutter compute serialization functions for $className')
      ..writeln('FutureOr<$className> deserialize$className($dartType json) =>')
      ..writeln('    ${className}Mapper.fromValue(json);')
      ..writeln()
      ..writeln(
        'FutureOr<List<$className>> '
        'deserialize${className}List(List<$dartType> json) =>',
      )
      ..writeln('    json.map(${className}Mapper.fromValue).toList();')
      ..writeln()
      ..writeln(
        'FutureOr<$dartType?> '
        'serialize$className($className? object) =>',
      )
      ..writeln('    object?.toValue() as $dartType?;')
      ..writeln()
      ..writeln(
        'FutureOr<List<$dartType?>> '
        'serialize${className}List(List<$className>? objects) =>',
      )
      ..writeln(
        '    objects?.map((e) => e.toValue() as $dartType?).toList() '
        '?? [];',
      );
  }

  /// String values must be quoted; integers must not.
  String _literal(Object value) {
    if (value is int) return '$value';
    final escaped = value
        .toString()
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'");
    return "'$escaped'";
  }
}
