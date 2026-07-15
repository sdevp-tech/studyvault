import 'package:hive/hive.dart';

part 'local_chat.g.dart';

@HiveType(typeId: 4)
class LocalChat extends HiveObject {
  @HiveField(0)
  final String chatId;

  @HiveField(1)
  final String type; // individual or group

  @HiveField(2)
   String? title; // اسم المجموعة أو اسم الطرف الآخر

  @HiveField(3)
  final List<String> participants;

  @HiveField(4)
  String lastMessage;

  @HiveField(5)
  DateTime lastUpdate;

  @HiveField(6)
  final String? adminId; // معرف مدير المجموعة (للمجموعات فقط)

  @HiveField(7) // جديد: عداد الرسائل غير المقروءة
  int unreadCount;

  @HiveField(8) // جديد: حالة التثبيت
  bool isPinned;

  LocalChat({
    required this.chatId,
    required this.type,
    this.title,
    required this.participants,
    required this.lastMessage,
    required this.lastUpdate,
    this.adminId,
    this.unreadCount = 0,
    this.isPinned = false,
  });
}
