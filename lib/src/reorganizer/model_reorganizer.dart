import 'dart:io';

import 'package:path/path.dart' as p;

/// What a reorganisation pass did.
class ReorganizeResult {
  const ReorganizeResult({
    required this.moved,
    required this.groups,
    required this.renamed,
    required this.collisionsKept,
  });

  const ReorganizeResult.noop()
      : moved = 0,
        groups = const [],
        renamed = 0,
        collisionsKept = 0;

  /// Number of model files moved into a namespace folder.
  final int moved;

  /// The namespace folders that now exist, sorted.
  final List<String> groups;

  /// Number of class names that had their namespace prefix stripped.
  final int renamed;

  /// Types that kept their prefix because stripping it would collide with
  /// another service's type of the same name.
  final int collisionsKept;

  bool get changed => moved > 0;

  String describe() => changed
      ? 'moved $moved models into ${groups.length} namespace folders; '
          'renamed $renamed classes'
          '${collisionsKept > 0 ? ', kept $collisionsKept prefixed to avoid '
              'collisions' : ''}'
      : 'models already reorganized';
}

/// One flat generated model and where it is going.
class _Move {
  _Move({required this.group, required this.rest, required this.isEnum});

  final String group;

  /// The file stem with the namespace prefix removed.
  final String rest;
  final bool isEnum;

  late final String newRelative;
}

/// Groups the flat model files `swagger_parser` emits into per-namespace
/// folders and strips the now-redundant namespace prefix from type names.
///
/// `swagger_parser` names every DTO after its full .NET namespace and writes it
/// flat, which produces both very long identifiers and a single directory with
/// hundreds of files:
///
/// ```
/// models/crm_account_types_admin_dtos_account_type_feature_dto.dart
/// class CrmAccountTypesAdminDtosAccountTypeFeatureDto
/// ```
///
/// After this pass:
///
/// ```
/// models/crm/account_types_admin_dtos_account_type_feature_dto.dart
/// class AccountTypesAdminDtosAccountTypeFeatureDto
/// ```
///
/// Enums are routed into an `enums/` subfolder of their namespace, and lose the
/// `Enums` segment as well: `crm_enums_account_status` becomes
/// `crm/enums/account_status.dart` holding `AccountStatus`.
///
/// Run it after the generator and after enum patching, but before
/// `build_runner` — the `.mapper.dart` parts are moved alongside their source,
/// but are only regenerated afterwards.
///
/// Idempotent: once the files are nested there is nothing flat left to match,
/// so re-running is a no-op.
class ModelReorganizer {
  const ModelReorganizer({
    required this.groups,
    this.enumsSubdirectory = 'enums',
  });

  /// `file_prefix -> ClassPrefix`, e.g. `{'crm': 'Crm'}`. Derive it with
  /// `RegistryBuilder.namespacePrefixes` rather than hard-coding it.
  final Map<String, String> groups;

  final String enumsSubdirectory;

  static final RegExp _reference =
      RegExp(r"""(part\s+of|import|export|part)\s+'([^']+)'""");

  static final RegExp _declaration = RegExp(
    r'^\s*(?:@\w+(?:\([^)]*\))?\s*)*'
    r'(?:final\s+|abstract\s+|sealed\s+|base\s+)*(?:class|enum|mixin)\s+(\w+)',
    multiLine: true,
  );

  static const _mapperExtension = '.mapper.dart';
  static const _dartExtension = '.dart';

  /// [modelsDir] is the flat `models/` directory, [apiDir] the generated tree
  /// whose relative imports need fixing, and [rewriteRoots] the source roots
  /// (typically `lib` and `test`) where type names and package URIs are used.
  ReorganizeResult run({
    required Directory modelsDir,
    required Directory apiDir,
    required List<Directory> rewriteRoots,
  }) {
    if (!modelsDir.existsSync()) return const ReorganizeResult.noop();

    final moves = _planMoves(modelsDir);
    if (moves.isEmpty) return const ReorganizeResult.noop();

    _applyMoves(modelsDir, moves);
    final renames = _planRenames(modelsDir, moves);
    final collisions = _dropCollisions(renames);

    _rewriteRelativeReferences(apiDir, modelsDir, moves);
    _rewriteSources(rewriteRoots, moves, renames);

    return ReorganizeResult(
      moved: moves.length,
      groups: (moves.values.map((m) => m.group).toSet().toList())..sort(),
      renamed: renames.length,
      collisionsKept: collisions,
    );
  }

  /// Indexes the flat files and decides each one's destination.
  Map<String, _Move> _planMoves(Directory modelsDir) {
    final moves = <String, _Move>{};

    final names = modelsDir
        .listSync(followLinks: false)
        .whereType<File>()
        .map((f) => p.basename(f.path))
        .toList()
      ..sort();

    for (final name in names) {
      final stem = _stemOf(name);
      if (stem == null) continue;
      final group = _groupFor(stem);
      if (group == null) continue;
      if (moves.containsKey(stem)) continue;

      // Enum-ness is only visible on the source file; the mapper part carries
      // no annotation.
      final source = File(p.join(modelsDir.path, '$stem$_dartExtension'));
      final isEnum = source.existsSync() &&
          source.readAsStringSync().contains('@MappableEnum');

      final rest = stem == group ? stem : stem.substring(group.length + 1);
      final move = _Move(group: group, rest: rest, isEnum: isEnum);

      move.newRelative = isEnum
          ? p.join(
              group,
              enumsSubdirectory,
              rest.startsWith('${enumsSubdirectory}_')
                  ? rest.substring(enumsSubdirectory.length + 1)
                  : rest,
            )
          : p.join(group, rest);

      moves[stem] = move;
    }
    return moves;
  }

  void _applyMoves(Directory modelsDir, Map<String, _Move> moves) {
    for (final entry in moves.entries) {
      Directory(p.dirname(_destination(modelsDir, entry.value, _dartExtension)))
          .createSync(recursive: true);

      for (final extension in const [_dartExtension, _mapperExtension]) {
        final source = File(p.join(modelsDir.path, '${entry.key}$extension'));
        if (source.existsSync()) {
          source.renameSync(_destination(modelsDir, entry.value, extension));
        }
      }
    }
  }

  /// Builds `OldTypeName -> NewTypeName` from the declarations in each moved
  /// file, dropping the namespace prefix.
  Map<String, String> _planRenames(
    Directory modelsDir,
    Map<String, _Move> moves,
  ) {
    final renames = <String, String>{};

    for (final move in moves.values) {
      final file = File(_destination(modelsDir, move, _dartExtension));
      if (!file.existsSync()) continue;

      final prefix = groups[move.group]!;
      for (final match in _declaration.allMatches(file.readAsStringSync())) {
        final identifier = match.group(1)!;
        if (!identifier.startsWith(prefix) ||
            identifier.length <= prefix.length) {
          continue;
        }

        var stripped = identifier.substring(prefix.length);
        // An enum already lives under enums/, so the Enums segment in its name
        // is pure noise: CrmEnumsAccountStatus -> AccountStatus.
        const enumsSegment = 'Enums';
        if (move.isEnum &&
            stripped.startsWith(enumsSegment) &&
            stripped.length > enumsSegment.length) {
          stripped = stripped.substring(enumsSegment.length);
        }
        renames[identifier] = stripped;
      }
    }
    return renames;
  }

  /// Two services can define the same type under different namespaces. Those
  /// keep their prefix, or the generated code would no longer compile.
  int _dropCollisions(Map<String, String> renames) {
    final byNewName = <String, List<String>>{};
    for (final entry in renames.entries) {
      byNewName.putIfAbsent(entry.value, () => []).add(entry.key);
    }

    var dropped = 0;
    for (final claimants in byNewName.values) {
      if (claimants.length < 2) continue;
      for (final old in claimants) {
        renames.remove(old);
        dropped++;
      }
    }
    return dropped;
  }

  /// Fixes the relative `import` / `export` / `part` paths inside the
  /// generated tree, which all still point at the old flat locations.
  void _rewriteRelativeReferences(
    Directory apiDir,
    Directory modelsDir,
    Map<String, _Move> moves,
  ) {
    if (!apiDir.existsSync()) return;

    for (final file in _dartFilesIn(apiDir)) {
      final original = file.readAsStringSync();
      final updated = original.replaceAllMapped(_reference, (match) {
        final keyword = match.group(1)!;
        final reference = match.group(2)!;
        final stem = _stemOf(p.basename(reference));
        final move = stem == null ? null : moves[stem];
        if (move == null) return match.group(0)!;

        final extension = p.basename(reference).endsWith(_mapperExtension)
            ? _mapperExtension
            : _dartExtension;
        final relative = p.relative(
          _destination(modelsDir, move, extension),
          from: p.dirname(file.path),
        );
        return "$keyword '$relative'";
      });

      if (updated != original) file.writeAsStringSync(updated);
    }
  }

  /// Rewrites the generated-model URIs and the renamed type names across the
  /// application's own sources.
  void _rewriteSources(
    List<Directory> roots,
    Map<String, _Move> moves,
    Map<String, String> renames,
  ) {
    final uriPattern = RegExp(
      '(generated/api_clients/models/)([A-Za-z0-9_]+)(\\.mapper)?\\.dart',
    );

    // Matched as a prefix with no trailing boundary, so dart_mappable's
    // derivatives (Mapper, Mappable, CopyWith, …) are stripped along with the
    // base name. Longest-first stops a shorter name matching inside a longer.
    RegExp? namePattern;
    if (renames.isNotEmpty) {
      final alternatives = renames.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      namePattern = RegExp('\\b(${alternatives.map(RegExp.escape).join('|')})');
    }

    for (final root in roots) {
      if (!root.existsSync()) continue;
      for (final file in _dartFilesIn(root)) {
        final original = file.readAsStringSync();

        var updated = original.replaceAllMapped(uriPattern, (match) {
          final move = moves[match.group(2)];
          if (move == null) return match.group(0)!;
          return '${match.group(1)}${move.newRelative}'
              '${match.group(3) ?? ''}$_dartExtension';
        });

        if (namePattern != null) {
          updated = updated.replaceAllMapped(
            namePattern,
            (match) => renames[match.group(1)]!,
          );
        }

        if (updated != original) file.writeAsStringSync(updated);
      }
    }
  }

  String _destination(Directory modelsDir, _Move move, String extension) =>
      p.join(modelsDir.path, '${move.newRelative}$extension');

  /// The file stem, with `.mapper.dart` treated as a single extension.
  String? _stemOf(String fileName) {
    if (fileName.endsWith(_mapperExtension)) {
      return fileName.substring(0, fileName.length - _mapperExtension.length);
    }
    if (fileName.endsWith(_dartExtension)) {
      return fileName.substring(0, fileName.length - _dartExtension.length);
    }
    return null;
  }

  /// The longest matching group prefix, so `ib_service` wins over `ib`.
  String? _groupFor(String stem) {
    String? best;
    for (final group in groups.keys) {
      if (stem != group && !stem.startsWith('${group}_')) continue;
      if (best == null || group.length > best.length) best = group;
    }
    return best;
  }

  Iterable<File> _dartFilesIn(Directory root) => root
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith(_dartExtension));
}
