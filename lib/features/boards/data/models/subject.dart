import 'package:hive/hive.dart';

part 'subject.g.dart';

@HiveType(typeId: 2)
class Subject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String boardId;

  @HiveField(3, defaultValue: 0xFFCCCCCC)
  final int color; // Store color as int (0xAARRGGBB)

  final int sortOrder;

  const Subject({
    required this.id,
    required this.name,
    required this.boardId,
    this.color = 0xFFCCCCCC, // Default gray if not specified
    this.sortOrder = 0,
  });

  Subject copyWith({
    String? id,
    String? name,
    String? boardId,
    int? color,
    int? sortOrder,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      boardId: boardId ?? this.boardId,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  String toString() {
    return 'Subject(id: $id, name: $name, boardId: $boardId, color: $color)';
  }
}
