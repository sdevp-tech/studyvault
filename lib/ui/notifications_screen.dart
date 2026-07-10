// notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // تم الاستيراد لدعم النسخ للحافظة (Clipboard)
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../../models/notification_item.dart';
import 'l10n/app_localizations.dart';

class NotificationsScreen extends StatelessWidget {
  final int initialTabIndex; // إضافة متغير لتحديد التبويب الافتراضي

  const NotificationsScreen({
    Key? key,
    this.initialTabIndex = 0, // القيمة الافتراضية 0 (عامة)
  }) : super(key: key);

  void _markAllAsRead() {
    final box = Hive.box<NotificationItem>('notifications_box');
    for (var item in box.values) {
      if (!item.isRead) {
        item.isRead = true;
        item.save();
      }
    }
  }

  void _deleteAll() {
    final box = Hive.box<NotificationItem>('notifications_box');
    box.clear();
  }

  void _showNotificationDetails(BuildContext context, NotificationItem notification) {
    final local = AppLocalizations.of(context);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // مهم جداً للسماح للنافذة بأخذ مساحة أكبر من الشاشة
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          // تحديد أقصى ارتفاع للنافذة ليكون 85% من حجم الشاشة لضمان عدم اختفائها بالكامل
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            // مساحة إضافية بالأسفل لمنع تداخل أزرار النظام (Navigation Bar) مع المحتوى
            bottom: MediaQuery.of(context).padding.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).canvasColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // مؤشر السحب العلوي (الخط الصغير)
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // صف العنوان + زر النسخ
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      notification.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // أيقونة النسخ
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: Theme.of(context).colorScheme.primary),
                    tooltip: 'نسخ الإشعار',
                    onPressed: () {
                      // نسخ العنوان ومحتوى الإشعار معاً
                      final textToCopy = "${notification.title}\n\n${notification.body}";
                      Clipboard.setData(ClipboardData(text: textToCopy));
                      
                      // إظهار رسالة تأكيد للمستخدم
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text("تم نسخ محتوى الإشعار بنجاح", style: TextStyle(fontFamily: 'Cairo')), // ضع الخط الخاص بتطبيقك إذا وجد
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          duration: const Duration(milliseconds: 1500),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

              // محتوى الإشعار القابل للتمرير
              // إستخدام Flexible مع SingleChildScrollView هو السر الذي يسمح بقراءة النصوص الطويلة
              Flexible(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      notification.body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.6, // زيادة التباعد بين الأسطر لقراءة أكثر راحة
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              // وقت الإشعار
              Text(
                DateFormat('yyyy/MM/dd - hh:mm a', Localizations.localeOf(context).languageCode)
                    .format(notification.timestamp),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
              ),
              const SizedBox(height: 20),
              
              // زر الإغلاق
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(local.translate('close')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // بناء القائمة بشكل مستقل لكل تبويب لمنع أي خطأ في البناء عند الفلترة
  Widget _buildNotificationsList(BuildContext context, List<NotificationItem> list, AppLocalizations local) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_off_outlined,
              size: 100,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              local.translate('no_notifications'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).disabledColor,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      padding: const EdgeInsets.all(8),
      itemBuilder: (context, index) {
        final notification = list[index];
        return Dismissible(
          key: Key(notification.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete, color: Colors.white, size: 30),
          ),
          onDismissed: (direction) {
            notification.delete();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Card(
              elevation: notification.isRead ? 1 : 3,
              shadowColor: notification.isRead
                  ? null
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: notification.isRead
                  ? Theme.of(context).cardColor
                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (!notification.isRead) {
                    notification.isRead = true;
                    notification.save();
                  }
                  _showNotificationDetails(context, notification);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: notification.isRead
                            ? Theme.of(context).disabledColor.withValues(alpha: 0.2)
                            : Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          notification.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: notification.isRead
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.primary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notification.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: notification.isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notification.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.color
                                        ?.withValues(alpha: 0.8),
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DateFormat('yyyy/MM/dd - hh:mm a', Localizations.localeOf(context).languageCode)
                                  .format(notification.timestamp),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).disabledColor,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.info_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => _showNotificationDetails(context, notification),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex, // استخدام المتغير هنا لتحديد التبويب
      child: Scaffold(
        appBar: AppBar(
          title: Text(local.translate('notifications_center')),
          centerTitle: true,
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor ??
              Theme.of(context).primaryColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor ??
              ((Theme.of(context).primaryColor.computeLuminance() > 0.5)
                  ? Colors.black
                  : Colors.white),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'عامة'),
              Tab(text: 'علمية / تخصصية'),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: local.translate('mark_all_read'),
              onPressed: _markAllAsRead,
            ),
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: local.translate('delete_all_notifications'),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(local.translate('delete_all')),
                    content: Text(local.translate('confirm_delete_all_notifications')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(local.translate('cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                          local.translate('delete'),
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  _deleteAll();
                }
              },
            ),
          ],
        ),
        body: ValueListenableBuilder<Box<NotificationItem>>(
          valueListenable: Hive.box<NotificationItem>('notifications_box').listenable(),
          builder: (context, box, _) {
            final allNotifications = box.values.toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

            // تطبيق الفلترة الذكية مع مراعاة الأخطاء الإملائية الشائعة مثل التاء المربوطة والهاء
            final specializedNotifications = allNotifications.where((n) {
              final title = n.title.toLowerCase();
              final body = n.body.toLowerCase();
              return title.contains('علمي') || title.contains('تخصص') || 
                     body.contains('علمي') || body.contains('تخصص');
            }).toList();

            final generalNotifications = allNotifications.where((n) {
              final title = n.title.toLowerCase();
              final body = n.body.toLowerCase();
              return !title.contains('علمي') && !title.contains('تخصص') && 
                     !body.contains('علمي') && !body.contains('تخصص');
            }).toList();

            return TabBarView(
              children: [
                _buildNotificationsList(context, generalNotifications, local),
                _buildNotificationsList(context, specializedNotifications, local),
              ],
            );
          },
        ),
      ),
    );
  }
}