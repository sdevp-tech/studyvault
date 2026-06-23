import 'dart:async';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/assignment_model.dart';
import 'notification_service.dart';

class AssignmentService {
  final Box<Assignment> box;

  AssignmentService(this.box);

  Future<Assignment> addAssignment({
    required String title,
    String? description,
    required AssignmentType type,
    required DateTime dueDate,
    String? field,
    String? year,
    String? subject,
    String? lecture,
    bool hasReminder = false,
  }) async {
    // ========== بداية التشخيص ==========
    print('📝 [AssignmentService] addAssignment: title=$title, dueDate=$dueDate, hasReminder=$hasReminder');
    // ====================================

    final id = const Uuid().v4();
    final assignment = Assignment(
      id: id,
      title: title,
      description: description,
      type: type,
      status: AssignmentStatus.pending,
      dueDate: dueDate,
      field: field,
      year: year,
      subject: subject,
      lecture: lecture,
      hasReminder: hasReminder,
      createdAt: DateTime.now(),
    );
    await box.put(id, assignment);

    if (hasReminder && dueDate.isAfter(DateTime.now())) {
      print('   - سيتم جدولة إشعار للتكليف الجديد');
      try {
        await NotificationService().scheduleNotification(
          id: id.hashCode,
          title: 'تذكير بتكليف',
          body: 'التكليف "$title"غير مكتمل ',
          scheduledTime: dueDate,
        );
        print('✅ [AssignmentService] تم استدعاء scheduleNotification بنجاح');
      } catch (e) {
        print('❌ [AssignmentService] فشل استدعاء scheduleNotification: $e');
      }
    } else {
      print('   - لن يتم جدولة إشعار (hasReminder=$hasReminder أو الوقت في الماضي)');
    }

    return assignment;
  }

  Future<void> updateAssignment(Assignment assignment) async {
    final old = box.get(assignment.id);

    // إلغاء الإشعار القديم دائمًا قبل الحفظ
    if (old != null) {
      try {
        await NotificationService().cancelNotification(old.id.hashCode);
        print('ℹ️ تم إلغاء الإشعار القديم قبل التحديث');
      } catch (e) {
        print('⚠️ فشل إلغاء الإشعار القديم: $e');
      }
    }

    await assignment.save();

    // جدولة جديدة فقط إذا كان التذكير مفعلاً والموعد مستقبلي
    if (assignment.hasReminder && assignment.dueDate.isAfter(DateTime.now())) {
      try {
        await NotificationService().scheduleNotification(
          id: assignment.id.hashCode,
          title: 'تذكير بتكليف',
          body: 'التكليف "${assignment.title}" التكليف غير مكتمل',
          scheduledTime: assignment.dueDate,
        );
        print('✅ تم جدولة إشعار محدث للتكليف ${assignment.id}');
      } catch (e) {
        print('❌ فشل جدولة الإشعار المحدث: $e');
      }
    }
  }

  Future<void> deleteAssignment(String id) async {
    try {
      await NotificationService().cancelNotification(id.hashCode);
    } catch (e) {
      print('⚠️ فشل إلغاء الإشعار للتكليف $id: $e');
    }
    await box.delete(id);
  }

  List<Assignment> getAllAssignments() {
    return box.values.toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<Assignment> getAssignmentsByStatus(AssignmentStatus status) {
    return box.values
        .where((a) => a.status == status)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<Assignment> getUpcomingAssignments({int days = 7}) {
    final now = DateTime.now();
    final deadline = now.add(Duration(days: days));

    return box.values
        .where((a) =>
            a.dueDate.isAfter(now) &&
            a.dueDate.isBefore(deadline) &&
            a.status != AssignmentStatus.completed)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  List<Assignment> getOverdueAssignments() {
    final now = DateTime.now();
    return box.values
        .where((a) =>
            a.dueDate.isBefore(now) &&
            a.status != AssignmentStatus.completed)
        .toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  }

  Future<void> changeStatus(String id, AssignmentStatus newStatus) async {
    final assignment = box.get(id);
    if (assignment == null) return;

    assignment.status = newStatus;

    // دائمًا: إلغاء أي إشعار قديم مرتبط بالتكليف
    try {
      await NotificationService().cancelNotification(id.hashCode);
      print('ℹ️ تم إلغاء الإشعار القديم للتكليف $id');
    } catch (e) {
      print('⚠️ فشل إلغاء الإشعار القديم: $e');
    }

    // جدولة إشعار جديد فقط إذا:
    // - التذكير مفعل
    // - الموعد لم ينته بعد
    // - الحالة ليست مكتملة
    if (assignment.hasReminder &&
        assignment.dueDate.isAfter(DateTime.now()) &&
        newStatus != AssignmentStatus.completed) {
      
      String title = 'تذكير بتكليف';
      String body = 'التكليف "${assignment.title}" مستحق الآن';

      // تخصيص الرسالة حسب الحالة
      if (newStatus == AssignmentStatus.inProgress) {
        title = 'تذكير – قيد التنفيذ';
        body = 'ما زال التكليف "${assignment.title}" يحتاج إلى إنهاء قريبًا';
      } else if (newStatus == AssignmentStatus.pending) {
        title = 'تذكير – قيد الانتظار';
        body = 'التكليف "${assignment.title}" ما زال في قائمة الانتظار';
      }

      try {
        await NotificationService().scheduleNotification(
          id: id.hashCode,
          title: title,
          body: body,
          scheduledTime: assignment.dueDate,
        );
        print('✅ تم جدولة إشعار جديد لـ $id (حالة: $newStatus)');
      } catch (e) {
        print('❌ فشل جدولة الإشعار بعد تغيير الحالة: $e');
      }
    }

    await assignment.save();
  }

  Map<AssignmentStatus, int> getStatistics() {
    final all = box.values.toList();
    return {
      AssignmentStatus.pending: all.where((a) => a.status == AssignmentStatus.pending).length,
      AssignmentStatus.inProgress: all.where((a) => a.status == AssignmentStatus.inProgress).length,
      AssignmentStatus.completed: all.where((a) => a.status == AssignmentStatus.completed).length,
      AssignmentStatus.overdue: all.where((a) => a.status == AssignmentStatus.overdue).length,
    };
  }

  void updateOverdueAssignments() {
    final now = DateTime.now();
    for (final assignment in box.values) {
      if (assignment.dueDate.isBefore(now) &&
          assignment.status != AssignmentStatus.completed &&
          assignment.status != AssignmentStatus.overdue) {
        assignment.status = AssignmentStatus.overdue;
        assignment.save();
      }
    }
  }
}