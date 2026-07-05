import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive/hive.dart';
import '../ui/local_chat.dart';
import '../ui/local_message.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Box<LocalChat> _chatBox = Hive.box<LocalChat>('chats_box');
  final Box<LocalMessage> _messageBox = Hive.box<LocalMessage>('messages_box');

  String _generateChatId(String uid1, String uid2) {
    List<String> ids = [uid1, uid2];
    ids.sort();
    return ids.join('_');
  }

  // جديد: التحقق من أن المستخدم موجود بالفعل
  Future<bool> checkUserExists(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  Future<String> getUserName(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      return doc.data()?['fullName'] ?? "مستخدم غير معروف";
    } catch (e) {
      return "مستخدم";
    }
  }

  Future<void> updateUserPresence(bool isOnline) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    await _firestore.collection('users').doc(myUid).set({
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateTypingStatus(String chatId, bool isTyping) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return;
    await _firestore.collection('chats').doc(chatId).set({
      'typing': {myUid: isTyping}
    }, SetOptions(merge: true));
  }

  Future<void> resetUnreadCount(String chatId) async {
    final chat = _chatBox.get(chatId);
    if (chat != null && chat.unreadCount > 0) {
      chat.unreadCount = 0;
      await chat.save();
    }
  }

  Future<void> togglePinChat(String chatId) async {
    final chat = _chatBox.get(chatId);
    if (chat != null) {
      chat.isPinned = !chat.isPinned;
      await chat.save();
    }
  }

  Future<String> startIndividualChat(String otherUserUid, String otherUserName) async {
    final myUid = _auth.currentUser!.uid;
    final chatId = _generateChatId(myUid, otherUserUid);

    await _firestore.collection('chats').doc(chatId).set({
      'type': 'individual',
      'participants': [myUid, otherUserUid],
      'lastMessageTime': FieldValue.serverTimestamp(),
      'typing': {}, 
    }, SetOptions(merge: true));

    if (!_chatBox.containsKey(chatId)) {
      await _chatBox.put(chatId, LocalChat(
        chatId: chatId,
        type: 'individual',
        title: otherUserName,
        participants: [myUid, otherUserUid],
        lastMessage: 'بدء المحادثة...',
        lastUpdate: DateTime.now(),
        adminId: null,
      ));
    }
    return chatId;
  }

  Future<void> createGroupChat(String groupName, List<String> memberUids) async {
    final myUid = _auth.currentUser!.uid;
    if (!memberUids.contains(myUid)) memberUids.add(myUid);

    final groupDoc = _firestore.collection('chats').doc();

    await groupDoc.set({
      'type': 'group',
      'title': groupName,
      'participants': memberUids,
      'adminId': myUid,
      'createdAt': FieldValue.serverTimestamp(),
      'typing': {},
    });

    await _chatBox.put(groupDoc.id, LocalChat(
      chatId: groupDoc.id,
      type: 'group',
      title: groupName,
      participants: memberUids,
      lastMessage: 'تم إنشاء المجموعة',
      lastUpdate: DateTime.now(),
      adminId: myUid,
    ));
  }

  Future<void> addMemberToGroup(String chatId, String newUserUid) async {
    await _firestore.collection('chats').doc(chatId).update({
      'participants': FieldValue.arrayUnion([newUserUid]),
    });

    final localChat = _chatBox.get(chatId);
    if (localChat != null && !localChat.participants.contains(newUserUid)) {
      localChat.participants.add(newUserUid);
      await localChat.save();
    }
  }

  Future<void> sendMessage(String chatId, String text, {String? replyToId, String? replyToText}) async {
    final myUid = _auth.currentUser!.uid;
    final now = DateTime.now();
    final myName = await getUserName(myUid);

    final messageDoc = _firestore.collection('chats').doc(chatId).collection('messages').doc();

    final localMsg = LocalMessage(
      messageId: messageDoc.id,
      chatId: chatId,
      senderId: myUid,
      senderName: myName,
      text: text,
      timestamp: now,
      status: 1,
      replyToMessageId: replyToId,
      replyToMessageText: replyToText,
      isDeleted: false,
    );
    
    await _messageBox.put(messageDoc.id, localMsg);
    
    final chat = _chatBox.get(chatId);
    if (chat != null) {
      chat.lastMessage = text;
      chat.lastUpdate = now;
      await chat.save();
    }

    await messageDoc.set({
      'senderId': myUid,
      'senderName': myName,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 1, 
      'expireAt': Timestamp.fromDate(now.add(const Duration(hours: 48))),
      'replyToMessageId': replyToId,
      'replyToMessageText': replyToText,
      'isDeleted': false,
    });

    // تحديث مستند المحادثة لتنبيه المستمع الشامل في الشاشة الرئيسية بوجود رسالة
    await _firestore.collection('chats').doc(chatId).set({
      'lastMessageTime': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastSenderId': myUid,
    }, SetOptions(merge: true));
  }

  Future<void> deleteMessageForEveryone(String chatId, String messageId) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'isDeleted': true, 'text': '🚫 تم حذف هذه الرسالة'});
    
    final localMsg = _messageBox.get(messageId);
    if (localMsg != null) {
      localMsg.isDeleted = true;
      localMsg.text = '🚫 تم حذف هذه الرسالة';
      await localMsg.save();
    }

    final chat = _chatBox.get(chatId);
    if (chat != null && chat.lastMessage != '🚫 تم حذف هذه الرسالة') {
      chat.lastMessage = '🚫 تم حذف هذه الرسالة';
      await chat.save();
    }
  }

  Future<void> markMessagesAsRead(String chatId) async {
    final myUid = _auth.currentUser!.uid;
    final snapshot = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: myUid)
        .where('status', isLessThan: 3)
        .get();

    for (var doc in snapshot.docs) {
      await doc.reference.update({'status': 3});
    }
    
    await resetUnreadCount(chatId);
  }

  Future<void> deleteOrLeaveChat(String chatId, [String? type]) async {
    final myUid = _auth.currentUser!.uid;
    
    String actualType = type ?? 'individual';
    if (actualType == 'individual') {
      final chat = _chatBox.get(chatId);
      if (chat != null) actualType = chat.type;
    }

    await _chatBox.delete(chatId);
    
    final keysToDelete = _messageBox.keys.where((key) => _messageBox.get(key)?.chatId == chatId).toList();
    await _messageBox.deleteAll(keysToDelete);

    try {
      if (actualType == 'group') {
        await _firestore.collection('chats').doc(chatId).update({
          'participants': FieldValue.arrayRemove([myUid])
        });
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<Map<String, dynamic>?> getGroupInfo(String chatId) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    if (doc.exists) return doc.data();
    return null;
  }
}
