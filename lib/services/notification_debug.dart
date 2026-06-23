import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class NotificationDebug {
  static final List<String> _logs = [];

  static void log(String step, [String? extra]) {
    final time = DateTime.now().toIso8601String().substring(11, 23);
    final message = '[NOTIF-DEBUG $time] $step ${extra ?? ""}';
    _logs.add(message);
    print(message);
  }

  static void error(String step, dynamic e, StackTrace? st) {
    final message = '[NOTIF-ERROR] ❌ $step → $e';
    _logs.add(message);
    print(message);
    if (st != null) print(st);
  }

  static void showReport(BuildContext context, String title) {
    if (!kDebugMode) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('📋 تقرير التنبيه: $title'),
        content: SizedBox(
          width: double.maxFinite,
          height: 450,
          child: SingleChildScrollView(
            child: Text(_logs.join('\n'), style: const TextStyle(fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              _logs.clear();
              Navigator.pop(context);
            },
            child: const Text('مسح السجل'),
          ),
        ],
      ),
    );
  }

  static void clear() => _logs.clear();
}