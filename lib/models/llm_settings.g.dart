// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LlmSettingsAdapter extends TypeAdapter<LlmSettings> {
  @override
  final int typeId = 20;

  @override
  LlmSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LlmSettings(
      systemPrompt: fields[0] as String,
      temperature: fields[1] as double,
      topK: fields[2] as int,
      maxTokens: fields[3] as int,
      useSystemPrompt: fields[4] as bool,
      backend: fields[5] as String,
      modelPath: fields[6] as String,
    );
  }

  @override
  void write(BinaryWriter writer, LlmSettings obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.systemPrompt)
      ..writeByte(1)
      ..write(obj.temperature)
      ..writeByte(2)
      ..write(obj.topK)
      ..writeByte(3)
      ..write(obj.maxTokens)
      ..writeByte(4)
      ..write(obj.useSystemPrompt)
      ..writeByte(5)
      ..write(obj.backend)
      ..writeByte(6)
      ..write(obj.modelPath);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
