import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../models/settings_model.dart';
import '../../ui/theme/app_theme.dart';
import '../l10n/app_localizations.dart';

class QuickAccessCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;
  final int count;

  const QuickAccessCard({
    Key? key,
    required this.title,
    required this.icon,
    this.color,
    required this.onTap,
    this.count = 0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final settingsBox = Hive.box<AppSettings>('settings_box');
    final settings = settingsBox.isNotEmpty ? settingsBox.getAt(0) : null;

    Color cardColor;
    switch (title) {
      case 'التخصصات':
      case 'fields':
        cardColor = scheme.primary;
        break;
      case 'AI':
        cardColor = Colors.purple;
        break;
      case 'التكاليف':
      case 'assignments':
        cardColor = scheme.warning;
        break;
      case 'قائمة المهام':
      case 'todo':
        cardColor = scheme.success;
        break;
      case 'البحث':
      case 'search':
        cardColor = Colors.teal;
        break;
      case 'المحاضرات':
      case 'lectures':
        cardColor = Colors.red;
        break;
      case 'المراجعة الذكية':
      case 'smart_review':
        cardColor = Colors.indigo;
        break;
      case 'التعليقات':
      case 'comments':
        cardColor = Colors.teal;
        break;
      case 'الإعدادات':
      case 'settings':
        cardColor = Colors.grey;
        break;
      default:
        cardColor = color ?? scheme.primary;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 120,
            maxHeight: 140,
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: cardColor, size: 24),
                  ),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getLocalizedTitle(title, settings, local),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      color: scheme.onSurface,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    local.translate('tap_for_quick_access'),
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getLocalizedTitle(String key, AppSettings? settings, AppLocalizations local) {
    switch (key) {
      case 'التخصصات':
      case 'fields':
        if (settings != null && settings.fieldsTitle.isNotEmpty && settings.fieldsTitle != 'التخصصات') {
          return settings.fieldsTitle;
        }
        return local.translate('fields');
        
      case 'السنة':
      case 'السنوات':
      case 'years':
        if (settings != null && settings.yearsTitle.isNotEmpty && settings.yearsTitle != 'السنوات' && settings.yearsTitle != 'السنة') {
          return settings.yearsTitle;
        }
        return local.translate('years');
        
      case 'المواد':
      case 'subjects':
        if (settings != null && settings.subjectsTitle.isNotEmpty && settings.subjectsTitle != 'المواد') {
          return settings.subjectsTitle;
        }
        return local.translate('subjects');
        
      case 'المحاضرات':
      case 'lectures':
        if (settings != null && settings.lecturesTitle.isNotEmpty && settings.lecturesTitle != 'المحاضرات') {
          return settings.lecturesTitle;
        }
        return local.translate('lectures');
        
      case 'التكاليف':
      case 'assignments':
        if (settings != null && settings.assignmentsTitle.isNotEmpty && settings.assignmentsTitle != 'التكاليف') {
          return settings.assignmentsTitle;
        }
        return local.translate('assignments');
        
      case 'الاختبارات':
      case 'exams':
        if (settings != null && settings.examsTitle.isNotEmpty && settings.examsTitle != 'الاختبارات') {
          return settings.examsTitle;
        }
        return local.translate('exams');
        
      case 'قائمة المهام':
      case 'todo':
        if (settings != null && settings.todoTitle.isNotEmpty && settings.todoTitle != 'قائمة المهام') {
          return settings.todoTitle;
        }
        return local.translate('todo');
        
      case 'البحث':
      case 'search':
        return local.translate('search');
        
      case 'المراجعة الذكية':
      case 'smart_review':
        return local.translate('smart_review');
        
      case 'التعليقات':
      case 'comments':
        return local.translate('comments');
        
      case 'الإعدادات':
      case 'settings':
        return local.translate('settings');
        
      case 'AI':
        return 'AI';
        
      default:
        return local.translate(key);
    }
  }
}