import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads the generator's output tree to find what was produced and what is
/// missing.
class OutputScanner {
  const OutputScanner();

  static final RegExp _modelImport =
      RegExp(r"""import '\.\./models/([^']+)\.dart'""");
  static const _clientSuffix = '_client.dart';
  static const _mapperSuffix = '.mapper.dart';

  /// Every generated model file, folded back to the flat stem the generator
  /// originally emitted.
  ///
  /// The audit may run right after generation (files still flat) or against a
  /// tree that has since been reorganised into per-service folders, so
  /// `crm/enums/account_status.dart` is also reported as
  /// `crm_enums_account_status`.
  Set<String> generatedStems(Directory modelsDir) {
    if (!modelsDir.existsSync()) return {};

    final stems = <String>{};
    for (final file in modelsDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith(_mapperSuffix)) continue;

      final parts = p.split(
        p.withoutExtension(p.relative(file.path, from: modelsDir.path)),
      );
      if (parts.length == 1) {
        stems.add(parts.single);
        continue;
      }
      final group = parts.first;
      final name = parts.last;
      stems.add('${group}_$name');
      if (parts.length >= 3 && parts[1] == 'enums') {
        stems.add('${group}_enums_$name');
      }
    }
    return stems;
  }

  /// Model stems that generated clients import but that were never written.
  ///
  /// `swagger_parser` only emits model files for schemas used in a request or
  /// response body. An enum used solely as a query parameter gets imported by
  /// the client but never produced, which fails the build.
  Set<String> missingModelStems({
    required Directory outputDir,
    required Directory modelsDir,
  }) {
    final missing = <String>{};
    for (final client in clientFiles(outputDir)) {
      for (final match in _modelImport.allMatches(client.readAsStringSync())) {
        final stem = match.group(1)!;
        if (!File(p.join(modelsDir.path, '$stem.dart')).existsSync()) {
          missing.add(stem);
        }
      }
    }
    return missing;
  }

  /// The generated Retrofit client files.
  List<File> clientFiles(Directory outputDir) {
    if (!outputDir.existsSync()) return const [];
    return outputDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith(_clientSuffix) ||
              p.basename(file.path) == 'remote_data_source.dart',
        )
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }
}
