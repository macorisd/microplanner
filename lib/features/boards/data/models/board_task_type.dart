import '../type_list_replacement.dart';

class BoardTaskType {
  const BoardTaskType({
    required this.id,
    required this.boardId,
    required this.name,
    required this.icon,
    required this.sortOrder,
  });

  final String id;
  final String boardId;
  final String name;
  final String icon;
  final int sortOrder;

  factory BoardTaskType.fromJson(Map<String, dynamic> json) => BoardTaskType(
    id: json['id'] as String,
    boardId: json['boardId'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String,
    sortOrder: json['sortOrder'] as int,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'boardId': boardId,
    'name': name,
    'icon': icon,
    'sortOrder': sortOrder,
  };

  BoardTypeEntry get replacementEntry =>
      BoardTypeEntry(id: id, name: name, icon: icon);
}

class TaskTypeList {
  const TaskTypeList({
    required this.id,
    required this.name,
    required this.types,
  });
  final String id;
  final String name;
  final List<TypeListEntry> types;

  factory TaskTypeList.fromJson(Map<String, dynamic> json) => TaskTypeList(
    id: json['id'] as String,
    name: json['name'] as String,
    types: (json['types'] as List).map((value) {
      final entry = Map<String, dynamic>.from(value as Map);
      return TypeListEntry(
        name: entry['name'] as String,
        icon: entry['icon'] as String,
      );
    }).toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'types': [
      for (final type in types) {'name': type.name, 'icon': type.icon},
    ],
  };
}
