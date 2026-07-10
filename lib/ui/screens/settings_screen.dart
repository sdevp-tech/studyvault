import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import '../../models/settings_model.dart';
import '../../models/asset_model.dart';
import '../../models/assignment_model.dart';
import '../../models/todo_model.dart';
import '../../services/spaced_repetition_service.dart';
import '../../services/annotation_service.dart';
import '../../services/storage_service.dart';
import '../../services/secure_storage_helper.dart';
import '../l10n/app_localizations.dart';
import 'llm_settings_screen.dart';
import 'edit_profile_screen.dart';
import '../../globals.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings settings;
  final Map<String, TextEditingController> _controllers = {};
  final StorageService _storage = StorageService();

  bool _isClearing = false;
  String _selectedPreset = 'جامعي';

  Map<String, String> socialLinks = {};
  String appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getSocialLinks();
    _getAppVersion();
  }

  void _loadSettings() {
    final box = Hive.box<AppSettings>('settings_box');
    if (box.isEmpty) box.add(AppSettings());
    settings = box.getAt(0)!;

    _controllers['fields'] = TextEditingController(text: settings.fieldsTitle);
    _controllers['years'] = TextEditingController(text: settings.yearsTitle);
    _controllers['subjects'] = TextEditingController(text: settings.subjectsTitle);
    _controllers['lectures'] = TextEditingController(text: settings.lecturesTitle);
    _controllers['assignments'] = TextEditingController(text: settings.assignmentsTitle);
    _controllers['exams'] = TextEditingController(text: settings.examsTitle);
    _controllers['todo'] = TextEditingController(text: settings.todoTitle);

    _determinePreset();
  }

  void _determinePreset() {
    if (settings.fieldsTitle == 'التخصصات' && settings.lecturesTitle == 'المحاضرات') {
      _selectedPreset = 'جامعي';
    } else if (settings.fieldsTitle == 'المراحل' && settings.lecturesTitle == 'الحصص') {
      _selectedPreset = 'مدرسي';
    } else if (settings.fieldsTitle == 'البرامج' && settings.lecturesTitle == 'الجلسات') {
      _selectedPreset = 'معهد';
    } else {
      _selectedPreset = 'مخصص';
    }
  }

  Future<void> _getSocialLinks() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('global_info')
          .get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          socialLinks = {
            'whatsapp': doc.data()!['whatsappLink']?.toString() ?? '',
            'telegram': doc.data()!['TelegramLink']?.toString() ?? '',
            'facebook': doc.data()!['FacebookLink']?.toString() ?? '',
            'instagram': doc.data()!['InstgramLink']?.toString() ?? '',
          };
        });
      }
    } catch (e) {
      debugPrint("خطأ في جلب روابط التواصل: $e");
    }
  }

  Future<void> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        appVersion = packageInfo.version;
      });
    } catch (e) {
      appVersion = '1.0.0';
    }
  }

  Future<void> _saveSettings() async {
    settings.fieldsTitle = _controllers['fields']!.text.trim();
    settings.yearsTitle = _controllers['years']!.text.trim();
    settings.subjectsTitle = _controllers['subjects']!.text.trim();
    settings.lecturesTitle = _controllers['lectures']!.text.trim();
    settings.assignmentsTitle = _controllers['assignments']!.text.trim();
    settings.examsTitle = _controllers['exams']!.text.trim();
    settings.todoTitle = _controllers['todo']!.text.trim();

    await settings.save();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).translate('success_save')),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _applyPreset(String preset) {
    final local = AppLocalizations.of(context);
    setState(() {
      _selectedPreset = preset;
      if (preset == 'جامعي') {
        _controllers['fields']!.text = local.translate('fields');
        _controllers['years']!.text = local.translate('years');
        _controllers['subjects']!.text = local.translate('subjects');
        _controllers['lectures']!.text = local.translate('lectures');
        _controllers['assignments']!.text = local.translate('assignments');
        _controllers['exams']!.text = local.translate('exams');
        _controllers['todo']!.text = local.translate('todo');
      } else if (preset == 'مدرسي') {
        _controllers['fields']!.text = local.translate('school_fields');
        _controllers['years']!.text = local.translate('school_years');
        _controllers['subjects']!.text = local.translate('subjects');
        _controllers['lectures']!.text = local.translate('school_lectures');
        _controllers['assignments']!.text = local.translate('school_assignments');
        _controllers['exams']!.text = local.translate('school_exams');
        _controllers['todo']!.text = local.translate('school_todo');
      } else if (preset == 'معهد') {
        _controllers['fields']!.text = local.translate('institute_fields');
        _controllers['years']!.text = local.translate('institute_years');
        _controllers['subjects']!.text = local.translate('institute_subjects');
        _controllers['lectures']!.text = local.translate('institute_lectures');
        _controllers['assignments']!.text = local.translate('institute_assignments');
        _controllers['exams']!.text = local.translate('exams');
        _controllers['todo']!.text = local.translate('institute_todo');
      }
    });

    if (preset != 'مخصص') {
      _saveSettings();
    }
  }

  Future<void> _showAssetContent(String assetPath, String title) async {
    try {
      String content = await rootBundle.loadString(assetPath);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Text(content),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(AppLocalizations.of(context).translate('close')),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorSnackBar('لم يتم العثور على الملف: $assetPath');
    }
  }

  void _launchURL(String? urlString) async {
    final local = AppLocalizations.of(context);
    if (urlString == null || urlString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('link_unavailable'))),
      );
      return;
    }
    final Uri url = Uri.parse(urlString.trim());
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('cannot_open_link'))),
      );
    }
  }

  // ==================== دوال حذف الحساب ====================

  Future<void> _deleteAccount() async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(local.translate('delete_account')),
        content: Text(local.translate('delete_account_warning')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(local.translate('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _handleReauthenticationAndDeletion(user, local);
  }

  Future<void> _handleReauthenticationAndDeletion(User user, AppLocalizations local) async {
    final password = await _showPasswordDialog(local);
    if (password == null || password.isEmpty) {
      _showErrorSnackBar(local.translate('delete_cancelled_password_required'));
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);

      await FirebaseFirestore.instance.collection('deleted_accounts').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'fullName': user.displayName ?? '',
        'deletedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data()!;
        userData['uuid'] = userDoc.id;
        await FirebaseFirestore.instance
            .collection('deleted_accounts_data')
            .doc(user.uid)
            .set(userData);
        await userDoc.reference.delete();
      }

      await user.delete();
      await FirebaseAuth.instance.signOut();

      await _clearAllLocalDataAfterDeletion();
      activationNotifier.value = false;

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(local.translate('account_deleted_title')),
            content: Text(local.translate('account_deleted_message')),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop(); 
                  if (Platform.isAndroid) {
                    SystemNavigator.pop();
                  } else {
                    exit(0);
                  }
                },
                child: Text(local.translate('ok')),
              ),
            ],
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        _showErrorSnackBar(local.translate('wrong_password_delete_failed'));
      } else {
        _showErrorSnackBar('${local.translate('error')}: ${e.message}');
      }
    } catch (e) {
      _showErrorSnackBar('${local.translate('error')}: $e');
    }
  }

  Future<String?> _showPasswordDialog(AppLocalizations local) async {
    String password = '';
    bool obscureText = true;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Row(
                children: [
                  const Icon(Icons.security, color: Colors.red),
                  const SizedBox(width: 10),
                  Text(local.translate('confirm_identity'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(local.translate('security_password_prompt')),
                  const SizedBox(height: 20),
                  TextField(
                    obscureText: obscureText,
                    onChanged: (value) => password = value,
                    decoration: InputDecoration(
                      labelText: local.translate('password'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                        icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
                        onPressed: () {
                          setState(() {
                            obscureText = !obscureText;
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(local.translate('cancel')),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, password),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(local.translate('confirm_and_delete'), style: const TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _clearAllLocalDataAfterDeletion() async {
    try {
      await Hive.box<AssetModel>('assets_box').clear();
      await Hive.box<CardModel>('cards_box').clear();
      await Hive.box<Annotation>('annotations_box').clear();
      await Hive.box<Assignment>('assignments_box').clear();
      await Hive.box<TodoItem>('todos_box').clear();
      await Hive.box<AppSettings>('settings_box').clear();

      final vault = await _storage.ensureStudyVault();
      if (await vault.exists()) await vault.delete(recursive: true);
      await _storage.ensureStudyVault();

      await SecureStorageHelper.clearActivation();
      await SecureStorageHelper.clearSessionId();
      await SecureStorageHelper.clearKickReason();

      debugPrint("✅ All local data and secure storage cleared after account deletion.");
    } catch (e) {
      debugPrint("Error clearing local data after deletion: $e");
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ==================== مسح البيانات اليدوي ====================

  Future<void> _clearAllLocalData() async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Text(local.translate('warning'), style: const TextStyle(color: Colors.red)),
          ],
        ),
        content: Text(local.translate('clear_all_data_warning')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(local.translate('clear_all_confirm'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isClearing = true);

    try {
      await Hive.box<AssetModel>('assets_box').clear();
      await Hive.box<CardModel>('cards_box').clear();
      await Hive.box<Annotation>('annotations_box').clear();
      await Hive.box<Assignment>('assignments_box').clear();
      await Hive.box<TodoItem>('todos_box').clear();
      await Hive.box<AppSettings>('settings_box').clear();

      final vault = await _storage.ensureStudyVault();
      if (await vault.exists()) await vault.delete(recursive: true);
      await _storage.ensureStudyVault();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('clear_all_success')), backgroundColor: Colors.green),
        );
        await Future.delayed(const Duration(seconds: 1));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  // ==================== بناء الواجهة ====================

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return ValueListenableBuilder<Box<AppSettings>>(
      valueListenable: Hive.box<AppSettings>('settings_box').listenable(),
      builder: (context, box, child) {
        settings = box.getAt(0)!;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
          appBar: AppBar(
            title: Text(local.translate('settings'), style: const TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
          body: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              _buildProfileSection(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('general')),
              _buildGeneralSettings(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('academic_affiliation')),
              _buildAcademicAffiliation(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('ai_section_title')),
              _buildAISettings(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('customize_labels')),
              _buildEducationalCustomization(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('privacy_security')),
              _buildPrivacySecuritySection(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('support_help')),
              _buildSupportSection(),
              const SizedBox(height: 24),
              _buildSectionTitle(local.translate('data_management')),
              _buildDataManagement(),
              const SizedBox(height: 24),
              _buildAppVersionInfo(),
              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildProfileSection() {
    final local = AppLocalizations.of(context);
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? local.translate('guest_user');
    final phone = user?.phoneNumber ?? '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const CircleAvatar(
              radius: 35,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 40, color: Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(local.translate('profile'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildAcademicAffiliation() {
    final local = AppLocalizations.of(context); 
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: _buildListTile(
        icon: Icons.account_balance,
        iconColor: Colors.deepOrange,
        title: local.translate('link_to_institution'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (ctx) => const InstitutionLinkingSheet(),
          );
        },
      ),
    );
  }

  Widget _buildGeneralSettings() {
    final local = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.language,
            iconColor: Colors.blue,
            title: local.translate('language'),
            trailing: DropdownButton<String>(
              value: settings.language,
              underline: const SizedBox(),
              icon: const Icon(Icons.keyboard_arrow_down, color: Colors.grey),
              style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
              items: [
                DropdownMenuItem(value: 'العربية', child: Text(local.translate('arabic'))),
                DropdownMenuItem(value: 'English', child: Text(local.translate('english'))),
              ],
              onChanged: (newValue) async {
                if (newValue != null && newValue != settings.language) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(local.translate('language')),
                      content: Text(local.translate('language_change_confirm_message')),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(local.translate('cancel')),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(local.translate('ok')),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;

                  settings.language = newValue;
                  final newLocal = AppLocalizations(Locale(newValue == 'العربية' ? 'ar' : 'en'));
                  await newLocal.load();
                  settings.fieldsTitle = newLocal.translate('fields');
                  settings.yearsTitle = newLocal.translate('years');
                  settings.subjectsTitle = newLocal.translate('subjects');
                  settings.lecturesTitle = newLocal.translate('lectures');
                  settings.assignmentsTitle = newLocal.translate('assignments');
                  settings.examsTitle = newLocal.translate('exams');
                  settings.todoTitle = newLocal.translate('todo');
                  
                  await settings.save();
                  
                  if (mounted) {
                    await Future.delayed(const Duration(milliseconds: 500));
                  }
                }
              },
            ),
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          _buildListTile(
            icon: Icons.dark_mode_rounded,
            iconColor: Colors.indigo,
            title: local.translate('dark_mode'),
            trailing: Switch.adaptive(
              activeThumbColor: Theme.of(context).colorScheme.primary,
              value: settings.isDarkMode,
              onChanged: (value) {
                settings.isDarkMode = value;
                settings.save();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISettings() {
    final local = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.smart_toy, color: Colors.purple),
        ),
        title: Text(local.translate('ai_settings')),
        subtitle: Text(local.translate('ai_settings_subtitle')),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LlmSettingsScreen()),
          );
        },
      ),
    );
  }

  Widget _buildEducationalCustomization() {
    final local = AppLocalizations.of(context);
    final presets = {
      'جامعي': local.translate('preset_university'),
      'مدرسي': local.translate('preset_school'),
      'معهد': local.translate('preset_institute'),
      'مخصص': local.translate('preset_custom'),
    };

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedPreset,
              decoration: InputDecoration(
                labelText: local.translate('customize_labels'),
                prefixIcon: const Icon(Icons.school, color: Colors.orange),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
              ),
              items: presets.entries.map((e) {
                return DropdownMenuItem<String>(
                  value: e.key,
                  child: Text(e.value),
                );
              }).toList(),
              onChanged: (newValue) {
                if (newValue != null) _applyPreset(newValue);
              },
            ),
            if (_selectedPreset == 'مخصص') ...[
              const SizedBox(height: 20),
              Text(local.translate('manual_customization'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 12),
              _buildTextField(local.translate('field_label_hint'), 'fields'),
              _buildTextField(local.translate('year_label_hint'), 'years'),
              _buildTextField(local.translate('subject_label_hint'), 'subjects'),
              _buildTextField(local.translate('lecture_label_hint'), 'lectures'),
              _buildTextField(local.translate('assignment_label_hint'), 'assignments'),
              _buildTextField(local.translate('exam_label_hint'), 'exams'),
              _buildTextField(local.translate('todo_label_hint'), 'todo'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: Text(local.translate('save_custom_labels'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacySecuritySection() {
    final local = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.privacy_tip_outlined,
            iconColor: Colors.blueGrey,
            title: local.translate('privacy_policy'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              _showAssetContent('assets/privacy_policy.txt', local.translate('privacy_policy'));
            },
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          _buildListTile(
            icon: Icons.description_outlined,
            iconColor: Colors.blueGrey,
            title: local.translate('terms_of_service'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              _showAssetContent('assets/terms_of_service.txt', local.translate('terms_of_service'));
            },
          ),
          Divider(height: 1, color: Colors.grey.withValues(alpha: 0.2)),
          _buildListTile(
            icon: Icons.delete_forever,
            iconColor: Colors.red,
            title: local.translate('delete_account'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _deleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildSupportSection() {
    final local = AppLocalizations.of(context);
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 2,
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.headset_mic,
            iconColor: Colors.green,
            title: local.translate('contact_us'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showContactOptions,
          ),
        ],
      ),
    );
  }

  void _showContactOptions() {
    final local = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(local.translate('contact_us'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildSocialIcon(Icons.chat, Colors.green, socialLinks['whatsapp']),
                  _buildSocialIcon(Icons.send, Colors.blue, socialLinks['telegram']),
                  _buildSocialIcon(Icons.facebook, Colors.indigo, socialLinks['facebook']),
                  _buildSocialIcon(Icons.camera_alt, Colors.pink, socialLinks['instagram']),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSocialIcon(IconData icon, Color color, String? url) {
    return IconButton(
      icon: Icon(icon, color: color, size: 36),
      onPressed: () {
        Navigator.pop(context);
        _launchURL(url);
      },
    );
  }

  Widget _buildDataManagement() {
    final local = AppLocalizations.of(context);
    return Card(
      color: Colors.red.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.redAccent, width: 0.5),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.security, color: Colors.red),
                const SizedBox(width: 8),
                Text(local.translate('data_management'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              local.translate('clear_all_data_warning_long'),
              style: const TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isClearing ? null : _clearAllLocalData,
                icon: _isClearing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.delete_forever),
                label: Text(_isClearing ? local.translate('clearing') : local.translate('clear_all_data')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppVersionInfo() {
    final local = AppLocalizations.of(context);
    return Center(
      child: Text(
        '${local.translate('app_version')} $appVersion',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
      ),
    );
  }

  Widget _buildListTile({required IconData icon, required Color iconColor, required String title, required Widget trailing, VoidCallback? onTap}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildTextField(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[key],
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

// ==================== ويدجت الارتباط بمؤسسة (مستخرج من شاشة التفعيل) ====================
class InstitutionLinkingSheet extends StatefulWidget {
  const InstitutionLinkingSheet({Key? key}) : super(key: key);

  @override
  State<InstitutionLinkingSheet> createState() => _InstitutionLinkingSheetState();
}

class _InstitutionLinkingSheetState extends State<InstitutionLinkingSheet> {
  String? selectedCountryId;
  Map<String, dynamic>? selectedInstitution;
  String? selectedMajorId;
  String? selectedLevelId;

  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> filteredInstitutions = [];
  List<Map<String, dynamic>> majors = [];
  List<Map<String, dynamic>> levels = [];

  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _getCountriesFuture();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _getCountriesFuture() async {
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
          (c) => c['name'].toString().contains('يمن') || c['name'].toString().contains('Yemen'),
        );
      } catch (e) {
        yemen = null;
      }
      if (mounted) {
        setState(() {
          countries = list;
          selectedCountryId = yemen?['id'] ?? (list.isNotEmpty ? list.first['id'] : null);
        });
      }
    } catch (e) {
      debugPrint('خطأ في جلب الدول: $e');
    }
  }

  Future<void> _searchInstitutions(String query) async {
    if (selectedCountryId == null || query.isEmpty) {
      setState(() => filteredInstitutions = []);
      return;
    }
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('institutions')
          .where('countryCode', isEqualTo: selectedCountryId)
          .where('name', isGreaterThanOrEqualTo: query)
          .where('name', isLessThanOrEqualTo: '$query\uf8ff')
          .orderBy('name')
          .limit(10)
          .get();

      if (mounted) {
        setState(() {
          filteredInstitutions = snapshot.docs.map((doc) {
            return <String, dynamic>{
              'id': doc.id,
              ...(doc.data() as Map<String, dynamic>? ?? {})
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('خطأ في البحث: $e');
    }
  }

  Future<void> _onInstitutionSelected(Map<String, dynamic> inst) async {
    setState(() {
      selectedInstitution = inst;
      _searchController.text = inst['name'];
      filteredInstitutions = [];
      majors = [];
      levels = [];
      selectedMajorId = null;
      selectedLevelId = null;
    });
    try {
      if (inst['type'] == 'university' || inst['type'] == 'institute') {
        final mSnapshot = await FirebaseFirestore.instance
            .collection('majors')
            .where('institutionId', isEqualTo: inst['id'])
            .get();
        if (mounted) {
          setState(() => majors = mSnapshot.docs.map((doc) => <String, dynamic>{
                'id': doc.id,
                ...(doc.data() as Map<String, dynamic>? ?? {})
              }).toList());
        }
      } else {
        await _fetchLevels(inst['id'], null);
      }
    } catch (e) {
      debugPrint('خطأ في جلب التخصصات: $e');
    }
  }

  Future<void> _fetchLevels(String instId, String? majorId) async {
    try {
      Query query = FirebaseFirestore.instance
          .collection('levels')
          .where('institutionId', isEqualTo: instId);
      if (majorId != null) query = query.where('majorId', isEqualTo: majorId);

      final lSnapshot = await query.get();
      if (mounted) {
        setState(() => levels = lSnapshot.docs.map((doc) => <String, dynamic>{
              'id': doc.id,
              ...(doc.data() as Map<String, dynamic>? ?? {})
            }).toList());
      }
    } catch (e) {
      debugPrint('خطأ في جلب المستويات: $e');
    }
  }

  Future<void> _submitRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (selectedInstitution == null || selectedLevelId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إكمال كافة البيانات المطلوبة')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userName = userDoc.data()?['fullName'] ?? user.displayName ?? 'مستخدم';

      String majorName = majors.firstWhere(
          (m) => m['id'] == selectedMajorId,
          orElse: () => <String, dynamic>{'name': ''})['name'] as String;
      String levelName = levels.firstWhere(
          (l) => l['id'] == selectedLevelId,
          orElse: () => <String, dynamic>{'name': ''})['name'] as String;

      await FirebaseFirestore.instance.collection('join_requests').add({
        'userId': user.uid,
        'userName': userName,
        'institutionId': selectedInstitution!['id'],
        'institutionName': selectedInstitution!['name'],
        'majorId': selectedMajorId,
        'majorName': majorName,
        'levelId': selectedLevelId,
        'levelName': levelName,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'institutionId': selectedInstitution!['id'],
        'majorId': selectedMajorId,
        'levelId': selectedLevelId,
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال طلب الانضمام للمؤسسة بنجاح، وهو قيد المراجعة.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء الإرسال: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'طلب انضمام لمؤسسة تعليمية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            if (countries.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedCountryId,
                decoration: const InputDecoration(
                  labelText: 'اختر الدولة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.public),
                ),
                items: countries.map((c) {
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
                    selectedInstitution = null;
                    _searchController.clear();
                    filteredInstitutions = [];
                    majors = [];
                    levels = [];
                    selectedMajorId = null;
                    selectedLevelId = null;
                  });
                },
              ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'ابحث عن مؤسسة (جامعة، معهد، مدرسة)',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => filteredInstitutions = []);
                  },
                ),
              ),
              onChanged: _searchInstitutions,
            ),
            const SizedBox(height: 8),
            
            if (filteredInstitutions.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: filteredInstitutions.length,
                  itemBuilder: (context, index) {
                    final inst = filteredInstitutions[index];
                    return ListTile(
                      title: Text(inst['name'] as String),
                      subtitle: Text(inst['type'] == 'school' ? 'مدرسة' : 'مؤسسة عليا'),
                      onTap: () => _onInstitutionSelected(inst),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),

            if (selectedInstitution != null && majors.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('inst_${selectedInstitution?['id']}'),
                initialValue: selectedMajorId,
                decoration: const InputDecoration(
                  labelText: 'التخصص',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: majors.map((m) {
                  return DropdownMenuItem<String>(
                    value: m['id'] as String,
                    child: Text(
                      m['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => selectedMajorId = val);
                  if (selectedInstitution != null) {
                    _fetchLevels(selectedInstitution!['id'] as String, val);
                  }
                },
              ),
            
            if (selectedInstitution != null && majors.isNotEmpty)
              const SizedBox(height: 16),

            if ((selectedMajorId != null || (selectedInstitution != null && majors.isEmpty)) && levels.isNotEmpty)
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('major_$selectedMajorId'),
                initialValue: selectedLevelId,
                decoration: const InputDecoration(
                  labelText: 'المستوى / المرحلة',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers),
                ),
                items: levels.map((l) {
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

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitRequest,
                child: _isLoading 
                  ? const CircularProgressIndicator() 
                  : const Text('إرسال طلب الانضمام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}