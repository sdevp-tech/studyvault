import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_chat.dart';
import '../screens/chat_room_screen.dart';
import 'my_qr_screen.dart';
import '../../services/chat_service.dart';
import '../../services/sync_service.dart';
import '../mobile_scanner.dart';
import '../l10n/app_localizations.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  late final Stream<QuerySnapshot> _chatsStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    _chatsStream = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: myUid)
        .snapshots();
        
    SyncService().syncAll();
    ChatService().updateUserPresence(true); 
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ChatService().updateUserPresence(false); 
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService().syncAll();
      ChatService().updateUserPresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      ChatService().updateUserPresence(false);
    }
  }

  Future<void> _showRenameDialog(LocalChat chat) async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController(text: chat.title);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('rename_chat')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: local.translate('new_name')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                chat.title = newName;
                await chat.save();
                if (chat.type == 'group' && chat.adminId == FirebaseAuth.instance.currentUser?.uid) {
                  FirebaseFirestore.instance.collection('chats').doc(chat.chatId).update({'title': newName});
                }
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(local.translate('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateGroupDialog() async {
    final local = AppLocalizations.of(context);
    final box = Hive.box<LocalChat>('chats_box');
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    
    final individualChats = box.values.where((c) => c.type == 'individual').toList();
    List<String> selectedUids = [];
    final groupNameController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(local.translate('create_group')),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: groupNameController,
                      decoration: InputDecoration(
                        labelText: local.translate('group_name'), 
                        border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                  Text(local.translate('select_members')),
                    Expanded(
                      child: individualChats.isEmpty 
                    ? Center(child: Text(local.translate('no_contacts')))
                        : ListView.builder(
                        shrinkWrap: true,
                        itemCount: individualChats.length,
                        itemBuilder: (context, index) {
                          final chat = individualChats[index];
                          final otherUid = chat.participants.firstWhere((id) => id != myUid, orElse: () => '');
                          if (otherUid.isEmpty) return const SizedBox.shrink();
                          
                          final isSelected = selectedUids.contains(otherUid);
                          return CheckboxListTile(
                            title: Text(chat.title ?? 'مستخدم'),
                            value: isSelected,
                            onChanged: (bool? val) {
                              setState(() {
                                if (val == true) {
                                  selectedUids.add(otherUid);
                                } else {
                                  selectedUids.remove(otherUid);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(local.translate('cancel'))),
                ElevatedButton(
                  onPressed: () async {
                    final groupName = groupNameController.text.trim();
                    if (groupName.isEmpty) return;
                    try {
                      await ChatService().createGroupChat(groupName, selectedUids);
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      print(e);
                    }
                  },
                  child: Text(local.translate('create')),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(local.translate('chats_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add),
            tooltip: local.translate('new_group'),
            onPressed: _showCreateGroupDialog,
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QRScannerScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQRScreen())),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _chatsStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
             _updateChatsFromSnapshot(snapshot.data!);
          }
          
          return ValueListenableBuilder(
            valueListenable: Hive.box<LocalChat>('chats_box').listenable(),
            builder: (context, Box<LocalChat> box, _) {
               if (box.isEmpty) return Center(child: Text(local.translate('no_chats_yet')));

              final chats = box.values.toList()
                ..sort((a, b) {
                  if (a.isPinned && !b.isPinned) return -1;
                  if (!a.isPinned && b.isPinned) return 1;
                  return b.lastUpdate.compareTo(a.lastUpdate);
                });

              return ListView.builder(
                itemCount: chats.length,
                itemBuilder: (context, index) {
                  final chat = chats[index];
                  return ListTile(
                    leading: CircleAvatar(
                      child: chat.type == 'group' ? const Icon(Icons.group, size: 20) : Text(chat.title?[0] ?? "G"),
                    ),
                    title: Text(chat.title ?? "محادثة"),
                    subtitle: Text(chat.lastMessage, maxLines: 1, style: TextStyle(color: chat.unreadCount > 0 ? Colors.black87 : Colors.grey)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${chat.lastUpdate.hour}:${chat.lastUpdate.minute.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (chat.isPinned) const Icon(Icons.push_pin, size: 16, color: Colors.blue),
                            if (chat.isPinned && chat.unreadCount > 0) const SizedBox(width: 4),
                            if (chat.unreadCount > 0)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                child: Text('${chat.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        )
                      ],
                    ),
                    onLongPress: () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => Wrap(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.edit, color: Colors.blue),
                              title: Text(local.translate('rename_chat')),
                              onTap: () {
                                Navigator.pop(context);
                                _showRenameDialog(chat);
                              },
                            ),
                            ListTile(
                              leading: Icon(chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin),
                              title: Text(chat.isPinned ? local.translate('unpin_chat') : local.translate('pin_chat')),
                              onTap: () {
                                ChatService().togglePinChat(chat.chatId);
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete, color: Colors.red),
                              title: Text(local.translate('delete_chat'), style: const TextStyle(color: Colors.red)),
                              onTap: () {
                                ChatService().deleteOrLeaveChat(chat.chatId);
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      );
                    },
                    onTap: () async {
                      await ChatService().resetUnreadCount(chat.chatId); 
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => ChatRoomScreen(chatId: chat.chatId, title: chat.title ?? "محادثة")),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _updateChatsFromSnapshot(QuerySnapshot snapshot) async {
    final local = AppLocalizations.of(context);
    final box = Hive.box<LocalChat>('chats_box');
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final chatId = doc.id;
      
      if (!box.containsKey(chatId)) {
        String title = data['title'] ?? 'محادثة جديدة';
        if (data['type'] == 'individual') {
          final otherUid = (data['participants'] as List).firstWhere((id) => id != myUid, orElse: () => '');
          if (otherUid.isNotEmpty) {
             title = await ChatService().getUserName(otherUid);
          }
        }

        final newChat = LocalChat(
          chatId: chatId,
          type: data['type'] ?? 'individual',
          title: title,
          participants: List<String>.from(data['participants'] ?? []),
          lastMessage: data['lastMessage'] ?? local.translate('start_conversation'),
          lastUpdate: (data['lastMessageTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
          adminId: data['adminId'],
        );
        await box.put(chatId, newChat);
        SyncService().syncMessagesForChat(chatId);
      } else {
        final existing = box.get(chatId)!;
        bool changed = false;

        if (existing.participants.length != (data['participants'] as List).length) {
          existing.participants.clear();
          existing.participants.addAll(List<String>.from(data['participants'] ?? existing.participants));
          changed = true;
        }

        // التقاط التحديثات وتشغيل المزامنة الفورية
        if (data['lastMessage'] != null && data['lastMessageTime'] != null) {
          DateTime serverTime = (data['lastMessageTime'] as Timestamp).toDate();
          if (serverTime.isAfter(existing.lastUpdate)) {
            existing.lastMessage = data['lastMessage'];
            existing.lastUpdate = serverTime;
            
            // تحديث فوري لعداد الإشعارات (Optimistic Update)
            if (data['lastSenderId'] != null && data['lastSenderId'] != myUid) {
               existing.unreadCount += 1;
            }
            
            changed = true;
            
            // جلب الرسالة في الخلفية وتحديث حالتها
            SyncService().syncMessagesForChat(chatId);
          }
        }

        if (changed) {
          await existing.save();
        }
      }
    }
  }
}