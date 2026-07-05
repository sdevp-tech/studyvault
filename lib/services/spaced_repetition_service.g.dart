// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spaced_repetition_service.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CardModelAdapter extends TypeAdapter<CardModel> {
  @override
  final int typeId = 16;

  @override
  CardModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CardModel(
      id: fields[0] as String,
      assetId: fields[1] as String,
      snippet: fields[2] as String,
      nextReview: fields[3] as DateTime?,
      intervalDays: fields[4] as int,
      ease: fields[5] as int,
    );
  }

  @override
  void write(BinaryWriter writer, CardModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.assetId)
      ..writeByte(2)
      ..write(obj.snippet)
      ..writeByte(3)
      ..write(obj.nextReview)
      ..writeByte(4)
      ..write(obj.intervalDays)
      ..writeByte(5)
      ..write(obj.ease);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
