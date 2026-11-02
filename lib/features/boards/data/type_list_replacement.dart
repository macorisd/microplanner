/// A type already assigned to tasks on a board.
class BoardTypeEntry {
  const BoardTypeEntry({
    required this.id,
    required this.name,
    required this.icon,
  });

  final String id;
  final String name;
  final String icon;
}

/// A type in a reusable list. Applying it creates an independent board copy.
class TypeListEntry {
  const TypeListEntry({required this.name, required this.icon});

  final String name;
  final String icon;
}

class TypeListReplacement {
  const TypeListReplacement({required this.types, required this.removedIds});

  final List<BoardTypeEntry> types;
  final Set<String> removedIds;

  int affectedTasks(Iterable<String?> taskTypeIds) =>
      taskTypeIds.where((id) => id != null && removedIds.contains(id)).length;
}

/// Keeps an existing identifier only if its normalized name occurs exactly
/// once on both sides. Ambiguous matches never silently move assignments.
TypeListReplacement replaceTypeList({
  required List<BoardTypeEntry> existing,
  required List<TypeListEntry> replacement,
  required String Function() newId,
}) {
  String key(String name) => name.trim().toLowerCase();
  final existingByName = <String, List<BoardTypeEntry>>{};
  for (final entry in existing) {
    existingByName.putIfAbsent(key(entry.name), () => []).add(entry);
  }
  final replacementCounts = <String, int>{};
  for (final entry in replacement) {
    final name = key(entry.name);
    replacementCounts[name] = (replacementCounts[name] ?? 0) + 1;
  }
  final retained = <String>{};
  final result = <BoardTypeEntry>[];
  for (final entry in replacement) {
    final name = key(entry.name);
    final candidates = existingByName[name] ?? const <BoardTypeEntry>[];
    final match = candidates.length == 1 && replacementCounts[name] == 1
        ? candidates.single
        : null;
    if (match != null) retained.add(match.id);
    result.add(
      BoardTypeEntry(
        id: match?.id ?? newId(),
        name: entry.name,
        icon: entry.icon,
      ),
    );
  }
  return TypeListReplacement(
    types: List.unmodifiable(result),
    removedIds: Set.unmodifiable(
      existing.map((e) => e.id).where((id) => !retained.contains(id)),
    ),
  );
}
