// ===========================================================
// FILE: main.dart (الإصدار النهائي مع دعم التحديث اللحظي للغة والأسماء المخصصة)
// ===========================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';

import 'firebase_options.dart';
import 'models/asset_model.dart';
import 'models/settings_model.dart';
import 'models/assignment_model.dart';
import 'models/todo_model.dart';
import 'models/notification_item.dart';
import 'models/llm_settings.dart';
import 'services/spaced_repetition_service.dart';
import 'services/annotation_service.dart';
import 'services/notification_service.dart';
import 'services/secure_storage_helper.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/activation_screen.dart';
import 'ui/theme/app_theme.dart';
import 'globals.dart';

import './ui/local_chat.dart';
import './ui/local_message.dart';
import 'services/sync_service.dart';
import 'services/chat_service.dart';
import 'services/connectivity_service.dart';
import 'services/path_resolver.dart';
import './ui/widgets/connectivity_banner.dart';
import './ui/l10n/app_localizations.dart';
import 'ui/screens/update_wrapper.dart'; 
import 'viewmodels/chat_viewmodel.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('❌ Firebase Background Error: $e');
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Hive.initFlutter();
    _registerHiveAdapters();
    await _openHiveBoxes();

    // تهيئة محوّل المسارات قبل أي قراءة لمسارات الأصول، ثم ترحيل المسارات القديمة.
    final appDocDir = await getApplicationDocumentsDirectory();
    PathResolver.init(appDocDir.path);
    await _migrateAssetPaths();

    await _initializeDefaultSettings();
    await initializeDateFormatting('ar_SA', null);
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // مراقبة حالة الاتصال وإعادة إرسال الرسائل المعلّقة عند عودة الإنترنت.
    await ConnectivityService().init();
    ConnectivityService().onReconnected(_onNetworkRestored);

    final isActivated = await _loadInitialActivationState();
    final kickReason = isActivated ? null : await SecureStorageHelper.getKickReason();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatViewModel()),
        ],
        child: MyApp(initialKickReason: kickReason),
      ),
    );

    _startBackgroundSyncTasks();
  } catch (e, stackTrace) {
    debugPrint('‼️ FATAL initialization error: $e');
    debugPrint(stackTrace.toString());
    runApp(ErrorApp(errorMessage: e.toString()));
  }
}

Future<bool> _loadInitialActivationState() async {
  bool isActivated = await SecureStorageHelper.isUserActivated();
  String? expiryStr = await SecureStorageHelper.getExpiryDate();
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    isActivated = false;
  } else if (isActivated && expiryStr != null) {
    try {
      DateTime expiryDate = DateTime.parse(expiryStr);
      if (expiryDate.isBefore(DateTime.now())) {
        isActivated = false;
        await SecureStorageHelper.suspendActivation('انتهت صلاحية الحساب');
      }
    } catch (e) {
      isActivated = false;
    }
  }
  activationNotifier.value = isActivated;
  return isActivated;
}

void _startBackgroundSyncTasks() {
  Future.sync(() async {
    try {
      await _requestRequiredPermissions();
      await NotificationService().init();
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        try {
          await SyncService().syncAll();
          debugPrint('✅ Chat Sync: تم تحديث الرسائل بنجاح');
        } catch (e) {
          debugPrint('⚠️ Chat Sync Error: فشل تحديث الرسائل: $e');
        }

        var userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3), onTimeout: () {
          return FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(const GetOptions(source: Source.server));
        });

        if (userDoc.exists) {
          final data = userDoc.data()!;
          await NotificationService().subscribeToUserTopics(
            countryCode: data['countryCode'],
            institutionId: data['institutionId'],
            majorId: data['majorId'],
            levelId: data['levelId'],
            userId: user.uid,
          );
        } else {
          await FirebaseMessaging.instance.subscribeToTopic('user_${user.uid}');
        }
      }

      await _syncWithFirestore();
    } catch (e) {
      debugPrint('⚠️ فشل تشغيل مهام الخلفية الشاملة: $e');
    }
  });
}

Future<void> _requestRequiredPermissions() async {
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
  if (await Permission.scheduleExactAlarm.isDenied) {
    await Permission.scheduleExactAlarm.request();
  }
}

Future<void> _handleKickOut(String reason) async {
  await SecureStorageHelper.killActivation(reason);
  await FirebaseAuth.instance.signOut();

  try {
    await Hive.box<LocalChat>('chats_box').clear();
    await Hive.box<LocalMessage>('messages_box').clear();
    await Hive.box<NotificationItem>('notifications_box').clear();
    await Hive.box<AppSettings>('settings_box').clear();
    print('✅ تم مسح بيانات المستخدم المحلية');
  } catch (e) {
    debugPrint('⚠️ تعذر مسح بعض البيانات المحلية: $e');
  }

  activationNotifier.value = false;

  Future.delayed(const Duration(milliseconds: 500), () {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("تنبيه أمني", style: TextStyle(color: Colors.red)),
          content: Text(reason),
          actions: [
            ElevatedButton(
              onPressed: () {
                SecureStorageHelper.clearKickReason();
                Navigator.pop(context);
              },
              child: const Text("حسناً"),
            )
          ],
        ),
      );
    }
  });
}

Future<void> _syncWithFirestore() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  try {
    var userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 10));

    bool isServerValid = false;
    String? expiryDateStr;
    String? remoteSessionId;

    if (userDoc.exists && userDoc.data() != null) {
      final data = userDoc.data()!;
      bool isActivatedInServer = data['isActivated'] ?? false;
      Timestamp? expiryTimestamp = data['expiryDate'];
      remoteSessionId = data['currentSessionId'] as String?;

      print('🔍 _syncWithFirestore: isActivated=$isActivatedInServer, expiry=$expiryTimestamp, remoteSessionId=$remoteSessionId');

      if (isActivatedInServer && expiryTimestamp != null) {
        DateTime expiryDate = expiryTimestamp.toDate();
        if (expiryDate.isAfter(DateTime.now())) {
          isServerValid = true;
          expiryDateStr = expiryDate.toIso8601String();
        } else {
          print('⚠️ انتهت الصلاحية في السيرفر: $expiryDate');
        }
      } else {
        print('⚠️ المستخدم غير مفعل في السيرفر');
      }
    } else {
      print('⚠️ وثيقة المستخدم غير موجودة في السيرفر');
    }

    final localSessionId = await SecureStorageHelper.getSessionId();
    print('🔍 localSessionId: $localSessionId');

    if (isServerValid && expiryDateStr != null) {
      if (localSessionId == null) {
        if (remoteSessionId != null) {
          print('❌ جهاز جديد يحاول الدخول دون جلسة محلية – طرده');
          await _handleKickOut('حسابك مفعل مسبقاً على جهاز آخر. يرجى إعادة تسجيل الدخول والتفعيل.');
          return;
        } else {
          final newSessionId = const Uuid().v4();
          print('🆕 إنشاء جلسة جديدة: $newSessionId وتحديث السيرفر');
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'currentSessionId': newSessionId,
          }, SetOptions(merge: true));
          await SecureStorageHelper.saveActivation(
            sessionId: newSessionId,
            expiryDate: expiryDateStr,
          );
          activationNotifier.value = true;
          return;
        }
      } else {
        if (remoteSessionId != null && remoteSessionId != localSessionId) {
          print('❌ عدم تطابق الجلسة: remote=$remoteSessionId, local=$localSessionId');
          await _handleKickOut('تم تسجيل الخروج. تم فتح حسابك من جهاز آخر.');
          return;
        } else if (remoteSessionId == null) {
          print('⚠️ remoteSessionId غير موجود، سنقوم بتحديث الجلسة المحلية على السيرفر');
          final newSessionId = localSessionId; 
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'currentSessionId': newSessionId,
          }, SetOptions(merge: true));
          await SecureStorageHelper.saveActivation(
            sessionId: newSessionId,
            expiryDate: expiryDateStr,
          );
          activationNotifier.value = true;
          return;
        } else {
          print('✅ الجلسة متطابقة، تحديث التاريخ وإعادة التفعيل');
          await SecureStorageHelper.saveActivation(
            sessionId: localSessionId,
            expiryDate: expiryDateStr,
          );
          activationNotifier.value = true;
          return;
        }
      }
    } else {
      print('❌ الحساب غير مفعل أو منتهي الصلاحية، نجمده');
      await SecureStorageHelper.suspendActivation('انتهت صلاحية الحساب من الإدارة');
      activationNotifier.value = false;
      return;
    }
  } catch (e) {
    debugPrint('ℹ️ تعذر المزامنة (أوفلاين): $e');
  }
}

/// ترحيل مسارات الأصول القديمة (المطلقة) إلى مسارات نسبية مستقرة.
/// هذه العملية idempotent — آمنة للتشغيل في كل إقلاع.
Future<void> _migrateAssetPaths() async {
  try {
    final box = Hive.box<AssetModel>('assets_box');
    for (final asset in box.values) {
      final newFilePath = PathResolver.toStorable(asset.filePath);
      final newThumb = asset.thumbnailPath == null
          ? null
          : PathResolver.toStorable(asset.thumbnailPath!);

      bool changed = false;
      if (newFilePath != asset.filePath) {
        asset.filePath = newFilePath;
        changed = true;
      }
      if (newThumb != asset.thumbnailPath) {
        asset.thumbnailPath = newThumb;
        changed = true;
      }
      if (changed) await asset.save();
    }
    debugPrint('✅ تم ترحيل مسارات الأصول إلى الصيغة النسبية');
  } catch (e) {
    debugPrint('⚠️ تعذر ترحيل مسارات الأصول: $e');
  }
}

/// يُستدعى تلقائياً عند عودة الاتصال بالإنترنت لإعادة إرسال ما تعذّر إرساله ومزامنة المحادثات.
void _onNetworkRestored() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  Future.microtask(() async {
    try {
      await ChatService().resendPendingMessages();
      await SyncService().syncAll();
      debugPrint('✅ أُعيدت المزامنة بعد عودة الاتصال');
    } catch (e) {
      debugPrint('⚠️ فشلت المزامنة بعد عودة الاتصال: $e');
    }
  });
}

void _registerHiveAdapters() {
  Hive.registerAdapter(LocalChatAdapter());
  Hive.registerAdapter(LocalMessageAdapter());
  Hive.registerAdapter(AssetModelAdapter());
  Hive.registerAdapter(CardModelAdapter());
  Hive.registerAdapter(AnnotationAdapter());
  Hive.registerAdapter(AppSettingsAdapter());
  Hive.registerAdapter(AssignmentTypeAdapter());
  Hive.registerAdapter(AssignmentStatusAdapter());
  Hive.registerAdapter(AssignmentAdapter());
  Hive.registerAdapter(PriorityAdapter());
  Hive.registerAdapter(TodoItemAdapter());
  Hive.registerAdapter(NotificationItemAdapter());
  Hive.registerAdapter(LlmSettingsAdapter());
}

Future<void> _openHiveBoxes() async {
  await Future.wait([
    Hive.openBox<LocalChat>('chats_box'),
    Hive.openBox<LocalMessage>('messages_box'),
    Hive.openBox<AssetModel>('assets_box'),
    Hive.openBox<CardModel>('cards_box'),
    Hive.openBox<Annotation>('annotations_box'),
    Hive.openBox<AppSettings>('settings_box'),
    Hive.openBox<Assignment>('assignments_box'),
    Hive.openBox<TodoItem>('todos_box'),
    Hive.openBox<NotificationItem>('notifications_box'),
    Hive.openBox<LlmSettings>('llm_settings_box'),
  ]);
}

Future<void> _initializeDefaultSettings() async {
  final settingsBox = Hive.box<AppSettings>('settings_box');
  if (settingsBox.isEmpty) {
    final String deviceLocale = Platform.localeName;
    String defaultLanguage;
    if (deviceLocale.startsWith('en')) {
      defaultLanguage = 'English';
    } else {
      defaultLanguage = 'العربية';
    }
    await settingsBox.add(AppSettings(language: defaultLanguage));
    debugPrint('✅ تم إنشاء الإعدادات الافتراضية باللغة: $defaultLanguage');
  }
}

class MyApp extends StatelessWidget {
  final String? initialKickReason;
  const MyApp({super.key, this.initialKickReason});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: activationNotifier,
      builder: (context, isActivated, child) {
        return ValueListenableBuilder<Box<AppSettings>>(
          valueListenable: Hive.box<AppSettings>('settings_box').listenable(),
          builder: (context, box, child) {
            final settings = box.isEmpty ? AppSettings() : box.getAt(0)!;

            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'StudyVault',
              debugShowCheckedModeBanner: false,
              builder: (context, child) =>
                  ConnectivityBanner(child: child ?? const SizedBox.shrink()),
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
              
              // التعديل الجوهري هنا: إضافة ValueKey يعتمد على متغيرات الأسماء واللغة
              home: UpdateWrapper(
                child: isActivated
                    ? MainScreen(
                        key: ValueKey(
                          '${settings.language}_${settings.fieldsTitle}_${settings.lecturesTitle}_${settings.assignmentsTitle}_${settings.todoTitle}_${settings.isDarkMode}',
                        ),
                      )
                    : ActivationScreen(initialKickReason: initialKickReason),
              ),

              locale: settings.language == 'English' ? const Locale('en', 'US') : const Locale('ar', 'SA'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('ar', 'SA'),
                Locale('en', 'US'),
              ],
            );
          },
        );
      },
    );
  }
}

class ErrorApp extends StatelessWidget {
  final String? errorMessage;
  const ErrorApp({super.key, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    const isDebug = true;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'SA'),
        Locale('en', 'US'),
      ],
      locale: const Locale('ar', 'SA'),
      home: Builder(
        builder: (context) {
          final local = AppLocalizations.of(context);
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 80),
                      const SizedBox(height: 24),
                      Text(
                        local.translate('error_occurred'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        local.translate('restart_app_message'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      if (isDebug && errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            '${local.translate('error_details')}: $errorMessage',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.refresh),
                        label: Text(local.translate('retry')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}