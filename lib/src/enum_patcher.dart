import 'dart:io';

import 'package:path/path.dart' as p;

import 'audit/enum_audit.dart';
import 'config/schema_prep_config.dart';
import 'config/swagger_parser_config.dart';
import 'emitter/dart_mappable_enum_emitter.dart';
import 'emitter/enum_emitter.dart';
import 'models/enum_entry.dart';
import 'models/enum_override.dart';
import 'normalizer/schema_normalizer.dart';
import 'output_scanner.dart';
import 'prepare/schema_preparer.dart';
import 'registry_builder.dart';
import 'reorganizer/model_reorganizer.dart';
import 'schema/schema_codec.dart';

/// What a patch run did.
class PatchResult {
  const PatchResult({
    required this.generated,
    required this.overridden,
    required this.report,
    required this.unknownOverrideKeys,
    required this.unresolvedImports,
  });

  /// Stems written because a client imported them but no file existed.
  final List<String> generated;

  /// Stems rewritten to apply an override, as `stem -> what changed`.
  final Map<String, String> overridden;

  final AuditReport report;

  /// Override keys that match no schema — usually a typo or a renamed schema.
  final List<String> unknownOverrideKeys;

  /// Imports that are missing and are not enums in any schema, so this package
  /// cannot synthesise them.
  final List<String> unresolvedImports;

  bool get didNothing => generated.isEmpty && overridden.isEmpty;
}

/// Normalises schemas, fills in enum files the generator skipped, applies
/// overrides, and audits coverage.
class EnumPatcher {
  EnumPatcher({
    required this.root,
    required this.config,
    EnumEmitter? emitter,
    RegistryBuilder? registryBuilder,
    OutputScanner? scanner,
    EnumAuditor? auditor,
  }) : _emitter =
           emitter ??
           DartMappableEnumEmitter(useFlutterCompute: config.useFlutterCompute),
       _registryBuilder = registryBuilder ?? const RegistryBuilder(),
       _scanner = scanner ?? const OutputScanner(),
       _auditor = auditor ?? const EnumAuditor();

  /// The project root that all config paths are relative to.
  final String root;
  final SwaggerParserConfig config;

  final EnumEmitter _emitter;
  final RegistryBuilder _registryBuilder;
  final OutputScanner _scanner;
  final EnumAuditor _auditor;

  Directory get outputDir => Directory(p.join(root, config.outputDirectory));
  Directory get modelsDir =>
      Directory(p.join(outputDir.path, config.modelsSubdirectory));

  /// Rewrites each configured schema in place, applying the preparation passes
  /// [preps] declares for it. Run this *first*, before [normalizeSchemas].
  ///
  /// A scheme with no entry, or an entry that turns nothing on, is skipped —
  /// most exports need no preparation at all.
  Map<String, PreparationResult> prepareSchemas(
    SchemaPreps preps, {
    SchemaPreparer preparer = const SchemaPreparer(),
  }) {
    final results = <String, PreparationResult>{};
    for (final scheme in config.schemes) {
      final prep = preps.prepFor(scheme.name);
      if (prep.isEmpty) continue;

      final file = File(p.join(root, scheme.schemaPath));
      if (!file.existsSync()) continue;

      final content = file.readAsStringSync();
      final format = SchemaFormat.resolve(
        path: scheme.schemaPath,
        content: content,
      );
      final document = _registryBuilder.decode(
        content,
        source: scheme.schemaPath,
        format: format,
      );
      final result = preparer.prepare(
        document,
        prep,
        namespacePrefix: _prefixFor(scheme),
      );
      if (result.changed) {
        file.writeAsStringSync(const SchemaCodec().encode(document, format));
      }
      results[scheme.name] = result;
    }
    return results;
  }

  /// Rewrites each configured schema in place, applying the `{version}` and
  /// namespace-prefix fixes. Run this *before* `swagger_parser`.
  List<NormalizationResult> normalizeSchemas({
    SchemaNormalizer normalizer = const SchemaNormalizer(),
  }) {
    final results = <NormalizationResult>[];
    for (final scheme in config.schemes) {
      final file = File(p.join(root, scheme.schemaPath));
      if (!file.existsSync()) continue;

      final content = file.readAsStringSync();
      final format = SchemaFormat.resolve(
        path: scheme.schemaPath,
        content: content,
      );
      final document = _registryBuilder.decode(
        content,
        source: scheme.schemaPath,
        format: format,
      );
      final result = normalizer.normalize(
        document,
        namespacePrefix: _prefixFor(scheme),
      );
      if (result.changed) {
        // Rewritten in the format it was read in, so a YAML schema stays YAML.
        file.writeAsStringSync(const SchemaCodec().encode(document, format));
        results.add(result);
      }
    }
    return results;
  }

  /// The namespace prefix `normalize` gives [scheme]'s components.
  String _prefixFor(SchemeConfig scheme) => SchemaNormalizer.toNamespacePrefix(
    scheme.name.isNotEmpty
        ? scheme.name
        : p.basenameWithoutExtension(scheme.schemaPath),
  );

  /// Reads every configured schema and indexes the enums in them.
  EnumRegistry buildRegistry() {
    final documents = <Map<String, Object?>>[];
    for (final scheme in config.schemes) {
      final file = File(p.join(root, scheme.schemaPath));
      if (!file.existsSync()) continue;
      documents.add(
        _registryBuilder.decode(
          file.readAsStringSync(),
          source: scheme.schemaPath,
        ),
      );
    }
    return _registryBuilder.build(documents);
  }

  /// Groups the flat generated models into per-namespace folders and strips
  /// the redundant prefix from their type names.
  ///
  /// Run after [patch] and before `build_runner`. [rewriteRoots] are the source
  /// roots whose type references need updating, relative to [root].
  ReorganizeResult reorganizeModels({
    List<String> rewriteRoots = const ['lib', 'test'],
    Map<String, String>? groups,
  }) {
    final prefixes = groups ?? _namespacePrefixes();
    if (prefixes.isEmpty) return const ReorganizeResult.noop();

    return ModelReorganizer(groups: prefixes).run(
      modelsDir: modelsDir,
      apiDir: outputDir,
      rewriteRoots: [for (final r in rewriteRoots) Directory(p.join(root, r))],
    );
  }

  /// Reads every configured schema and derives the namespace prefixes.
  Map<String, String> _namespacePrefixes() {
    final documents = <Map<String, Object?>>[];
    for (final scheme in config.schemes) {
      final file = File(p.join(root, scheme.schemaPath));
      if (!file.existsSync()) continue;
      documents.add(
        _registryBuilder.decode(
          file.readAsStringSync(),
          source: scheme.schemaPath,
        ),
      );
    }
    return _registryBuilder.namespacePrefixes(documents);
  }

  /// Audits override coverage without writing anything.
  AuditReport patchDryRunReport(EnumOverrides overrides) => _auditor.audit(
    registry: buildRegistry(),
    overrides: overrides,
    generatedStems: _scanner.generatedStems(modelsDir),
  );

  /// Runs the post-generation passes. Run this *after* `swagger_parser`.
  PatchResult patch(EnumOverrides overrides) {
    final registry = buildRegistry();
    final stemsByKey = registry.stemsBySchemaKey;

    final generated = <String>[];
    final unresolved = <String>[];

    // Pass 1 — synthesise files for enums the generator skipped.
    final missing = _scanner.missingModelStems(
      outputDir: outputDir,
      modelsDir: modelsDir,
    );
    for (final stem in missing.toList()..sort()) {
      final entry = registry.byStem(stem);
      if (entry == null) {
        unresolved.add(stem);
        continue;
      }
      _write(entry, overrides.overrideFor(entry.schemaKey));
      generated.add(stem);
    }

    // Pass 2 — re-emit existing files so overrides take effect.
    final overridden = <String, String>{};
    final unknownKeys = <String>[];
    for (final entry in overrides.bySchemaKey.entries) {
      if (entry.value.isEmpty) continue;

      final stem = stemsByKey[entry.key];
      if (stem == null) {
        unknownKeys.add(entry.key);
        continue;
      }
      if (generated.contains(stem)) continue; // Already written with overrides.
      if (!File(p.join(modelsDir.path, '$stem.dart')).existsSync()) continue;

      _write(registry.entries[stem]!, entry.value);
      overridden[stem] = entry.value.describe();
    }

    return PatchResult(
      generated: generated,
      overridden: overridden,
      unknownOverrideKeys: unknownKeys..sort(),
      unresolvedImports: unresolved..sort(),
      report: _auditor.audit(
        registry: registry,
        overrides: overrides,
        generatedStems: _scanner.generatedStems(modelsDir),
      ),
    );
  }

  void _write(EnumEntry entry, EnumOverride override) {
    final file = File(p.join(modelsDir.path, '${entry.fileStem}.dart'))
      ..createSync(recursive: true);
    file.writeAsStringSync(_emitter.emit(entry, override));
  }
}
