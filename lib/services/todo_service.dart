import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_model.dart';
import 'notification_service.dart';

class TodoService {
  final Box<TodoItem> box;

  TodoService(this.box);

  /// معرف إشعار موحّد وآمن (32-bit موجب دائماً) — نفس المنطق المستخدم في الشاشات
  /// لضمان أن الجدولة (إلغاء ثم إعادة جدولة) idempotent بلا إشعارات مكررة.
  int _notifId(String id) => id.hashCode & 0x7FFFFFFF;

  Future<TodoItem> addTodo({
    required String title,
    String? description,
    Priority priority = Priority.medium,
    DateTime? dueDate,
    bool hasReminder = false,
  }) async {
    // ========== بداية التشخيص ==========
    print(
        '📝 [TodoService] addTodo: title=$title, dueDate=$dueDate, hasReminder=$hasReminder');
    // ====================================

    final id = const Uuid().v4();
    final todo = TodoItem(
      id: id,
      title: title,
      description: description,
      priority: priority,
      dueDate: dueDate,
      createdAt: DateTime.now(),
      hasReminder: hasReminder,
    );
    await box.put(id, todo);

    if (hasReminder && dueDate != null && dueDate.isAfter(DateTime.now())) {
      print('   - سيتم جدولة إشعار للمهمة الجديدة');
      try {
        await NotificationService().scheduleNotification(
          id: _notifId(id),
          title: 'مهمة مستحقة',
          body: 'المهمة "$title"',
          scheduledTime: dueDate,
        );
        print('✅ [TodoService] تم استدعاء scheduleNotification بنجاح');
      } catch (e) {
        print('❌ [TodoService] فشل استدعاء scheduleNotification: $e');
      }
    } else {
      print(
          '   - لن يتم جدولة إشعار (hasReminder=$hasReminder أو dueDate=null أو الوقت في الماضي)');
    }

    return todo;
  }

  Future<void> updateTodo(TodoItem todo) async {
    final old = box.get(todo.id);
    await todo.save();

    if (old != null) {
      try {
        await NotificationService().cancelNotification(_notifId(old.id));
      } catch (e) {
        print('⚠️ فشل إلغاء الإشعار القديم للمهمة ${old.id}: $e');
      }
    }

    if (todo.hasReminder &&
        todo.dueDate != null &&
        todo.dueDate!.isAfter(DateTime.now()) &&
        !todo.isCompleted) {
      try {
        await NotificationService().scheduleNotification(
          id: _notifId(todo.id),
          title: 'مهمة مستحقة',
          body: 'المهمة "${todo.title}"',
          scheduledTime: todo.dueDate!,
        );
        print('✅ تم جدولة إشعار محدث للمهمة ${todo.id}');
      } catch (e) {
        print('❌ فشل جدولة الإشعار المحدث: $e');
      }
    }
  }

  Future<void> deleteTodo(String id) async {
    try {
      await NotificationService().cancelNotification(_notifId(id));
    } catch (e) {
      print('⚠️ فشل إلغاء الإشعار للمهمة $id: $e');
    }
    await box.delete(id);
  }

  Future<void> deleteCompletedTodos() async {
    final completedIds = box.values
        .where((todo) => todo.isCompleted)
        .map((todo) => todo.id)
        .toList();

    for (final id in completedIds) {
      try {
        await NotificationService().cancelNotification(_notifId(id));
      } catch (e) {
        print('⚠️ فشل إلغاء الإشعار للمهمة المكتملة $id: $e');
      }
      await box.delete(id);
    }
  }

  Future<void> toggleTodoStatus(String id) async {
    final todo = box.get(id);
    if (todo != null) {
      todo.isCompleted = !todo.isCompleted;
      todo.completedAt = todo.isCompleted ? DateTime.now() : null;
      await todo.save();

      if (todo.isCompleted) {
        try {
          await NotificationService().cancelNotification(_notifId(id));
        } catch (e) {
          print('⚠️ فشل إلغاء الإشعار بعد الإكمال $id: $e');
        }
      } else if (todo.hasReminder &&
          todo.dueDate != null &&
          todo.dueDate!.isAfter(DateTime.now())) {
        try {
          await NotificationService().scheduleNotification(
            id: _notifId(id),
            title: 'مهمة منتظره',
            body: 'المهمة "${todo.title}"',
            scheduledTime: todo.dueDate!,
          );
          print('✅ تم جدولة إشعار جديد بعد إعادة فتح المهمة $id');
        } catch (e) {
          print('❌ فشل جدولة الإشعار بعد إعادة الفتح: $e');
        }
      }
    }
  }

  Future<void> updateTodoPriority(String id, Priority priority) async {
    final todo = box.get(id);
    if (todo != null) {
      todo.priority = priority;
      await todo.save();
    }
  }

  List<TodoItem> getAllTodos() {
    return box.values.toList()
      ..sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }

        final priorityCompare = b.priority.index.compareTo(a.priority.index);
        if (priorityCompare != 0) return priorityCompare;

        if (a.dueDate != null && b.dueDate != null) {
          return a.dueDate!.compareTo(b.dueDate!);
        } else if (a.dueDate != null) {
          return -1;
        } else if (b.dueDate != null) {
          return 1;
        }

        return b.createdAt.compareTo(a.createdAt);
      });
  }

  List<TodoItem> getActiveTodos() {
    return box.values
        .where((todo) => !todo.isCompleted)
        .toList()
      ..sort((a, b) {
        final priorityCompare = b.priority.index.compareTo(a.priority.index);
        if (priorityCompare != 0) return priorityCompare;

        if (a.dueDate != null && b.dueDate != null) {
          return a.dueDate!.compareTo(b.dueDate!);
        } else if (a.dueDate != null) {
          return -1;
        } else if (b.dueDate != null) {
          return 1;
        }

        return b.createdAt.compareTo(a.createdAt);
      });
  }

  List<TodoItem> getCompletedTodos() {
    return box.values
        .where((todo) => todo.isCompleted)
        .toList()
      ..sort((a, b) => (b.completedAt ?? b.createdAt)
          .compareTo(a.completedAt ?? a.createdAt));
  }

  List<TodoItem> getTodosByPriority(Priority priority) {
    return box.values
        .where((todo) => todo.priority == priority && !todo.isCompleted)
        .toList();
  }

  List<TodoItem> getTodayTodos() {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);

    return box.values
        .where((todo) =>
            !todo.isCompleted &&
            todo.dueDate != null &&
            todo.dueDate!.isAfter(todayStart) &&
            todo.dueDate!.isBefore(todayEnd))
        .toList()
      ..sort((a, b) => a.priority.index.compareTo(b.priority.index));
  }

  Map<Priority, int> getPriorityStatistics() {
    final activeTodos = getActiveTodos();
    return {
      Priority.urgent:
          activeTodos.where((t) => t.priority == Priority.urgent).length,
      Priority.high:
          activeTodos.where((t) => t.priority == Priority.high).length,
      Priority.medium:
          activeTodos.where((t) => t.priority == Priority.medium).length,
      Priority.low:
          activeTodos.where((t) => t.priority == Priority.low).length,
    };
  }

  int getTotalCount() => box.length;
  int getActiveCount() => getActiveTodos().length;
  int getCompletedCount() => getCompletedTodos().length;
}
