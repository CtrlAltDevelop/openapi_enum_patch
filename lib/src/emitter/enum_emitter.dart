import '../models/enum_entry.dart';
import '../models/enum_override.dart';
import '../naming/dart_naming.dart';

/// Renders a Dart enum file for one [EnumEntry].
///
/// An interface so projects on a different serializer (json_serializable,
/// freezed, hand-rolled) can plug in their own template without forking the
/// registry, override and audit machinery.
abstract interface class EnumEmitter {
  String emit(EnumEntry entry, EnumOverride override);
}

/// The member names and values an emitter should render, after applying an
/// override on top of the schema.
class ResolvedMembers {
  const ResolvedMembers(this.members, {this.collisions = const {}});

  /// Builds the effective member list: schema values first, then any `extra`
  /// values the override adds that the schema does not declare.
  ///
  /// Each value takes its name from the first source that has one — the
  /// override, then the names the export declares, then the `valueN` fallback
  /// that made this package necessary.
  factory ResolvedMembers.resolve(EnumEntry entry, EnumOverride override) {
    final values = <Object>[
      ...entry.values,
      ...override.extra.where((value) => !entry.values.contains(value)),
    ];

    // Pass 1 — the identifier each value asks for.
    final requested = <({String name, Object value})>[
      for (final value in values)
        (name: memberNameFor(entry, override, value), value: value),
    ];

    final valuesByName = <String, List<Object>>{};
    for (final member in requested) {
      (valuesByName[member.name] ??= <Object>[]).add(member.value);
    }

    // Pass 2 — two values asking for one identifier would not compile, so each
    // of them is suffixed. Both are suffixed rather than just the later one, so
    // neither reads as the legitimate owner of the name.
    final taken = <String, int>{};
    final members = <({String name, Object value})>[];
    for (final member in requested) {
      if (valuesByName[member.name]!.length == 1) {
        members.add(member);
        continue;
      }
      final ordinal = (taken[member.name] ?? 0) + 1;
      taken[member.name] = ordinal;
      members.add((name: '${member.name}\$$ordinal', value: member.value));
    }

    return ResolvedMembers(
      members,
      collisions: {
        for (final entry in valuesByName.entries)
          if (entry.value.length > 1) entry.key: entry.value,
      },
    );
  }

  /// The identifier [value] generates as, before collisions are resolved.
  static String memberNameFor(
    EnumEntry entry,
    EnumOverride override,
    Object value,
  ) => DartNaming.safeMemberName(
    override.names[value] ??
        entry.schemaNames[value] ??
        (value is int ? 'value$value' : value.toString().toLowerCase()),
  );

  final List<({String name, Object value})> members;

  /// Identifiers that more than one value asked for, as `name -> values`.
  ///
  /// Empty for a healthy enum. The audit reports these, because a `$1`/`$2`
  /// pair in the output is a naming mistake made visible, not a fix.
  final Map<String, List<Object>> collisions;

  bool get isEmpty => members.isEmpty;
}
