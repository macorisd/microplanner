import 'package:hive/hive.dart';

part 'board.g.dart';

/// Board model representing a task board
@HiveType(typeId: 1)
class Board extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  final DateTime createdAt;

  @HiveField(3, defaultValue: 0)
  int sortOrder;

  Board({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
  });

  factory Board.create({
    required String id,
    required String name,
    int sortOrder = 0,
  }) {
    return Board(
      id: id,
      name: name,
      createdAt: DateTime.now(),
      sortOrder: sortOrder,
    );
  }

  Board copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    int? sortOrder,
  }) {
    return Board(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  String toString() => 'Board(id: $id, name: $name)';
}
