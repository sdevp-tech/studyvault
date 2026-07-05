// ============================================================
// FILE: lib/ui/screens/update_wrapper.dart
// ============================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateWrapper extends StatefulWidget {
  final Widget child; // الواجهة التي سيتم عرضها إذا لم يكن هناك تحديث
  
  const UpdateWrapper({super.key, required this.child});

  @override
  State<UpdateWrapper> createState() => _UpdateWrapperState();
}

class _UpdateWrapperState extends State<UpdateWrapper> {
  bool _isLoading = true;
  bool _needsUpdate = false;
  String _updateUrl = '';

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    try {
      // جلب إصدار التطبيق المثبت حالياً
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // جلب بيانات الإصدار الأخير من فايربيز
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('global_info')
          .get(const GetOptions(source: Source.serverAndCache));

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final latestVersion = data['latestVersion']?.toString() ?? currentVersion;
        final updateUrl = data['updateUrl']?.toString() ?? '';

        // مقارنة الإصدارات
        if (_isVersionGreater(latestVersion, currentVersion)) {
          setState(() {
            _needsUpdate = true;
            _updateUrl = updateUrl;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في التحقق من التحديث: $e');
    }

    // في حال عدم وجود تحديث أو حدوث خطأ (مثل عدم وجود إنترنت)، نسمح بالدخول
    setState(() {
      _isLoading = false;
    });
  }

  // دالة لمقارنة أرقام الإصدارات (مثل 1.0.2 مع 1.0.1)
  bool _isVersionGreater(String serverVersion, String localVersion) {
    List<String> serverV = serverVersion.split('.');
    List<String> localV = localVersion.split('.');

    for (int i = 0; i < serverV.length; i++) {
      int serverPart = int.tryParse(serverV[i]) ?? 0;
      int localPart = i < localV.length ? (int.tryParse(localV[i]) ?? 0) : 0;
      
      if (serverPart > localPart) return true;
      if (serverPart < localPart) return false;
    }
    return false;
  }

  Future<void> _launchUpdateUrl() async {
    if (_updateUrl.isNotEmpty) {
      final Uri url = Uri.parse(_updateUrl);
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('⚠️ تعذر فتح رابط التحديث: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // إذا كان هناك تحديث، نعرض شاشة الإجبار ولا نعرض الـ child نهائياً
    if (_needsUpdate) {
      return PopScope(
        canPop: false, // لمنع المستخدم من التخطي عبر زر الرجوع في النظام
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.system_update_rounded,
                    size: 100,
                    color: Colors.blueAccent,
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'تحديث جديد متاح!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لضمان أفضل تجربة وللاستفادة من أحدث الميزات والإصلاحات، يرجى تحديث StudyVault إلى الإصدار الأخير للمتابعة.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _launchUpdateUrl,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        'تحديث الآن',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // إذا تساوى الإصدار (أو كان التطبيق أحدث من السيرفر)، نعرض واجهة التطبيق الأصلية
    return widget.child;
  }
}