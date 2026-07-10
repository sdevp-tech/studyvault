// ============================================================
// FILE: lib/ui/screens/activation_screen.dart
// ============================================================

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/notification_service.dart';
import '../../services/secure_storage_helper.dart';
import '../../globals.dart';
import '../l10n/app_localizations.dart';
import '../screens/main_screen.dart';

class ActivationScreen extends StatefulWidget {
  final String? initialKickReason;

  const ActivationScreen({super.key, this.initialKickReason});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // مفتاح نموذج المصادقة لمنع الإرسال قبل اكتمال البيانات
  final GlobalKey<FormState> _authFormKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoginMode = false;
  bool _isAuthLoading = false;

  // بيانات الدراسة (الطالب العام فقط)
  String? _generalEducationType; // 'university' or 'school'
  String? selectedCountryId;
  String? selectedMajorId;
  String? selectedLevelId;

  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> _generalMajorsList = [];
  List<Map<String, dynamic>> _generalLevelsList = [];
  bool _isLoadingMajors = false;
  bool _isLoadingLevels = false;

  final TextEditingController _codeController = TextEditingController();
  bool _isActivationLoading = false;

  Map<String, String> socialLinks = {};

  StreamSubscription<DocumentSnapshot>? _userStatusSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (widget.initialKickReason != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showKickDialog(widget.initialKickReason!);
      });
    }

    if (FirebaseAuth.instance.currentUser != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkExistingUserStatus();
        _getCountriesFuture();
        _getSocialLinksFuture();
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _userStatusSubscription?.cancel();
    super.dispose();
  }

  // ==================== [دوال التنظيف والتنبيه] ====================

  void _resetStudyStep() {
    setState(() {
      selectedMajorId = null;
      selectedLevelId = null;
      _generalEducationType = null;
      _codeController.clear();
      _generalMajorsList = [];
      _generalLevelsList = [];
    });
  }

  void _cleanupStudyData() {
    _resetStudyStep();
    _showSnackBar(AppLocalizations.of(context).translate('data_reset_message'));
  }

  void _showKickDialog(String reason) {
    final local = AppLocalizations.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(local.translate('security_alert_session_expired'),
            style: const TextStyle(color: Colors.red)),
        content: Text(reason),
        actions: [
          ElevatedButton(
            onPressed: () {
              SecureStorageHelper.clearKickReason();
              Navigator.pop(context);
            },
            child: Text(local.translate('ok')),
          )
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // ==================== [دوال جلب البيانات الثابتة] ====================

  Future<List<Map<String, dynamic>>> _getCountriesFuture() async {
    if (countries.isNotEmpty) return countries;
    try {
      final snapshot = await FirebaseFirestore.instance.collection('countries').get();
      final list = snapshot.docs.map((doc) {
        return <String, dynamic>{
          'id': doc.id,
          ...(doc.data() as Map<String, dynamic>? ?? {}),
        };
      }).toList();

      Map<String, dynamic>? yemen;
      try {
        yemen = list.firstWhere(
          (c) => c['name'].toString().contains('يمن') ||
              c['name'].toString().contains('Yemen'),
        );
      } catch (e) {
        yemen = null;
      }
      if (yemen != null) {
        selectedCountryId = yemen['id'] as String?;
      } else if (list.isNotEmpty) {
        selectedCountryId = list.first['id'] as String?;
      }

      setState(() {
        countries = list;
      });
      return list;
    } catch (e) {
      debugPrint('خطأ في جلب الدول: $e');
      return [];
    }
  }

  Future<Map<String, String>> _getSocialLinksFuture() async {
    if (socialLinks.isNotEmpty) return socialLinks;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('global_info')
          .get();
      if (doc.exists && doc.data() != null) {
        final links = <String, String>{
          'whatsapp': doc.data()!['whatsappLink']?.toString() ?? '',
          'telegram': doc.data()!['TelegramLink']?.toString() ?? '',
          'facebook': doc.data()!['FacebookLink']?.toString() ?? '',
          'instagram': doc.data()!['InstgramLink']?.toString() ?? '',
        };
        setState(() => socialLinks = links);
        return links;
      }
    } catch (e) {
      debugPrint("خطأ في جلب روابط التواصل: $e");
    }
    return {};
  }

  Widget _buildCountryDropdown() {
    final local = AppLocalizations.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getCountriesFuture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('${local.translate('error_loading_countries')}: ${snapshot.error}');
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Text(local.translate('no_countries_available'));
        }
        return DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: selectedCountryId,
          decoration: InputDecoration(
              labelText: local.translate('select_your_country'),
              border: const OutlineInputBorder()),
          items: list.map((c) {
            return DropdownMenuItem<String>(
              value: c['id'] as String,
              child: Text(
                c['name'] as String,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              selectedCountryId = val;
              _generalEducationType = null;
              selectedMajorId = null;
              selectedLevelId = null;
              _generalMajorsList = [];
              _generalLevelsList = [];
            });
          },
        );
      },
    );
  }

  // ==================== [دوال للمستخدم العام] ====================

  Future<void> _fetchGeneralMajors(String type) async {
    setState(() => _isLoadingMajors = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('majors')
          .where('type', isEqualTo: type)
          .get();
      _generalMajorsList = snapshot.docs.map((doc) {
        return <String, dynamic>{
          'id': doc.id,
          ...(doc.data() as Map<String, dynamic>? ?? {}),
        };
      }).toList();
    } catch (e) {
      debugPrint("خطأ في جلب التخصصات العامة: $e");
      _generalMajorsList = [];
    } finally {
      if (mounted) setState(() => _isLoadingMajors = false);
    }
  }

  Future<void> _fetchGeneralLevels(String majorId) async {
    setState(() => _isLoadingLevels = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('levels')
          .where('majorId', isEqualTo: majorId)
          .get();
      _generalLevelsList = snapshot.docs.map((doc) {
        return <String, dynamic>{
          'id': doc.id,
          ...(doc.data() as Map<String, dynamic>? ?? {}),
        };
      }).toList();
    } catch (e) {
      debugPrint("خطأ في جلب المستويات العامة: $e");
      _generalLevelsList = [];
    } finally {
      if (mounted) setState(() => _isLoadingLevels = false);
    }
  }

  // ==================== [التحقق من حالة المستخدم القديم] ====================

  Future<void> _checkExistingUserStatus() async {
    final local = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
          
      if (doc.exists) {
        final data = doc.data()!;
        String status = data['status'] ?? 'pending';
        String? country = data['countryCode'];
        bool isActivated = data['isActivated'] ?? false;
        Timestamp? expiryTimestamp = data['expiryDate'];

        if (country == null) {
          _tabController.animateTo(1);
        } else if (status == 'approved') {
          // التحقق مما إذا كان المستخدم يمتلك تفعيلاً صالحاً (تجريبي أو مدفوع)
          if (isActivated && expiryTimestamp != null && expiryTimestamp.toDate().isAfter(DateTime.now())) {
            
            // 🔥 إنشاء جلسة جديدة كلياً لضمان طرد أي هاتف آخر
            String newSessionUuid = const Uuid().v4();
            
            // تحديث السيرفر بالجلسة الجديدة 
            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'currentSessionId': newSessionUuid,
            });

            // حفظ الجلسة محلياً في الهاتف الجديد
            await SecureStorageHelper.saveActivation(
              sessionId: newSessionUuid,
              expiryDate: expiryTimestamp.toDate().toIso8601String(),
            );
            
            activationNotifier.value = true; // سيدخله مباشرة لـ MainScreen
          } else {
            // حسابه منتهي الصلاحية أو لم يتم تفعيله قط
            _tabController.animateTo(2);
          }
        } else {
          _tabController.animateTo(1);
          _showSnackBar(local.translate('account_under_review'));
          _listenToUserApprovalStatus();
        }
      } else {
        _tabController.animateTo(1);
      }
    } catch (e) {
      debugPrint("خطأ في فحص المستخدم: $e");
    }
  }

  // ==================== [المحطة الأولى: المصادقة] ====================

  Future<void> _submitAuth() async {
    final local = AppLocalizations.of(context);
    
    if (!_authFormKey.currentState!.validate()) {
      return;
    }

    setState(() => _isAuthLoading = true);
    try {
      UserCredential userCredential;
      if (_isLoginMode) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        _getCountriesFuture();
        _getSocialLinksFuture();
        await _checkExistingUserStatus();
      } else {
        userCredential =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        if (userCredential.user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'fullName': _nameController.text.trim(),
            'email': _emailController.text.trim(),
            'status': 'pending_data',
          }, SetOptions(merge: true));
        }
        _getCountriesFuture();
        _getSocialLinksFuture();
        _resetStudyStep();
        _tabController.animateTo(1);
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(e.message ?? local.translate('auth_error'));
    } finally {
      if (mounted) setState(() => _isAuthLoading = false);
    }
  }

  // ==================== [المحطة الثانية: الدراسة والانتظار] ====================

  void _listenToUserApprovalStatus() {
    final local = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userStatusSubscription?.cancel();
    _userStatusSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        String status = snapshot.data()?['status'] ?? 'pending';
        if (status == 'approved' && _tabController.index == 1) {
          _showSnackBar(local.translate('account_approved_can_activate'));
          _tabController.animateTo(2);
        }
      }
    });
  }

  Future<void> _validateStudyStep() async {
    final local = AppLocalizations.of(context);
    if (selectedCountryId == null) {
      _showSnackBar(local.translate('country_required'));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_generalEducationType == null) {
      _showSnackBar(local.translate('education_type_required'));
      return;
    }
    if (selectedMajorId == null) {
      _showSnackBar(local.translate('major_required'));
      return;
    }
    if (selectedLevelId == null) {
      _showSnackBar(local.translate('level_required'));
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 1. جلب إعدادات الفترة التجريبية من فايربيز
      final globalDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('global_info')
          .get();
          
      int trialDays = 0;
      if (globalDoc.exists && globalDoc.data()!.containsKey('trialDays')) {
        trialDays = (globalDoc.data()!['trialDays'] as num).toInt();
      }

      // 2. تجهيز البيانات الأساسية
      Map<String, dynamic> userData = {
        'countryCode': selectedCountryId,
        'isGeneralUser': true,
        'educationType': _generalEducationType,
        'majorId': selectedMajorId,
        'levelId': selectedLevelId,
        'role': 'student',
        'status': 'approved',
      };

      // 3. التحقق مما إذا كان هناك فترة تجريبية
      if (trialDays > 0) {
        String sessionUuid = const Uuid().v4();
        String deviceId = await _getDeviceId();
        DateTime trialExpiryDate = DateTime.now().add(Duration(days: trialDays));

        // إضافة بيانات التفعيل التجريبي
        userData.addAll({
          'isActivated': true,
          'deviceId': deviceId,
          'currentSessionId': sessionUuid,
          'expiryDate': Timestamp.fromDate(trialExpiryDate),
          'isTrial': true,
        });

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));

        await SecureStorageHelper.saveActivation(
          sessionId: sessionUuid,
          expiryDate: trialExpiryDate.toIso8601String(),
        );

        final notificationService = NotificationService();
        await notificationService.saveUserToken(user.uid);
        await notificationService.subscribeToUserTopics(
          countryCode: selectedCountryId,
          institutionId: null,
          majorId: selectedMajorId,
          levelId: selectedLevelId,
          userId: user.uid,
        );

        activationNotifier.value = true;

        if (mounted) {
          Navigator.pop(context); // إغلاق شريط التحميل
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
      } else {
        // لا يوجد فترة تجريبية
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
        
        if (mounted) {
          Navigator.pop(context); // إغلاق شريط التحميل
          _tabController.animateTo(2);
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('${local.translate('error_saving_data')}: $e');
    }
  }

  // ==================== [المحطة الثالثة: التفعيل] ====================

  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? "unknown_ios_device";
    }
    return "unknown_device";
  }

  Future<void> _activateAndRegister() async {
    final local = AppLocalizations.of(context);
    if (_codeController.text.isEmpty) {
      _showSnackBar(local.translate('enter_activation_code'));
      return;
    }

    setState(() => _isActivationLoading = true);

    try {
      String sessionUuid = const Uuid().v4();
      String deviceId = await _getDeviceId();
      String code = _codeController.text.trim();
      User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) throw Exception(local.translate('user_not_logged_in'));

      final codeRef =
          FirebaseFirestore.instance.collection('activation_codes').doc(code);
      final codeDoc = await codeRef.get();

      if (codeDoc.exists && codeDoc.data()!['isUsed'] == false) {
        final codeData = codeDoc.data()!;
        if (codeData.containsKey('expiryDate')) {
          final codeExpiry = (codeData['expiryDate'] as Timestamp).toDate();
          if (codeExpiry.isBefore(DateTime.now())) {
            _showSnackBar(local.translate('activation_code_expired'));
            return;
          }
        }

        DateTime expiryDate;
        if (codeData.containsKey('expiryDate')) {
          expiryDate = (codeData['expiryDate'] as Timestamp).toDate();
        } else {
          expiryDate = DateTime.now().add(const Duration(days: 365));
        }

        await codeRef.update({
          'isUsed': true,
          'usedByUid': currentUser.uid,
          'usedByDeviceId': deviceId,
          'usedBySessionId': sessionUuid,
          'activatedAt': FieldValue.serverTimestamp(),
        });

        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .set({
          'isActivated': true,
          'deviceId': deviceId,
          'currentSessionId': sessionUuid,
          'expiryDate': Timestamp.fromDate(expiryDate),
          'isTrial': false, // إزالة علامة الفترة التجريبية في حال كان مفعلاً مدفوعاً
        }, SetOptions(merge: true));

        await SecureStorageHelper.saveActivation(
          sessionId: sessionUuid,
          expiryDate: expiryDate.toIso8601String(),
        );

        final notificationService = NotificationService();
        await notificationService.saveUserToken(currentUser.uid);
        await notificationService.subscribeToUserTopics(
          countryCode: selectedCountryId,
          institutionId: null,
          majorId: selectedMajorId,
          levelId: selectedLevelId,
          userId: currentUser.uid,
        );

        activationNotifier.value = true;

        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainScreen()),
            (route) => false,
          );
        }
      } else {
        _showSnackBar(local.translate('invalid_or_used_code'));
      }
    } catch (e) {
      debugPrint("خطأ أثناء التفعيل: $e");
      _showSnackBar('${local.translate('activation_failed')}: $e');
    } finally {
      if (mounted) setState(() => _isActivationLoading = false);
    }
  }

  void _launchURL(String? urlString) async {
    final local = AppLocalizations.of(context);
    if (urlString == null || urlString.isEmpty) {
      _showSnackBar(local.translate('link_unavailable'));
      return;
    }

    final String cleanUrl = urlString.trim();
    final Uri url = Uri.parse(cleanUrl);

    try {
      final bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint("Error launching URL: $e");
      _showSnackBar(local.translate('cannot_open_link'));
    }
  }

  // ==================== [واجهات التبويبات] ====================

  Widget _buildAuthStep() {
    final local = AppLocalizations.of(context);
    return SingleChildScrollView(
      child: Form(
        key: _authFormKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_circle, size: 80, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 20),
            Text(_isLoginMode ? local.translate('login') : local.translate('create_account'),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            
            if (!_isLoginMode) ...[
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: local.translate('full_name'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
                validator: (value) {
                  if (!_isLoginMode && (value == null || value.trim().isEmpty)) {
                    return local.translate('full_name_required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 15),
            ],
            
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: local.translate('email'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.email),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty || !value.contains('@')) {
                  return local.translate('invalid_email');
                }
                return null;
              },
            ),
            const SizedBox(height: 15),
            
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: local.translate('password'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
              ),
              validator: (value) {
                if (value == null || value.length < 6) {
                  return local.translate('password_too_short');
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isAuthLoading ? null : _submitAuth,
                child: _isAuthLoading
                    ? const CircularProgressIndicator()
                    : Text(_isLoginMode ? local.translate('login') : local.translate('create_account')),
              ),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                  _authFormKey.currentState?.reset();
                });
              },
              child: Text(_isLoginMode
                  ? local.translate('no_account_create_one')
                  : local.translate('have_account_login')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudyStep() {
    final local = AppLocalizations.of(context);
    bool isStudyValid = selectedCountryId != null &&
        _generalEducationType != null &&
        selectedMajorId != null &&
        selectedLevelId != null;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            local.translate('select_education_path'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _buildCountryDropdown(),
          const SizedBox(height: 24),

          Text(local.translate('select_education_path_type'),
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),

          RadioGroup<String>(
            groupValue: _generalEducationType,
            onChanged: (val) {
              setState(() {
                _generalEducationType = val;
                selectedMajorId = null;
                selectedLevelId = null;
                _generalMajorsList = [];
                _generalLevelsList = [];
              });
              if (val != null) _fetchGeneralMajors(val);
            },
            child: Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: Text(local.translate('university_student'),
                        style: const TextStyle(fontSize: 14)),
                    value: 'university',
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: Text(local.translate('school_student'),
                        style: const TextStyle(fontSize: 14)),
                    value: 'school',
                  ),
                ),
              ],
            ),
          ),

          if (_generalEducationType != null) ...[
            const SizedBox(height: 16),
            if (_isLoadingMajors)
              const Center(child: CircularProgressIndicator())
            else if (_generalMajorsList.isEmpty)
              Text(local.translate('no_data_available'),
                  style: const TextStyle(color: Colors.red))
            else
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('major_${_generalEducationType}'),
                initialValue: selectedMajorId,
                decoration: InputDecoration(
                  labelText: _generalEducationType == 'university'
                      ? local.translate('select_major')
                      : local.translate('select_stage'),
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _generalMajorsList.map((m) {
                  return DropdownMenuItem<String>(
                    value: m['id'] as String,
                    child: Text(
                      m['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedMajorId = val;
                    selectedLevelId = null;
                    _generalLevelsList = [];
                  });
                  if (val != null) _fetchGeneralLevels(val);
                },
              ),
            const SizedBox(height: 16),
            if (selectedMajorId != null)
              if (_isLoadingLevels)
                const Center(child: CircularProgressIndicator())
              else if (_generalLevelsList.isEmpty)
                Text(local.translate('no_levels_available'),
                    style: const TextStyle(color: Colors.red))
              else
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  key: ValueKey('level_$selectedMajorId'),
                  initialValue: selectedLevelId,
                  decoration: InputDecoration(
                    labelText: local.translate('select_level_grade'),
                    prefixIcon: const Icon(Icons.layers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _generalLevelsList.map((l) {
                    return DropdownMenuItem<String>(
                      value: l['id'] as String,
                      child: Text(
                        l['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedLevelId = val),
                ),
          ],

          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  _cleanupStudyData();
                  _tabController.animateTo(0);
                },
                child: Text(local.translate('back_and_change_account'),
                    style: const TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: isStudyValid ? () async => await _validateStudyStep() : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(local.translate('save_and_continue')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivationStep() {
    final local = AppLocalizations.of(context);
    return FutureBuilder<Map<String, String>>(
      future: _getSocialLinksFuture(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final links = snapshot.data ?? {};
        return SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Icon(Icons.verified_user, size: 80, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 20),
              Text(local.translate('final_step_activation'),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text(
                local.translate('enter_activation_code_hint'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _codeController,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    letterSpacing: 4, fontWeight: FontWeight.bold, fontSize: 18),
                decoration: InputDecoration(
                  hintText: local.translate('activation_code'),
                  border: const OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isActivationLoading ? null : _activateAndRegister,
                  child: _isActivationLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(local.translate('activate_and_finish')),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                local.translate('contact_if_no_code'),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (links['whatsapp']?.isNotEmpty == true)
                    IconButton(
                      icon: const Icon(Icons.chat, color: Colors.green, size: 30),
                      onPressed: () => _launchURL(links['whatsapp']),
                    ),
                  if (links['telegram']?.isNotEmpty == true)
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue, size: 30),
                      onPressed: () => _launchURL(links['telegram']),
                    ),
                  if (links['facebook']?.isNotEmpty == true)
                    IconButton(
                      icon: const Icon(Icons.facebook, color: Colors.blueAccent, size: 30),
                      onPressed: () => _launchURL(links['facebook']),
                    ),
                  if (links['instagram']?.isNotEmpty == true)
                    IconButton(
                      icon: const Icon(Icons.camera_alt, color: Colors.pink, size: 30),
                      onPressed: () => _launchURL(links['instagram']),
                    ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(local.translate('account_setup_activation')),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kTextTabBarHeight),
          child: IgnorePointer(
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(icon: const Icon(Icons.lock), text: local.translate('account')),
                Tab(icon: const Icon(Icons.school), text: local.translate('education')),
                Tab(icon: const Icon(Icons.check_circle), text: local.translate('activation')),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: TabBarView(
          controller: _tabController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildAuthStep(),
            _buildStudyStep(),
            _buildActivationStep(),
          ],
        ),
      ),
    );
  }
}