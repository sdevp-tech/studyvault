// ============================================================
// FILE: lib/ui/screens/main_screen.dart
// ============================================================
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/storage_service.dart';
import '../../models/settings_model.dart';
import '../../models/notification_item.dart';
import '../../globals.dart';
import '../../services/sync_service.dart';
import '../l10n/app_localizations.dart';

import '../home_content.dart';
import './assignments_screen.dart';
import './todo_screen.dart';

import './ai_chat_screen.dart';   // ⬅️ أضف هذا السطر
//import './copilot_screen.dart';
import './field_screen.dart';
import './onboarding_screen.dart';
import '../notifications_screen.dart';

import '../screens/annotation_screen.dart';
import '../screens/spaced_repetition_screen.dart';
import '../screens/chats_box.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  final StorageService _storage = StorageService();
  AppSettings? _settings;

  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomeContent(),
    const ChatListScreen(),
    const AiChatScreen(),
    const AssignmentsScreen(),
    const TodoScreen(),
    const SpacedRepetitionScreen(),
    const AnnotationScreen(),
    const SizedBox.shrink(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _checkFirstTime();
    _requestNotificationPermission();
    _requestExactAlarmPermissionWithCheck();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _storage.clearTemporaryCache();
    });

    _checkExpiryAndNotify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkExpiryAndNotify();
      SyncService().syncAll();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkExpiryAndNotify() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryStr = prefs.getString('expiry_date');
    if (expiryStr == null) return;

    try {
      final expiryDate = DateTime.parse(expiryStr);
      final now = DateTime.now();

      if (expiryDate.isBefore(now)) {
        activationNotifier.value = false;
        return;
      }

      final daysLeft = expiryDate.difference(now).inDays;
      if (daysLeft <= 7) {
        final local = AppLocalizations.of(context);
        String message = daysLeft == 0
            ? local.translate('expiry_today')
            : local.translate('expiry_days_left').replaceFirst('{days}', daysLeft.toString());

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('خطأ في قراءة تاريخ الانتهاء: $e');
    }
  }

  void _requestNotificationPermission() {
    FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> _requestExactAlarmPermissionWithCheck() async {
    if (!Platform.isAndroid) return;
    final plugin = FlutterLocalNotificationsPlugin();
    final androidImpl = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final bool? granted = await androidImpl?.requestExactAlarmsPermission();
    if (granted != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showExactAlarmPermissionDialog());
    }
  }

  void _showExactAlarmPermissionDialog() {
    final local = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('exact_alarm_permission_title')),
        content: Text(local.translate('exact_alarm_permission_message')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(local.translate('later'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context), child: Text(local.translate('got_it'))),
        ],
      ),
    );
  }

  Future<void> _loadSettings() async {
    final settingsBox = Hive.box<AppSettings>('settings_box');
    if (settingsBox.isNotEmpty) {
      setState(() => _settings = settingsBox.getAt(0));
    }
  }

  Future<void> _checkFirstTime() async {
    final settingsBox = Hive.box<AppSettings>('settings_box');
    if (settingsBox.isEmpty || (settingsBox.getAt(0)?.isFirstTime ?? true)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()),
        );
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 7) {
      _showFieldsDialog();
      return;
    }
    setState(() => _currentIndex = index);
  }

  String _getAppBarTitle(int index) {
    final local = AppLocalizations.of(context);
    switch (index) {
      case 0:
        return 'StudyVault';
      case 1:
        return local.translate('chats');
      case 2:
        return local.translate('choose_ai_mode');
      case 3:
  return (_settings != null && _settings!.assignmentsTitle.isNotEmpty && _settings!.assignmentsTitle != 'التكاليف')
      ? _settings!.assignmentsTitle 
      : local.translate('assignments');

case 4:
  return (_settings != null && _settings!.todoTitle.isNotEmpty && _settings!.todoTitle != 'قائمة المهام')
      ? _settings!.todoTitle 
      : local.translate('todo');
      case 5:
        return local.translate('spaced_repetition');
      case 6:
        return local.translate('annotations');
      case 7:
  return (_settings != null && _settings!.fieldsTitle.isNotEmpty && _settings!.fieldsTitle != 'التخصصات')
      ? _settings!.fieldsTitle 
      : local.translate('fields');
      default:
        return 'StudyVault';
    }
  }

  Future<void> _showFieldsDialog() async {
    final local = AppLocalizations.of(context);
    final fields = await _storage.listFields();
    if (fields.isEmpty) {
      await _showAddFieldDialog();
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _settings?.fieldsTitle ?? local.translate('fields'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle),
                      onPressed: _showAddFieldDialog,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: fields.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(fields[i]),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FieldScreen(field: fields[i])),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddFieldDialog() async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
  local.translate('add_field').replaceFirst(
    '{name}', 
    (_settings != null && _settings!.fieldsTitle.isNotEmpty && _settings!.fieldsTitle != 'التخصصات')
        ? _settings!.fieldsTitle 
        : local.translate('fields'),
  ),
),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: local.translate('field_name_hint'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await _storage.createSubjectFolder(
                  controller.text.trim(),
                  local.translate('default_year'),
                  local.translate('default_subject'),
                );
                Navigator.pop(context);
                await _loadSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(local.translate('field_added').replaceFirst('{name}', controller.text.trim()))),
                  );
                  _checkExpiryAndNotify();
                }
              }
            },
            child: Text(local.translate('add')),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions() {
    final local = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              local.translate('more_options'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Divider(),
            Wrap(
              spacing: 20,
              runSpacing: 20,
              alignment: WrapAlignment.center,
              children: [
                _buildMoreMenuItem(3, Icons.assignment, _settings?.assignmentsTitle ?? local.translate('assignments')),
                _buildMoreMenuItem(4, Icons.checklist, _settings?.todoTitle ?? local.translate('todo')),
                _buildMoreMenuItem(5, Icons.repeat, local.translate('spaced_repetition')),
                _buildMoreMenuItem(6, Icons.note_alt, local.translate('annotations')),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenuItem(int index, IconData icon, String label) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        setState(() => _currentIndex = index);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            child: Icon(icon, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildNavBarItem(int index, IconData icon, String label) {
    final bool isSelected = _currentIndex == index;
    final Color color = isSelected ? Theme.of(context).primaryColor : Colors.grey;
    return InkWell(
      onTap: () => _onItemTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomAppBar() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        bottom: BorderSide(
          color: Theme.of(context).dividerColor.withAlpha(51),
        ),
      ),
    ),
    child: Row(
      children: [
        if (_currentIndex != 0)
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _currentIndex = 0),
          ),
        Expanded(
          child: Text(
            _getAppBarTitle(_currentIndex),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: _currentIndex == 0 ? TextAlign.start : TextAlign.center,
          ),
        ),
        ValueListenableBuilder<Box<NotificationItem>>(
          valueListenable: Hive.box<NotificationItem>('notifications_box').listenable(),
          builder: (context, box, child) {
            final unreadCount = box.values.where((item) => !item.isRead).length;
            return Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                    );
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        unreadCount > 99 ? '+99' : '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: PopScope(
        canPop: _currentIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _currentIndex != 0) {
            setState(() => _currentIndex = 0);
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              _buildCustomAppBar(),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: _pages,
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavBarItem(0, Icons.home, local.translate('home')),
                    _buildNavBarItem(1, Icons.chat, local.translate('chats')),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up, size: 30, color: Colors.blue),
                onPressed: _showMoreOptions,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavBarItem(2, Icons.smart_toy, local.translate('copilot')),
                    _buildNavBarItem(
  7, 
  Icons.category, 
  (_settings != null && _settings!.fieldsTitle.isNotEmpty && _settings!.fieldsTitle != 'التخصصات')
      ? _settings!.fieldsTitle 
      : local.translate('fields')
),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}