import 'dart:io';

import 'package:openapi_enum_patch/openapi_enum_patch.dart';

/// Audits enum-override coverage for a project, without writing anything.
///
/// ```sh
/// dart run example/openapi_enum_patch_example.dart /path/to/project
/// ```
///
/// The CLI equivalent is `dart run openapi_enum_patch audit --root <path>`.
void main(List<String> arguments) {
  final root = arguments.isEmpty ? '.' : arguments.first;

  final config = SwaggerParserConfig.parse(
    File('$root/swagger_tools/swagger_parser.yaml').readAsStringSync(),
  );
  final overridesFile = File('$root/swagger_tools/enum_overrides.yaml');
  final overrides = overridesFile.existsSync()
      ? EnumOverrides.parse(overridesFile.readAsStringSync())
      : const EnumOverrides.empty();

  final patcher = EnumPatcher(root: root, config: config);

  // Inspect the registry directly — every enum the schemas declare.
  final registry = patcher.buildRegistry();
  final integerEnums = registry.all.where((e) => e.isIntegerEnum).length;
  final selfNaming = registry.all.where((e) => e.isSchemaNamed).length;
  stdout.writeln(
    'Found ${registry.all.length} enum(s), $integerEnums of them integer, '
    '$selfNaming already named by the export.',
  );

  final report = patcher.patchDryRunReport(overrides);
  stdout.write(
    const AuditFormatter(
      overridesPath: 'swagger_tools/enum_overrides.yaml',
    ).format(report),
  );

  if (!report.isClean) exitCode = 1;
}
