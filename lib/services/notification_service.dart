// ============================================================
// FILE: lib/services/notification_service.dart
// ============================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:convert';
import '../models/notification_item.dart';
import '../ui/notifications_screen.dart';
import '../main.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final Set<int> _scheduledIds = {}; // لمنع الجدولة المزدوجة

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZoneInfo.toString();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print('✅ المنطقة الزمنية: $timeZoneName');
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final InitializationSettings settings = InitializationSettings(android: androidSettings, iOS: iosSettings);

    // 1. معالجة النقر والتطبيق في الواجهة أو الخلفية
    await _notificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleNotificationClick,
    );

    // 2. معالجة النقر والتطبيق مغلق تماماً (Terminated Cold Start)
    final NotificationAppLaunchDetails? launchDetails = await _notificationsPlugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      if (launchDetails.notificationResponse != null) {
        // نستخدم Future.delayed لضمان فتح صناديق Hive قبل محاولة الحفظ
        Future.delayed(const Duration(milliseconds: 500), () {
           _handleNotificationClick(launchDetails.notificationResponse!);
        });
      }
    }

    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'study_vault_channel_v2', 'قناة StudyVault',
        description: 'إشعارات التذكير بالتكاليف والمهام والمراجعة',
        importance: Importance.max, playSound: true, enableVibration: true, showBadge: true,
      );
      await _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
    }

    final messaging = FirebaseMessaging.instance;
    NotificationSettings fcmSettings = await messaging.requestPermission(alert: true, badge: true, sound: true);

    if (fcmSettings.authorizationStatus == AuthorizationStatus.authorized) {
      await messaging.subscribeToTopic('all_users');
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.notification != null) {
          showNotificationFromBackground(id: message.hashCode, title: message.notification!.title ?? '', body: message.notification!.body ?? '');
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen(_handleIncomingFcmClick);
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
      if (initialMessage != null) _handleIncomingFcmClick(initialMessage);
    }

    _isInitialized = true;
  }

  // دالة منفصلة وآمنة لمعالجة النقرات وفك تشفير الـ Payload
  void _handleNotificationClick(NotificationResponse response) async {
    if (response.payload != null) {
      String title = 'تذكير';
      String body = '';
      try {
        // محاولة فك التشفير بصيغة JSON الآمنة
        final data = jsonDecode(response.payload!);
        title = data['title'] ?? 'تذكير';
        body = data['body'] ?? '';
        await _saveNotificationLocally(title, body);
      } catch (e) {
        // دعم توافقي (Fallback) في حال كان هناك إشعارات قديمة مجدولة بالنظام القديم
        final parts = response.payload!.split('|');
        if (parts.length >= 2) {
          title = parts[0];
          body = parts.sublist(1).join('|');
        } else {
          body = response.payload!;
        }
        await _saveNotificationLocally(title, body);
      }
      // تمرير العنوان والمحتوى لدالة الانتقال
      _navigateToNotificationsScreen(title, body);
    }
  }

  // دالة موحدة للتعامل مع نقرات إشعارات Firebase القادمة من الخلفية أو الإغلاق التام
  void _handleIncomingFcmClick(RemoteMessage message) async {
    if (message.notification != null) {
      final title = message.notification!.title ?? 'إشعار جديد';
      final body = message.notification!.body ?? '';
      await _saveNotificationLocally(title, body);
      // تمرير العنوان والمحتوى لدالة الانتقال
      _navigateToNotificationsScreen(title, body);
    }
  }

  // دالة التنقل الآمن القائمة على حالة إطار الواجهة (Post Frame Callback)
  void _navigateToNotificationsScreen(String title, String body) {
    // تحديد رقم التبويب بناءً على محتوى الإشعار
    final lowerTitle = title.toLowerCase();
    final lowerBody = body.toLowerCase();
    
    final isSpecialized = lowerTitle.contains('علمي') || lowerTitle.contains('تخصص') || 
                          lowerBody.contains('علمي') || lowerBody.contains('تخصص');
                          
    final tabIndex = isSpecialized ? 1 : 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (_) => NotificationsScreen(initialTabIndex: tabIndex),
          ),
        );
      } else {
        // محاولة بديلة متأخرة في حال كان التطبيق يمر بمرحلة التشغيل البارد (Terminated Cold Launch)
        Future.delayed(const Duration(milliseconds: 600), () {
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => NotificationsScreen(initialTabIndex: tabIndex),
            ),
          );
        });
      }
    });
  }

  // === دالة مساعدة لحفظ الإشعارات محلياً ===
  Future<void> _saveNotificationLocally(String title, String body) async {
    try {
      if (Hive.isBoxOpen('notifications_box')) {
        final box = Hive.box<NotificationItem>('notifications_box');
        final item = NotificationItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          body: body,
          timestamp: DateTime.now(),
          isRead: false,
        );
        await box.put(item.id, item);
      }
    } catch (e) {
      print('❌ خطأ في حفظ الإشعار محلياً: $e');
    }
  }

  // دالة مساعدة لعرض إشعار فوري وحفظه في القائمة (مرة واحدة)
  Future<void> _showImmediateNotification(int id, String title, String body) async {
    await _saveNotificationLocally(title, body);
    await _notificationsPlugin.show(
      id.abs(),
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'study_vault_channel_v2',
          'قناة StudyVault',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
      ),
    );
  }

  Future<void> showNotificationFromBackground({
    required int id,
    required String title,
    required String body,
  }) async {
    // حفظ الإشعار في الواجهة
    await _saveNotificationLocally(title, body);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'study_vault_channel_v2',
          'قناة StudyVault',
          channelDescription: 'إشعارات التذكير بالواجبات والمهام',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          playSound: true,
          enableVibration: true,
          autoCancel: true,
          icon: '@mipmap/ic_launcher',
          visibility: NotificationVisibility.public,
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  Future<void> saveUserToken(String userId) async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(userId).set({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('⚠️ فشل حفظ التوكن: $e');
    }
  }

  Future<void> subscribeToUserTopics({
    String? countryCode,
    String? institutionId,
    String? majorId,
    String? levelId,
    required String userId,
  }) async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      // 1. الاشتراك في الإشعارات العامة دائماً
      await messaging.subscribeToTopic('all_users');
      print('✅ تم الاشتراك في: all_users');

      // 2. الاشتراك في القنوات المخصصة بناءً على المؤسسة
      if (institutionId != null && institutionId.isNotEmpty) {
        // أ. الاشتراك في التخصص داخل هذه المؤسسة
        if (majorId != null && majorId.isNotEmpty) {
          String majorTopic = 'inst_${institutionId}_major_${majorId}';
          await messaging.subscribeToTopic(majorTopic);
          print('✅ تم الاشتراك في: $majorTopic');
        }

        // ب. الاشتراك في المستوى داخل هذه المؤسسة
        if (levelId != null && levelId.isNotEmpty) {
          String levelTopic = 'inst_${institutionId}_level_${levelId}';
          await messaging.subscribeToTopic(levelTopic);
          print('✅ تم الاشتراك في: $levelTopic');
        }
      }

      // 3. الاشتراك الخاص بالمستخدم الفردي (عبر الـ UID)
      await messaging.subscribeToTopic('user_$userId');
      print('✅ تم الاشتراك في: user_$userId');

    } catch (e) {
      print('❌ خطأ أثناء الاشتراك في المواضيع: $e');
    }
  }

  // الدالة الأساسية للجدولة بعد التعديل (بدون حفظ محلي أثناء الجدولة)
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
  }) async {
    print('🕒 [NotificationService] بدء محاولة جدولة إشعار:');
    print('   - id: $id');
    print('   - title: $title');
    print('   - scheduledTime: $scheduledTime');
    print('   - الوقت الحالي: ${DateTime.now()}');
    print('   - الفرق بالثواني: ${scheduledTime.difference(DateTime.now()).inSeconds}');

    // 1. إلغاء أي إشعار سابق بنفس المعرف (لتجنب التكرار)
    await cancelNotification(id);

    final now = DateTime.now();
    final difference = scheduledTime.difference(now);

    // 2. إذا كان الوقت في الماضي أو أقل من 30 ثانية -> عرض فوري (مرة واحدة فقط)
    if (scheduledTime.isBefore(now) || difference.inSeconds < 30) {
      print('⚠️ [NotificationService] الوقت قريب جداً أو مضى، سيتم عرض الإشعار فوراً');
      await _showImmediateNotification(id, title, body);
      return;
    }

    // 3. جدولة عادية للمستقبل (لن يظهر الإشعار إلا في الوقت المحدد)
    try {
      final tz.TZDateTime tzScheduledTime = tz.TZDateTime.from(scheduledTime, tz.local);
      print('   - tzScheduledTime: $tzScheduledTime');
      print('   - المنطقة الزمنية: ${tz.local}');

      // تمرير البيانات في payload لتتمكن من حفظها عند النقر
      final payloadData = {
      'title': title,
      'body': body,
    };
    final payload = jsonEncode(payloadData);

      await _notificationsPlugin.zonedSchedule(
        id.abs(),
        title,
        body,
        tzScheduledTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'study_vault_channel_v2',
            'قناة StudyVault',
            channelDescription: 'إشعارات التذكير بالواجبات والمهام',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            visibility: NotificationVisibility.public,
            showWhen: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload, // إضافة الـ payload
      );

      _scheduledIds.add(id);
      print('✅ [NotificationService] تمت الجدولة بنجاح عبر zonedSchedule (لن يظهر الإشعار إلا في الوقت المحدد)');
      
      // ❌ تم حذف سطر الحفظ المحلي من هنا لمنع ظهور الإشعار فوراً عند الحفظ
      // await _saveNotificationLocally("تذكير مجدول: $title", body);

    } catch (e) {
      print('❌ [NotificationService] فشل zonedSchedule: $e');
      rethrow;
    }
  }

  Future<void> showTestNotification() async {
    final title = '🧪 اختبار فوري';
    final body = 'الإشعارات تعمل بكفاءة!';
    
    await _saveNotificationLocally(title, body);

    await _notificationsPlugin.show(
      888888,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'study_vault_channel_v2',
          'قناة StudyVault',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> cancelNotification(int id) async {
    _scheduledIds.remove(id);
    await _notificationsPlugin.cancel(id.abs());
  }

  Future<void> cancelAll() async {
    _scheduledIds.clear();
    await _notificationsPlugin.cancelAll();
  }
}