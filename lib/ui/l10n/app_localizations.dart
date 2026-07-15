import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppLocalizations {
  final Locale locale;
  Map<String, String> _localizedStrings = {};

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  /// Loads the localization JSON for [locale].
  ///
  /// Crash-proof: if the requested language file is missing, malformed, or
  /// fails to decode, it falls back to Arabic, then to an empty map so that
  /// [translate] simply echoes the key instead of throwing and crashing the
  /// entire app into the ErrorApp screen.
  Future<bool> load() async {
    _localizedStrings = await _tryLoad(locale.languageCode);

    if (_localizedStrings.isEmpty && locale.languageCode != 'ar') {
      _localizedStrings = await _tryLoad('ar');
    }

    return true;
  }

  Future<Map<String, String>> _tryLoad(String languageCode) async {
    try {
      final String jsonString =
          await rootBundle.loadString('assets/lang/$languageCode.json');
      final Map<String, dynamic> jsonMap =
          json.decode(jsonString) as Map<String, dynamic>;
      return jsonMap.map((key, value) => MapEntry(key, value.toString()));
    } catch (e) {
      debugPrint('⚠️ Failed to load localization for "$languageCode": $e');
      return <String, String>{};
    }
  }

  String translate(String key) {
    return _localizedStrings[key] ?? key;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['en', 'ar'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    AppLocalizations localizations = AppLocalizations(locale);
    await localizations.load();
    return localizations;
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
