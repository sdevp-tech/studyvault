import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/settings_model.dart';
import '../../viewmodels/chat_viewmodel.dart';
import '../screens/chat_screen.dart';
import 'app_theme.dart';

void main() async {
  // التأكد من تهيئة بيئة فلاتر قبل تشغيل التطبيق
  WidgetsFlutterBinding.ensureInitialized();
  
  // يجب التأكد من تهيئة Hive وفتح الصندوق 'settings_box' قبل هذه النقطة في ملف التهيئة الرئيسي
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => ChatViewModel(),
      // ✅ الاستماع المتواصل لتغييرات الإعدادات من Hive لتطبيق الثيم فوراً
      child: ValueListenableBuilder<Box<AppSettings>>(
        valueListenable: Hive.box<AppSettings>('settings_box').listenable(),
        builder: (context, box, child) {
          // استخراج حالة الثيم المحفوظة، مع وضع افتراضي للوضع النهاري إذا لم تكن موجودة
          final settings = box.isNotEmpty ? box.getAt(0) : null;
          final isDarkMode = settings?.isDarkMode ?? false;

          return MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            // ✅ ربط حالة الثيم باختيار المستخدم من شاشة الإعدادات
            themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const ChatScreen(),
          );
        },
      ),
    ),
  );
}