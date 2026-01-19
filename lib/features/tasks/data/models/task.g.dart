// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TaskAdapter extends TypeAdapter<Task> {
  @override
  final int typeId = 0;

  @override
  Task read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Task(
      id: fields[0] as String,
      name: fields[1] as String,
      deadline: fields[2] as DateTime,
      typeIndex: fields[3] as int,
      priorityIndex: fields[4] as int,
      subject: fields[5] as String,
      isCompleted: fields[6] as bool,
      createdAt: fields[7] as DateTime,
      boardId: fields[8] as String?,
      subjectId: fields[9] as String?,
    );
  }

  void write(BinaryWriter writer, Task obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.deadline)
      ..writeByte(3)
      ..write(obj.typeIndex)
      ..writeByte(4)
      ..write(obj.priorityIndex)
      ..writeByte(5)
      ..write(obj.subject)
      ..writeByte(6)
      ..write(obj.isCompleted)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.boardId)
      ..writeByte(9)
      ..write(obj.subjectId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TaskAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
