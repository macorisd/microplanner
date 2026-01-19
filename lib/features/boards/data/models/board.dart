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

  Board({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Board.create({
    required String id,
    required String name,
  }) {
    return Board(
      id: id,
      name: name,
      createdAt: DateTime.now(),
    );
  }

  Board copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
  }) {
    return Board(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'Board(id: $id, name: $name)';
}
