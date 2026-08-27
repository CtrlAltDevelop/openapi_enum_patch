import 'dart:io';

import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches the pubspec', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;

    expect(
      packageVersion,
      pubspec['version'].toString(),
      reason:
          'bump packageVersion in lib/src/version.dart with the pubspec, or '
          '--version reports the wrong release',
    );
  });
}
