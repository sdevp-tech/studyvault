// chat_message.dart
enum MessageSide { user, agent }

class ChatMessage {
  final String content;
  final MessageSide side;
  final double latencyMs;
  final String accelerator;
  final String? imagePath; // ✅ إضافة متغير مسار الصورة

  ChatMessage({
    required this.content,
    this.side = MessageSide.user,
    this.latencyMs = 0,
    this.accelerator = '',
    this.imagePath, // ✅ تهيئة المتغير
  });
}