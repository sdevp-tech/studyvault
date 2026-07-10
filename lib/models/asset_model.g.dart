// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetModelAdapter extends TypeAdapter<AssetModel> {
  @override
  final int typeId = 0;

  @override
  AssetModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssetModel(
      id: fields[0] as String,
      field: fields[1] as String,
      year: fields[2] as String,
      subject: fields[3] as String,
      lecture: fields[4] as String?,
      fileName: fields[5] as String,
      filePath: fields[6] as String,
      type: fields[7] as String,
      tags: (fields[8] as List).cast<String>(),
      createdAt: fields[9] as DateTime,
      notes: fields[10] as String?,
      extractedText: fields[11] as String?,
      thumbnailPath: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, AssetModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.field)
      ..writeByte(2)
      ..write(obj.year)
      ..writeByte(3)
      ..write(obj.subject)
      ..writeByte(4)
      ..write(obj.lecture)
      ..writeByte(5)
      ..write(obj.fileName)
      ..writeByte(6)
      ..write(obj.filePath)
      ..writeByte(7)
      ..write(obj.type)
      ..writeByte(8)
      ..write(obj.tags)
      ..writeByte(9)
      ..write(obj.createdAt)
      ..writeByte(10)
      ..write(obj.notes)
      ..writeByte(11)
      ..write(obj.extractedText)
      ..writeByte(12)
      ..write(obj.thumbnailPath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
