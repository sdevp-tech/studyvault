import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../models/settings_model.dart';
import '../l10n/app_localizations.dart';
class CustomBottomNavBar extends StatefulWidget {
  final int currentIndex;
  final Function(int) onTap;
  final bool showLabels;

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    this.showLabels = true,
  }) : super(key: key);

  @override
  State<CustomBottomNavBar> createState() => _CustomBottomNavBarState();
}

class _CustomBottomNavBarState extends State<CustomBottomNavBar> {
  late AppSettings _settings;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsBox = Hive.box<AppSettings>('settings_box');
    if (settingsBox.isNotEmpty) {
      setState(() {
        _settings = settingsBox.getAt(0)!;
        _settingsLoaded = true;
      });
    } else {
      setState(() {
        _settings = AppSettings();
        _settingsLoaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    // انتظار تحميل الإعدادات (يحدث بسرعة)
    if (!_settingsLoaded) {
      return const SizedBox.shrink(); // أو يمكن عرض تقدم بسيط
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 0. الرئيسية
          _buildNavItem(
            index: 0,
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: local.translate('home_title'),
          ),
          // 1. المحادثات (جديد)
          _buildNavItem(
            index: 1,
            icon: Icons.chat_outlined,
            activeIcon: Icons.chat_rounded,
           label: local.translate('chats_title'),
          ),
          // 2. Copilot
          _buildNavItem(
            index: 2,
            icon: Icons.smart_toy_outlined,
            activeIcon: Icons.smart_toy_rounded,
           label: local.translate('copilot_title'),
          ),
          // 3. التكاليف
          _buildNavItem(
            index: 3,
            icon: Icons.assignment_outlined,
            activeIcon: Icons.assignment_rounded,
            label: _settings.assignmentsTitle,
          ),
          // 4. قائمة المهام
          _buildNavItem(
            index: 4,
            icon: Icons.checklist_outlined,
            activeIcon: Icons.checklist_rounded,
            label: _settings.todoTitle,
          ),
          // 5. المراجعة الذكية (جديد)
          _buildNavItem(
            index: 5,
            icon: Icons.repeat_outlined,
            activeIcon: Icons.repeat_rounded,
           label: local.translate('review_title'),
          ),
          // 6. التعليقات (جديد)
          _buildNavItem(
            index: 6,
            icon: Icons.note_outlined,
            activeIcon: Icons.note_rounded,
            label: local.translate('annotations_title'),
          ),
          // 7. التخصصات
          _buildNavItem(
            index: 7,
            icon: Icons.category_outlined,
            activeIcon: Icons.category_rounded,
            label: _settings.fieldsTitle,
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = widget.currentIndex == index;
    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withAlpha(153);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => widget.onTap(index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Icon(
                      isActive ? activeIcon : icon,
                      size: 24,
                      color: color,
                    ),
                    if (isActive)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).colorScheme.surface,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.showLabels) ...[
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}