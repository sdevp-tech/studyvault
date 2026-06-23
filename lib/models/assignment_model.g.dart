// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'assignment_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssignmentAdapter extends TypeAdapter<Assignment> {
  @override
  final int typeId = 13;

  @override
  Assignment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Assignment(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String?,
      type: fields[3] as AssignmentType,
      status: fields[4] as AssignmentStatus,
      dueDate: fields[5] as DateTime,
      completedDate: fields[6] as DateTime?,
      field: fields[7] as String?,
      year: fields[8] as String?,
      subject: fields[9] as String?,
      lecture: fields[10] as String?,
      assetId: fields[11] as String?,
      hasReminder: fields[12] as bool,
      createdAt: fields[13] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Assignment obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.dueDate)
      ..writeByte(6)
      ..write(obj.completedDate)
      ..writeByte(7)
      ..write(obj.field)
      ..writeByte(8)
      ..write(obj.year)
      ..writeByte(9)
      ..write(obj.subject)
      ..writeByte(10)
      ..write(obj.lecture)
      ..writeByte(11)
      ..write(obj.assetId)
      ..writeByte(12)
      ..write(obj.hasReminder)
      ..writeByte(13)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AssignmentTypeAdapter extends TypeAdapter<AssignmentType> {
  @override
  final int typeId = 11;

  @override
  AssignmentType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssignmentType.assignment;
      case 1:
        return AssignmentType.exam;
      case 2:
        return AssignmentType.reminder;
      default:
        return AssignmentType.assignment;
    }
  }

  @override
  void write(BinaryWriter writer, AssignmentType obj) {
    switch (obj) {
      case AssignmentType.assignment:
        writer.writeByte(0);
        break;
      case AssignmentType.exam:
        writer.writeByte(1);
        break;
      case AssignmentType.reminder:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class AssignmentStatusAdapter extends TypeAdapter<AssignmentStatus> {
  @override
  final int typeId = 12;

  @override
  AssignmentStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AssignmentStatus.pending;
      case 1:
        return AssignmentStatus.inProgress;
      case 2:
        return AssignmentStatus.completed;
      case 3:
        return AssignmentStatus.overdue;
      default:
        return AssignmentStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, AssignmentStatus obj) {
    switch (obj) {
      case AssignmentStatus.pending:
        writer.writeByte(0);
        break;
      case AssignmentStatus.inProgress:
        writer.writeByte(1);
        break;
      case AssignmentStatus.completed:
        writer.writeByte(2);
        break;
      case AssignmentStatus.overdue:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssignmentStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
