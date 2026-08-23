import 'dart:io';

import 'package:args/args.dart';
import 'package:openapi_enum_patch/openapi_enum_patch.dart';
import 'package:path/path.dart' as p;

const _version = '1.1.0';

Future<void> main(List<String> arguments) async {
  final parser = _buildArgParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(_usage(parser));
    exitCode = 64; // EX_USAGE
    return;
  }

  if (args.flag('help')) {
    stdout.writeln(_usage(parser));
    return;
  }
  if (args.flag('version')) {
    stdout.writeln('openapi_enum_patch $_version');
    return;
  }

  final command = args.rest.isEmpty ? 'patch' : args.rest.first;
  if (!const {'normalize', 'patch', 'audit', 'reorganize'}.contains(command)) {
    stderr
      ..writeln('Unknown command "$command".')
      ..writeln()
      ..writeln(_usage(parser));
    exitCode = 64;
    return;
  }

  final root = args.option('root')!;
  final configPath = p.join(root, args.option('config')!);
  final overridesPath = p.join(root, args.option('overrides')!);

  final SwaggerParserConfig config;
  try {
    config = SwaggerParserConfig.parse(File(configPath).readAsStringSync());
  } on FileSystemException {
    stderr.writeln('Error: config not found at $configPath');
    exitCode = 1;
    return;
  } on FormatException catch (e) {
    stderr.writeln('Error: could not read $configPath — ${e.message}');
    exitCode = 1;
    return;
  }

  final EnumOverrides overrides;
  try {
    overrides = _loadOverrides(overridesPath);
  } on EnumOverrideFormatException catch (e) {
    stderr.writeln('Error: could not read $overridesPath — ${e.message}');
    exitCode = 1;
    return;
  }

  final patcher = EnumPatcher(root: root, config: config);

  try {
    switch (command) {
      case 'normalize':
        _runNormalize(patcher);
      case 'audit':
        _printAudit(
          patcher.patchDryRunReport(overrides),
          args.option('overrides')!,
        );
      case 'reorganize':
        final result = patcher.reorganizeModels();
        stdout.writeln('  ${result.describe()}');
      case 'patch':
        final result = patcher.patch(overrides);
        _printPatch(result);
        _printAudit(result.report, args.option('overrides')!);
        if (args.flag('strict') && !result.report.isClean) exitCode = 1;
    }
  } on SchemaFormatException catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message} (${e.path})');
    exitCode = 1;
  }
}

EnumOverrides _loadOverrides(String path) {
  final file = File(path);
  if (!file.existsSync()) return const EnumOverrides.empty();
  return EnumOverrides.parse(file.readAsStringSync());
}

void _runNormalize(EnumPatcher patcher) {
  final results = patcher.normalizeSchemas();
  if (results.isEmpty) {
    stdout.writeln('  Schemas already normalized.');
    return;
  }
  for (final result in results) {
    stdout.writeln('  Normalized ${result.describe()}');
  }
}

void _printPatch(PatchResult result) {
  for (final stem in result.generated) {
    stdout.writeln('  Generated (missing): $stem.dart');
  }
  for (final entry in result.overridden.entries) {
    stdout.writeln('  Overridden (${entry.value}): ${entry.key}.dart');
  }
  for (final key in result.unknownOverrideKeys) {
    stderr.writeln('  WARNING: override key "$key" is not in any schema');
  }
  for (final stem in result.unresolvedImports) {
    stderr.writeln(
      '  WARNING: import "$stem" is missing and is not an enum in any schema',
    );
  }
  if (result.didNothing) stdout.writeln('  Nothing to do.');
}

void _printAudit(AuditReport report, String overridesPath) {
  stdout.write(AuditFormatter(overridesPath: overridesPath).format(report));
}

ArgParser _buildArgParser() => ArgParser()
  ..addOption(
    'root',
    abbr: 'r',
    defaultsTo: '.',
    help: 'Project root that config paths are relative to.',
    valueHelp: 'path',
  )
  ..addOption(
    'config',
    abbr: 'c',
    defaultsTo: 'swagger_parser.yaml',
    help: 'Path to swagger_parser.yaml, relative to --root.',
    valueHelp: 'path',
  )
  ..addOption(
    'overrides',
    abbr: 'o',
    defaultsTo: 'enum_overrides.yaml',
    help: 'Path to enum_overrides.yaml, relative to --root.',
    valueHelp: 'path',
  )
  ..addFlag(
    'strict',
    negatable: false,
    help: 'Exit non-zero when the audit finds any enum needing attention.',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this usage.')
  ..addFlag('version', negatable: false, help: 'Print the version.');

String _usage(ArgParser parser) => '''
Name, complete and audit swagger_parser's integer enums.

Usage: dart run openapi_enum_patch <command> [options]

Commands:
  normalize   Rewrite {version} path templates and qualify bare schema names.
              Run BEFORE swagger_parser.
  patch       Generate skipped enum files, apply overrides, print the audit.
              Run AFTER swagger_parser. (default)
  audit       Print the audit only, changing nothing.
  reorganize  Group flat models into per-namespace folders and strip the
              redundant prefix from their type names. Run AFTER patch and
              BEFORE build_runner.

Schemas may be JSON or YAML; the format is taken from the file extension
(.json, .yaml, .yml) and sniffed from the content for anything else.

${parser.usage}''';
