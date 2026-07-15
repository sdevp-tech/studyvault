import 'package:hive/hive.dart';

class NotificationItem extends HiveObject {
  String id;
  String title;
  String body;
  DateTime timestamp;
  bool isRead;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
  });
}

// قمنا بكتابة الـ Adapter يدوياً لتسريع العمل وتجنب أخطاء التوليد
class NotificationItemAdapter extends TypeAdapter<NotificationItem> {
  @override
  final int typeId = 100; // استخدمنا رقم 100 لتجنب أي تعارض مع الـ Adapters الأخرى لديك

  @override
  NotificationItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return NotificationItem(
      id: fields[0] as String,
      title: fields[1] as String,
      body: fields[2] as String,
      timestamp: fields[3] as DateTime,
      isRead: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, NotificationItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.body)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.isRead);
  }
}