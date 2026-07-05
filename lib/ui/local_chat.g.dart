// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_chat.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalChatAdapter extends TypeAdapter<LocalChat> {
  @override
  final int typeId = 4;

  @override
  LocalChat read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalChat(
      chatId: fields[0] as String,
      type: fields[1] as String,
      title: fields[2] as String?,
      participants: (fields[3] as List).cast<String>(),
      lastMessage: fields[4] as String,
      lastUpdate: fields[5] as DateTime,
      adminId: fields[6] as String?,
      unreadCount: fields[7] as int,
      isPinned: fields[8] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalChat obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.chatId)
      ..writeByte(1)
      ..write(obj.type)
      ..writeByte(2)
      ..write(obj.title)
      ..writeByte(3)
      ..write(obj.participants)
      ..writeByte(4)
      ..write(obj.lastMessage)
      ..writeByte(5)
      ..write(obj.lastUpdate)
      ..writeByte(6)
      ..write(obj.adminId)
      ..writeByte(7)
      ..write(obj.unreadCount)
      ..writeByte(8)
      ..write(obj.isPinned);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalChatAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
