// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'annotation_service.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AnnotationAdapter extends TypeAdapter<Annotation> {
  @override
  final int typeId = 17;

  @override
  Annotation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Annotation(
      id: fields[0] as String,
      assetId: fields[1] as String,
      page: fields[2] as String,
      text: fields[3] as String,
      x: fields[4] as double,
      y: fields[5] as double,
      createdAt: fields[6] as DateTime?,
      color: fields[7] as String?,
      type: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Annotation obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.assetId)
      ..writeByte(2)
      ..write(obj.page)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.x)
      ..writeByte(5)
      ..write(obj.y)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.color)
      ..writeByte(8)
      ..write(obj.type);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnotationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
