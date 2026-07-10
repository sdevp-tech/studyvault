// litert_service.dart
import 'dart:async';
import 'package:flutter/services.dart';

class LiteRtService {
  static const MethodChannel _platform = MethodChannel('com.example.study_vault/litert');
  static const EventChannel _eventChannel = EventChannel('com.example.study_vault/litert_stream');

  // ✅ تعديل الدالة لتقبل مسار الصورة الاختياري وتمريره عبر المنصة
  Stream<String> generate(String prompt, {String? imagePath}) {
    return _eventChannel
        .receiveBroadcastStream({
          'prompt': prompt,
          'imagePath': imagePath, // ✅ إرسال المسار إلى Kotlin
        })
        .map((event) => event.toString());
  }

  // ✅ تعديل نوع الإرجاع ليكون String? لجلب رسالة الخطأ
  Future<String?> initialize(
    String modelPath, {
    String backend = 'cpu',
    String systemPrompt = '',
    // The new API handles sampling parameters via ConversationConfig.
    // We pass them through if needed, but the plugin currently uses defaults.
    int maxTokens = 256,
    double temperature = 0.6,
    int topK = 30,
    bool supportVision = false, // ✅ المتغير الجديد لدعم الصور
  }) async {
    try {
      await _platform.invokeMethod('initialize', {
        'modelPath': modelPath,
        'backend': backend,
        'systemPrompt': systemPrompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topK': topK,
        'supportVision': supportVision, // ✅ تمريره للطبقة الأصلية
      });
      return null; // نجاح (لا يوجد خطأ)
    } on PlatformException catch (e) {
      print("❌ Error initializing model (PlatformException): ${e.message}");
      return e.message ?? "حدث خطأ غير معروف في نظام التشغيل أثناء تهيئة المحرك.";
    } catch (e) {
      print("❌ Error initializing model: $e");
      return e.toString();
    }
  }

  Future<void> stop() async {
    try {
      await _platform.invokeMethod('stop');
    } catch (e) {
      print("❌ Error stopping model: $e");
    }
  }

  Future<void> close() async {
    try {
      await _platform.invokeMethod('close');
    } catch (e) {
      print("❌ Error closing service: $e");
    }
  }
}