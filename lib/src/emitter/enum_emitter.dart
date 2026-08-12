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
  const ResolvedMembers(this.members);

  /// Builds the effective member list: schema values first, then any `extra`
  /// values the override adds that the schema does not declare.
  factory ResolvedMembers.resolve(EnumEntry entry, EnumOverride override) {
    final values = <Object>[
      ...entry.values,
      ...override.extra.where((value) => !entry.values.contains(value)),
    ];

    return ResolvedMembers([
      for (final value in values)
        (
          name: DartNaming.safeMemberName(
            override.names[value] ??
                (value is int ? 'value$value' : value.toString().toLowerCase()),
          ),
          value: value,
        ),
    ]);
  }

  final List<({String name, Object value})> members;

  bool get isEmpty => members.isEmpty;
}
