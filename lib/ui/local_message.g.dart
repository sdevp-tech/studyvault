// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LocalMessageAdapter extends TypeAdapter<LocalMessage> {
  @override
  final int typeId = 1;

  @override
  LocalMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LocalMessage(
      messageId: fields[0] as String,
      chatId: fields[1] as String,
      senderId: fields[2] as String,
      text: fields[3] as String,
      timestamp: fields[4] as DateTime,
      status: fields[5] as int,
      senderName: fields[6] as String,
      replyToMessageId: fields[7] as String?,
      replyToMessageText: fields[8] as String?,
      isDeleted: fields[9] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, LocalMessage obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.senderId)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.senderName)
      ..writeByte(7)
      ..write(obj.replyToMessageId)
      ..writeByte(8)
      ..write(obj.replyToMessageText)
      ..writeByte(9)
      ..write(obj.isDeleted);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LocalMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
