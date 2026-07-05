// ============================================================
// FILE: lib/services/secure_storage_helper.dart
// ============================================================
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageHelper {
  static const _storage = FlutterSecureStorage();

  static const _keyIsActivated = 'is_activated';
  static const _keySessionId = 'session_id';
  static const _keyKickReason = 'kick_reason';
  static const _keyExpiryDate = 'expiry_date';

  static Future<void> saveActivation({required String sessionId, required String expiryDate}) async {
    await _storage.write(key: _keyIsActivated, value: 'true');
    await _storage.write(key: _keySessionId, value: sessionId);
    await _storage.write(key: _keyExpiryDate, value: expiryDate);
    await _storage.delete(key: _keyKickReason);
  }

  static Future<void> killActivation(String reason) async {
    await _storage.write(key: _keyIsActivated, value: 'false');
    await _storage.write(key: _keyKickReason, value: reason);
    await _storage.delete(key: _keySessionId);
  }

  static Future<void> suspendActivation(String reason) async {
    await _storage.write(key: _keyIsActivated, value: 'false');
    await _storage.write(key: _keyKickReason, value: reason);
    // لا نحذف _keySessionId للحفاظ على معرف الجلسة
  }

  static Future<void> updateExpiryDate(String expiryDate) async {
    await _storage.write(key: _keyExpiryDate, value: expiryDate);
  }

  static Future<bool> isUserActivated() async {
    String? value = await _storage.read(key: _keyIsActivated);
    return value == 'true';
  }

  static Future<String?> getSessionId() async {
    return await _storage.read(key: _keySessionId);
  }

  static Future<String?> getKickReason() async {
    return await _storage.read(key: _keyKickReason);
  }

  static Future<void> clearKickReason() async {
    await _storage.delete(key: _keyKickReason);
  }

  static Future<String?> getExpiryDate() async {
    return await _storage.read(key: _keyExpiryDate);
  }

  // ========== دوال مسح البيانات الجديدة ==========
  static Future<void> clearActivation() async {
    await _storage.delete(key: _keyIsActivated);
    await _storage.delete(key: _keyExpiryDate);
  }

  static Future<void> clearSessionId() async {
    await _storage.delete(key: _keySessionId);
  }

  static Future<void> clearAllActivationData() async {
    await clearActivation();
    await clearSessionId();
    await clearKickReason();
  }
}