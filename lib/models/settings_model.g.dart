// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 6;

  @override
  AppSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppSettings(
      fieldsTitle: fields[0] as String,
      yearsTitle: fields[1] as String,
      subjectsTitle: fields[2] as String,
      lecturesTitle: fields[3] as String,
      assignmentsTitle: fields[4] as String,
      examsTitle: fields[5] as String,
      todoTitle: fields[6] as String,
      isDarkMode: fields[7] as bool,
      language: fields[8] as String,
      isFirstTime: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.fieldsTitle)
      ..writeByte(1)
      ..write(obj.yearsTitle)
      ..writeByte(2)
      ..write(obj.subjectsTitle)
      ..writeByte(3)
      ..write(obj.lecturesTitle)
      ..writeByte(4)
      ..write(obj.assignmentsTitle)
      ..writeByte(5)
      ..write(obj.examsTitle)
      ..writeByte(6)
      ..write(obj.todoTitle)
      ..writeByte(7)
      ..write(obj.isDarkMode)
      ..writeByte(8)
      ..write(obj.language)
      ..writeByte(9)
      ..write(obj.isFirstTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
