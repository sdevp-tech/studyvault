import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive/hive.dart';
import '../ui/local_chat.dart';
import '../ui/local_message.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_service.dart';

class SyncService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Box<LocalChat> _chatBox = Hive.box<LocalChat>('chats_box');
  final Box<LocalMessage> _messageBox = Hive.box<LocalMessage>('messages_box');

  Future<void> syncAll() async {
    await _discoverNewChats();
    for (var chat in _chatBox.values) {
      await syncMessagesForChat(chat.chatId);
    }
    await _syncChatInfo();
  }

  Future<void> _discoverNewChats() async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    final snapshot = await _firestore.collection('chats')
        .where('participants', arrayContains: myUid)
        .get();

    for (var doc in snapshot.docs) {
      if (!_chatBox.containsKey(doc.id)) {
        final data = doc.data();
        
        String title = data['title'] ?? 'محادثة جديدة';
        if (data['type'] == 'individual') {
          final otherUid = (data['participants'] as List).firstWhere((id) => id != myUid, orElse: () => '');
          if (otherUid.isNotEmpty) {
             title = await ChatService().getUserName(otherUid);
          }
        }

        final newChat = LocalChat(
          chatId: doc.id,
          type: data['type'] ?? 'individual',
          title: title,
          participants: List<String>.from(data['participants'] ?? []),
          lastMessage: data['lastMessage'] ?? 'تمت إضافتك للمحادثة',
          lastUpdate: (data['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
          adminId: data['adminId'],
          unreadCount: 1, 
        );
        await _chatBox.put(doc.id, newChat);
      }
    }
  }

  Future<void> _syncChatInfo() async {
    for (var localChat in _chatBox.values) {
      final doc = await _firestore.collection('chats').doc(localChat.chatId).get();
      if (doc.exists) {
        final data = doc.data()!;
        final updatedChat = LocalChat(
          chatId: localChat.chatId,
          type: data['type'] ?? localChat.type,
          title: localChat.title, 
          participants: List<String>.from(data['participants'] ?? localChat.participants),
          lastMessage: localChat.lastMessage,
          lastUpdate: localChat.lastUpdate,
          adminId: data['adminId'] as String?,
          unreadCount: localChat.unreadCount,
          isPinned: localChat.isPinned,
        );
        await _chatBox.put(localChat.chatId, updatedChat);
      }
    }
  }

  Future<void> syncMessagesForChat(String chatId) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    
    // جلب أحدث 50 رسالة دائماً لتجنب أي مشاكل في اختلاف التوقيت بين الأجهزة
    final newSnapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    // معالجة الرسائل وتحديث حالتها إلى 2 (مستلمة)
    await _processSnapshotDocs(chatId, newSnapshot.docs, myUid, isCurrentlyInRoom: false);

    // إعادة حساب عدد الرسائل غير المقروءة بدقة من القاعدة المحلية لمنع التكرار
    final unreadCount = _messageBox.values
        .where((m) => m.chatId == chatId && m.senderId != myUid && m.status < 3)
        .length;
        
    final chat = _chatBox.get(chatId);
    if (chat != null && chat.unreadCount != unreadCount) {
      chat.unreadCount = unreadCount;
      await chat.save();
    }

    // التحقق القوي من الرسائل المعلقة للمرسل وتحديثها (يحل مشكلة الصحين الأزرق عند الانقطاع)
    final localPendingMsgs = _messageBox.values.where((m) => m.chatId == chatId && m.senderId == myUid && m.status < 3).toList();
    for (var msg in localPendingMsgs) {
      try {
        final doc = await _firestore.collection('chats').doc(chatId).collection('messages').doc(msg.messageId).get();
        if (doc.exists) {
          final serverStatus = doc.data()?['status'] ?? 1;
          if (msg.status < serverStatus) {
            msg.status = serverStatus;
            await msg.save();
          }
        }
      } catch (e) {
        // تجاهل الأخطاء العابرة
      }
    }
  }

  Future<void> _processSnapshotDocs(String chatId, List<QueryDocumentSnapshot> docs, String myUid, {bool isCurrentlyInRoom = false}) async {
    if (docs.isEmpty) return;

    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final msgId = doc.id;
      int serverStatus = data['status'] ?? 1;
      bool isDeletedServer = data['isDeleted'] ?? false;

      // تعديل حالة القراءة عند المستقبل بشكل دقيق (تحديث إلى 2 للصحين الرماديين)
      if (data['senderId'] != myUid) {
        if (isCurrentlyInRoom && serverStatus < 3) {
          serverStatus = 3;
          doc.reference.update({'status': 3}).catchError((_) {});
        } else if (!isCurrentlyInRoom && serverStatus == 1) {
          serverStatus = 2; // تم الاستلام (صحين رماديين)
          doc.reference.update({'status': 2}).catchError((_) {});
        }
      }

      if (!_messageBox.containsKey(msgId)) {
        final newMsg = LocalMessage(
          messageId: msgId,
          chatId: chatId,
          senderId: data['senderId'],
          senderName: data['senderName'] ?? "",
          text: data['text'],
          timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          status: serverStatus,
          replyToMessageId: data['replyToMessageId'],
          replyToMessageText: data['replyToMessageText'],
          isDeleted: isDeletedServer,
        );
        await _messageBox.put(msgId, newMsg);
        
        _updateLocalChatPreview(chatId, data['text'], newMsg.timestamp);
      } else {
        final existingMsg = _messageBox.get(msgId)!;
        bool changed = false;

        if (existingMsg.status != serverStatus) {
          existingMsg.status = serverStatus;
          changed = true;
        }
        
        if (isDeletedServer && !existingMsg.isDeleted) {
          existingMsg.isDeleted = true;
          existingMsg.text = '🚫 تم حذف هذه الرسالة';
          changed = true;
          _updateLocalChatPreview(chatId, '🚫 تم حذف هذه الرسالة', existingMsg.timestamp);
        }

        if (changed) await existingMsg.save();
      }
    }
  }

  Stream<QuerySnapshot> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  Future<void> processStreamSnapshots(String chatId, List<QueryDocumentSnapshot> docs, {bool isCurrentlyInRoom = false}) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    await _processSnapshotDocs(chatId, docs, myUid, isCurrentlyInRoom: isCurrentlyInRoom);
  }

  void _updateLocalChatPreview(String chatId, String text, DateTime time) {
    final chat = _chatBox.get(chatId);
    if (chat != null) {
      chat.lastMessage = text;
      chat.lastUpdate = time;
      chat.save();
    }
  }
}
