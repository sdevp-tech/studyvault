import 'package:hive/hive.dart';

part 'local_message.g.dart';

@HiveType(typeId: 1)
class LocalMessage extends HiveObject {
  @HiveField(0)
  final String messageId;

  @HiveField(1)
  final String chatId;

  @HiveField(2)
  final String senderId;

  @HiveField(3)
  String text;

  @HiveField(4)
  final DateTime timestamp;

  @HiveField(5)
  int status; // 0: جاري, 1: أرسل, 2: استلم, 3: قرأ (أزرق)

  @HiveField(6)
  final String senderName; 

  @HiveField(7) // جديد: آيدي الرسالة المُرد عليها
  final String? replyToMessageId;

  @HiveField(8) // جديد: نص الرسالة المُرد عليها
  final String? replyToMessageText;

  @HiveField(9) // جديد: حالة الحذف
  bool isDeleted;

  LocalMessage({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    this.status = 1,
    this.senderName = "",
    this.replyToMessageId,
    this.replyToMessageText,
    this.isDeleted = false,
  });
}
