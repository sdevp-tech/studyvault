import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_message.dart';
import '../../services/chat_service.dart';
import '../../services/sync_service.dart';
import '../mobile_scanner.dart';
import '../local_chat.dart';
import '../l10n/app_localizations.dart';

class ChatRoomScreen extends StatefulWidget {
  final String chatId;
  final String title;

  const ChatRoomScreen({super.key, required this.chatId, required this.title});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  final String myUid = FirebaseAuth.instance.currentUser!.uid;

  late final Stream<QuerySnapshot> _messagesStream;
  Timer? _typingTimer;
  LocalMessage? _replyingTo;

  @override
  void initState() {
    super.initState();
    _messagesStream = SyncService().getMessagesStream(widget.chatId);
    SyncService().syncMessagesForChat(widget.chatId);
    ChatService().markMessagesAsRead(widget.chatId);

    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    ChatService().updateTypingStatus(widget.chatId, true);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      ChatService().updateTypingStatus(widget.chatId, false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    ChatService().updateTypingStatus(widget.chatId, false);
    ChatService().markMessagesAsRead(widget.chatId);
    super.dispose();
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    await ChatService().sendMessage(
      widget.chatId,
      text,
      replyToId: _replyingTo?.messageId,
      replyToText: _replyingTo?.text,
    );
    setState(() => _replyingTo = null);
  }

  void _showOptions(LocalMessage msg, bool isMe) {
    final local = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (_) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.reply),
            title: Text(local.translate('reply_to_message')),
            onTap: () {
              setState(() => _replyingTo = msg);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(local.translate('copy_text')),
            onTap: () {
              Clipboard.setData(ClipboardData(text: msg.text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(local.translate('copied')))
              );
              Navigator.pop(context);
            },
          ),
          if (isMe && !msg.isDeleted)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: Text(local.translate('delete_for_everyone'), style: const TextStyle(color: Colors.red)),
              onTap: () {
                ChatService().deleteMessageForEveryone(widget.chatId, msg.messageId);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }

  Widget _getStatusIcon(int status, bool isDeleted) {
    if (isDeleted) return const SizedBox.shrink();
    switch (status) {
      case 1:
        return const Icon(Icons.check, size: 14, color: Colors.grey);
      case 2:
        return const Icon(Icons.done_all, size: 14, color: Colors.grey);
      case 3:
        return const Icon(Icons.done_all, size: 14, color: Colors.blue);
      default:
        return const Icon(Icons.access_time, size: 14, color: Colors.grey);
    }
  }

  Widget _buildAppBarTitle(LocalChat? chat) {
    final local = AppLocalizations.of(context);
    bool isGroup = chat?.type == 'group';
    String? otherUserId;
    if (!isGroup && chat != null) {
      otherUserId = chat.participants.firstWhere((id) => id != myUid, orElse: () => '');
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, chatSnap) {
        bool isSomeoneTyping = false;
        if (chatSnap.hasData && chatSnap.data!.exists) {
          final data = chatSnap.data!.data() as Map<String, dynamic>;
          final typingMap = data['typing'] as Map<String, dynamic>? ?? {};
          isSomeoneTyping = typingMap.entries.any((e) => e.key != myUid && e.value == true);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 18)),
            if (isSomeoneTyping)
              Text(local.translate('typing'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.secondary))
            else if (!isGroup && otherUserId != null && otherUserId.isNotEmpty)
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(otherUserId).snapshots(),
                builder: (context, userSnap) {
                  if (userSnap.hasData && userSnap.data!.exists) {
                    final userData = userSnap.data!.data() as Map<String, dynamic>;
                    final isOnline = userData['isOnline'] ?? false;
                    if (isOnline) {
                      return Text(local.translate('online_now'), style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.secondary));
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final chat = Hive.box<LocalChat>('chats_box').get(widget.chatId);
    final bool isGroup = chat?.type == 'group';
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(chat),
        actions: [
          if (isGroup && chat?.adminId == myUid)
            IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QRScannerScreen(chatId: widget.chatId))),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _messagesStream,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    SyncService().processStreamSnapshots(widget.chatId, snapshot.data!.docs, isCurrentlyInRoom: true);
                  });
                }

                return ValueListenableBuilder(
                  valueListenable: Hive.box<LocalMessage>('messages_box').listenable(),
                  builder: (context, Box<LocalMessage> box, _) {
                    final messages = box.values.where((m) => m.chatId == widget.chatId).toList()
                      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                    if (messages.isEmpty) return Center(child: Text(local.translate('no_messages_yet')));

                    return ListView.builder(
                      reverse: true,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == myUid;

                        // ألوان ديناميكية حسب الثيم
                        final bubbleColor = isMe
                            ? (isDark ? Colors.indigo.shade700 : const Color(0xFFDCF8C6))
                            : (isDark ? Colors.grey.shade800 : Colors.white);
                        
                        final textColor = isMe
                            ? (isDark ? Colors.white : Colors.black)
                            : (isDark ? Colors.white : Colors.black);
                        
                        final replyBackgroundColor = isDark ? Colors.grey.shade700.withValues(alpha: 0.3) : Colors.grey.shade100;
                        final replyTextColor = isDark ? Colors.grey.shade400 : Colors.black54;
                        final senderNameColor = isDark ? Colors.cyan.shade200 : Colors.blueGrey;
                        final timestampColor = isDark ? Colors.grey.shade400 : Colors.black54;

                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _showOptions(msg, isMe),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: bubbleColor,
                                borderRadius: BorderRadius.circular(12).copyWith(
                                  bottomLeft: isMe ? const Radius.circular(12) : Radius.zero,
                                  bottomRight: isMe ? Radius.zero : const Radius.circular(12),
                                ),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isGroup && !isMe)
                                    Text(
                                      msg.senderName,
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: senderNameColor)
                                    ),
                                  
                                  // صندوق الرد داخل الرسالة
                                  if (msg.replyToMessageText != null)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: replyBackgroundColor,
                                        borderRadius: BorderRadius.circular(8),
                                        border: const Border(right: BorderSide(color: Colors.blueAccent, width: 4)),
                                      ),
                                      child: Text(
                                        msg.replyToMessageText!,
                                        style: TextStyle(fontSize: 13, color: replyTextColor),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis
                                      ),
                                    ),
                                    
                                  Text(
                                    msg.text,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontStyle: msg.isDeleted ? FontStyle.italic : FontStyle.normal,
                                      color: msg.isDeleted ? Colors.grey : textColor
                                    )
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                                        style: TextStyle(fontSize: 10, color: timestampColor)
                                      ),
                                      const SizedBox(width: 4),
                                      if (isMe) _getStatusIcon(msg.status, msg.isDeleted),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // عرض الرسالة المُراد الرد عليها فوق حقل الإدخال
          if (_replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          local.translate('reply_to'),
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)
                        ),
                        Text(
                          _replyingTo!.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.black54)
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => setState(() => _replyingTo = null)
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(8),
            color: theme.scaffoldBackgroundColor,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: theme.textTheme.bodyLarge?.color),
                    decoration: InputDecoration(
                      hintText: local.translate('type_message'),
                      hintStyle: TextStyle(color: isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}