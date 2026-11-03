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

  // These fields are stored in workspace JSON; old Hive records use defaults.
  String icon;
  int color;

  Board({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
    this.icon = 'board',
    this.color = 0xff7986cb,
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
      color: 0xff90a4ae,
    );
  }

  Board copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    int? sortOrder,
    String? icon,
    int? color,
  }) {
    return Board(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortOrder: sortOrder ?? this.sortOrder,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }

  @override
  String toString() => 'Board(id: $id, name: $name)';
}
