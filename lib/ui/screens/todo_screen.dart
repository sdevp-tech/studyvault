// todo_screen.dart - كود كامل مع دعم الترجمة وتعديلات الإشعارات (بما في ذلك تحسينات Gemini AI)
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../../models/todo_model.dart';
import '../../services/todo_service.dart';
import '../widgets/empty_state.dart';
import '../theme/app_theme.dart';
import '../../services/notification_service.dart';
import '../l10n/app_localizations.dart';

class TodoScreen extends StatefulWidget {
  const TodoScreen({Key? key}) : super(key: key);

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TodoService todoService;
  late TabController _tabController;
  List<TodoItem> _todos = [];
  String _searchQuery = '';

  List<String> _tabs = [];

  @override
  void initState() {
    super.initState();
    final box = Hive.box<TodoItem>('todos_box');
    todoService = TodoService(box);
    _tabController = TabController(length: 5, vsync: this);
    _loadTodos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final local = AppLocalizations.of(context);
    _tabs = [
      local.translate('all'),
      local.translate('urgent'),
      local.translate('high'),
      local.translate('medium'),
      local.translate('low'),
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTodos() async {
    setState(() {
      _todos = todoService.getAllTodos();
    });
  }

  List<TodoItem> _getFilteredTodos() {
    if (_searchQuery.isEmpty) {
      return _todos;
    }
    final query = _searchQuery.toLowerCase();
    return _todos.where((todo) {
      return todo.title.toLowerCase().contains(query) ||
          (todo.description ?? '').toLowerCase().contains(query);
    }).toList();
  }

  List<TodoItem> _getTabTodos(int tabIndex) {
    final filtered = _getFilteredTodos();
    final activeTodos = filtered.where((todo) => !todo.isCompleted).toList();

    switch (tabIndex) {
      case 0:
        return filtered;
      case 1:
        return activeTodos.where((todo) => todo.priority == Priority.urgent).toList();
      case 2:
        return activeTodos.where((todo) => todo.priority == Priority.high).toList();
      case 3:
        return activeTodos.where((todo) => todo.priority == Priority.medium).toList();
      case 4:
        return activeTodos.where((todo) => todo.priority == Priority.low).toList();
      default:
        return filtered;
    }
  }

  Future<void> _addTodo() async {
    final local = AppLocalizations.of(context);
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddTodoDialog(),
    );

    if (result != null && result.isNotEmpty) {
      try {
        // 1. حفظ المعرفات الموجودة قبل الإضافة
        final oldIds = _todos.map((t) => t.id).toSet();

        await todoService.addTodo(
          title: result['title'],
          description: result['description'],
          priority: result['priority'],
          dueDate: result['dueDate'],
          hasReminder: result['hasReminder'] ?? false,
        );
        await _loadTodos();

        // 2. العثور على المهمة الجديدة (الموجودة في القائمة الجديدة وليس في القديمة)
        final newTodos = _todos.where((t) => !oldIds.contains(t.id)).toList();

        if (newTodos.isNotEmpty) {
          final addedTodo = newTodos.first;

          // 3. توليد معرف آمن للإشعار
          final safeNotificationId = addedTodo.id.hashCode & 0x7FFFFFFF;

          // 4. جدولة التذكير فقط إذا كان مناسباً
          if (addedTodo.hasReminder &&
              addedTodo.dueDate != null &&
              addedTodo.dueDate!.isAfter(DateTime.now()) &&
              !addedTodo.isCompleted) {
            await NotificationService().cancelNotification(safeNotificationId);
            await NotificationService().scheduleNotification(
              id: safeNotificationId,
              title: '${local.translate('reminder_for_todo')}: ${addedTodo.title}',
              body: addedTodo.description ?? local.translate('todo_due'),
              scheduledTime: addedTodo.dueDate!,
            );
          } else if (addedTodo.hasReminder && addedTodo.dueDate != null && addedTodo.dueDate!.isBefore(DateTime.now())) {
            print('⚠️ [TodoScreen] المهمة مضى وقتها، لن يتم جدولة إشعار');
          }
        }
      } catch (e) {
        debugPrint('❌ [TodoScreen] فشل إضافة المهمة: $e');
      }
    }
  }

  Future<void> _editTodo(TodoItem todo) async {
    final local = AppLocalizations.of(context);
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddTodoDialog(todo: todo),
    );

    if (result != null && result.isNotEmpty) {
      // إلغاء التذكير القديم باستخدام معرف آمن
      final safeNotificationId = todo.id.hashCode & 0x7FFFFFFF;
      await NotificationService().cancelNotification(safeNotificationId);

      todo.title = result['title'];
      todo.description = result['description'];
      todo.priority = result['priority'];
      todo.dueDate = result['dueDate'];
      todo.hasReminder = result['hasReminder'] ?? false;
      await todoService.updateTodo(todo);
      await _loadTodos();

      // إعادة جدولة التذكير الجديد إذا كان مناسباً
      if (todo.hasReminder &&
          todo.dueDate != null &&
          todo.dueDate!.isAfter(DateTime.now()) &&
          !todo.isCompleted) {
        await NotificationService().scheduleNotification(
          id: safeNotificationId,
          title: '${local.translate('reminder_for_todo')}: ${todo.title}',
          body: todo.description ?? local.translate('todo_due'),
          scheduledTime: todo.dueDate!,
        );
      }
    }
  }

  Future<void> _deleteTodo(TodoItem todo) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_todo')),
        content: Text(local.translate('confirm_delete_todo')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(local.translate('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(local.translate('delete'))),
        ],
      ),
    );

    if (confirm == true) {
      final safeNotificationId = todo.id.hashCode & 0x7FFFFFFF;
      await NotificationService().cancelNotification(safeNotificationId);
      await todoService.deleteTodo(todo.id);
      if (mounted) await _loadTodos();
    }
  }

  Future<void> _deleteAllCompleted() async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_completed_todos')),
        content: Text(local.translate('confirm_delete_completed')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(local.translate('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(local.translate('delete_all'))),
        ],
      ),
    );

    if (confirm == true) {
      await todoService.deleteCompletedTodos();
      await _loadTodos();
    }
  }

  Color _getPriorityColor(Priority priority) {
    final scheme = Theme.of(context).colorScheme;
    switch (priority) {
      case Priority.urgent:
        return scheme.error;
      case Priority.high:
        return scheme.warning;
      case Priority.medium:
        return scheme.secondary;
      case Priority.low:
        return scheme.success;
    }
  }

  String _getPriorityText(Priority priority) {
    final local = AppLocalizations.of(context);
    switch (priority) {
      case Priority.urgent:
        return local.translate('urgent');
      case Priority.high:
        return local.translate('high');
      case Priority.medium:
        return local.translate('medium');
      case Priority.low:
        return local.translate('low');
    }
  }

  IconData _getPriorityIcon(Priority priority) {
    switch (priority) {
      case Priority.urgent:
        return Icons.error;
      case Priority.high:
        return Icons.warning;
      case Priority.medium:
        return Icons.info;
      case Priority.low:
        return Icons.low_priority;
    }
  }

  Widget _buildTodoCard(TodoItem todo) {
    final local = AppLocalizations.of(context);
    final isOverdue = todo.dueDate != null &&
        todo.dueDate!.isBefore(DateTime.now()) &&
        !todo.isCompleted;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdue ? scheme.error : Colors.transparent,
          width: isOverdue ? 2 : 0,
        ),
      ),
      color: todo.isCompleted ? scheme.surface.withValues(alpha: 0.6) : null,
      child: Dismissible(
        key: Key(todo.id),
        direction: DismissDirection.endToStart,
        background: Container(
          decoration: BoxDecoration(
            color: scheme.error,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          child: const Icon(Icons.delete, color: Colors.white, size: 30),
        ),
        confirmDismiss: (direction) async {
          return await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(local.translate('delete_todo')),
              content: Text(local.translate('confirm_delete_todo')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(local.translate('cancel'))),
                ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(local.translate('delete'))),
              ],
            ),
          );
        },
        onDismissed: (direction) async {
          final safeNotificationId = todo.id.hashCode & 0x7FFFFFFF;
          await NotificationService().cancelNotification(safeNotificationId);
          await todoService.deleteTodo(todo.id);
          if (mounted) await _loadTodos();
        },
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editTodo(todo),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Checkbox(
                  value: todo.isCompleted,
                  onChanged: (value) async {
                    await todoService.toggleTodoStatus(todo.id);
                    final safeNotificationId = todo.id.hashCode & 0x7FFFFFFF;
                    if (todo.isCompleted) {
                      await NotificationService().cancelNotification(safeNotificationId);
                    } else if (todo.hasReminder && todo.dueDate != null && todo.dueDate!.isAfter(DateTime.now())) {
                      await NotificationService().scheduleNotification(
                        id: safeNotificationId,
                        title: '${local.translate('reminder_for_todo')}: ${todo.title}',
                        body: todo.description ?? local.translate('todo_due'),
                        scheduledTime: todo.dueDate!,
                      );
                    }
                    await _loadTodos();
                  },
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                          color: todo.isCompleted
                              ? scheme.onSurface.withValues(alpha: 0.6)
                              : null,
                        ),
                      ),
                      if (todo.description != null && todo.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            todo.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withValues(alpha: 0.7),
                              decoration: todo.isCompleted ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getPriorityColor(todo.priority).withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: _getPriorityColor(todo.priority),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getPriorityIcon(todo.priority),
                                  size: 14,
                                  color: _getPriorityColor(todo.priority),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getPriorityText(todo.priority),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _getPriorityColor(todo.priority),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (todo.dueDate != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isOverdue
                                    ? scheme.error.withValues(alpha: 0.1)
                                    : scheme.surface.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: isOverdue
                                        ? scheme.error
                                        : scheme.onSurface.withValues(alpha: 0.6),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('yyyy/MM/dd').format(todo.dueDate!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isOverdue
                                          ? scheme.error
                                          : scheme.onSurface.withValues(alpha: 0.6),
                                      fontWeight: isOverdue ? FontWeight.bold : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (todo.isCompleted && todo.completedAt != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.success.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, size: 14, color: scheme.success),
                                  const SizedBox(width: 4),
                                  Text(
                                    DateFormat('yyyy/MM/dd').format(todo.completedAt!),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (todo.hasReminder && todo.dueDate != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: scheme.secondary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.notifications_active,
                                      size: 14, color: Colors.blue),
                                  const SizedBox(width: 4),
                                  Text(
                                    local.translate('reminder'),
                                    style: const TextStyle(fontSize: 12, color: Colors.blue),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton(
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, color: scheme.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('edit')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'priority',
                      child: Row(
                        children: [
                          Icon(Icons.flag, color: scheme.warning, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('change_priority')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: scheme.error, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('delete')),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    switch (value) {
                      case 'edit':
                        _editTodo(todo);
                        break;
                      case 'priority':
                        _showPriorityDialog(todo);
                        break;
                      case 'delete':
                        _deleteTodo(todo);
                        break;
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showPriorityDialog(TodoItem todo) async {
    final local = AppLocalizations.of(context);
    final priority = await showDialog<Priority>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('change_priority')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.error, color: Theme.of(context).colorScheme.error),
              title: Text(local.translate('urgent')),
              onTap: () => Navigator.pop(context, Priority.urgent),
            ),
            ListTile(
              leading: Icon(Icons.warning, color: Theme.of(context).colorScheme.warning),
              title: Text(local.translate('high')),
              onTap: () => Navigator.pop(context, Priority.high),
            ),
            ListTile(
              leading: Icon(Icons.info, color: Theme.of(context).colorScheme.secondary),
              title: Text(local.translate('medium')),
              onTap: () => Navigator.pop(context, Priority.medium),
            ),
            ListTile(
              leading: Icon(Icons.low_priority, color: Theme.of(context).colorScheme.success),
              title: Text(local.translate('low')),
              onTap: () => Navigator.pop(context, Priority.low),
            ),
          ],
        ),
      ),
    );

    if (priority != null) {
      await todoService.updateTodoPriority(todo.id, priority);
      await _loadTodos();
    }
  }

  Widget _buildStatsCard() {
    final local = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final stats = todoService.getPriorityStatistics();
    final totalActive = todoService.getActiveCount();
    final totalCompleted = todoService.getCompletedCount();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              local.translate('todo_stats'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCircle(
                    count: totalActive,
                    label: local.translate('pending'),
                    color: scheme.secondary,
                    icon: Icons.pending_actions,
                  ),
                ),
                Expanded(
                  child: _buildStatCircle(
                    count: totalCompleted,
                    label: local.translate('completed'),
                    color: scheme.success,
                    icon: Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              local.translate('priority_distribution'),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPriorityStat(count: stats[Priority.urgent] ?? 0, priority: Priority.urgent),
                _buildPriorityStat(count: stats[Priority.high] ?? 0, priority: Priority.high),
                _buildPriorityStat(count: stats[Priority.medium] ?? 0, priority: Priority.medium),
                _buildPriorityStat(count: stats[Priority.low] ?? 0, priority: Priority.low),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle({
    required int count,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(height: 4),
                Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildPriorityStat({required int count, required Priority priority}) {
    final color = _getPriorityColor(priority);
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _getPriorityText(priority),
          style: TextStyle(fontSize: 10, color: color),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final local = AppLocalizations.of(context);
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              title: Text(local.translate('todo_list')),
              floating: true,
              snap: true,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(110),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: local.translate('search_todos'),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                        },
                      ),
                    ),
                    TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: List.generate(_tabs.length, (index) {
            final tabTodos = _getTabTodos(index);
            return RefreshIndicator(
              onRefresh: _loadTodos,
              child: Builder(
                builder: (context) {
                  return tabTodos.isEmpty
                      ? EmptyState(
                          title: local.translate('no_todos'),
                          message: index == 0
                              ? local.translate('tap_plus_to_add_todo')
                              : local.translate('no_todos_in_section'),
                          icon: Icons.checklist,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: index == 0 ? tabTodos.length + 1 : tabTodos.length,
                          itemBuilder: (context, i) {
                            if (index == 0 && i == 0) {
                              return _buildStatsCard();
                            }
                            final actualIndex = index == 0 ? i - 1 : i;
                            return _buildTodoCard(tabTodos[actualIndex]);
                          },
                        );
                },
              ),
            );
          }),
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'add_todo',
            onPressed: _addTodo,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 12),
          if (todoService.getCompletedCount() > 0)
            FloatingActionButton.extended(
              heroTag: 'clear_completed',
              onPressed: _deleteAllCompleted,
              icon: const Icon(Icons.delete_sweep),
              label: Text(local.translate('clear_completed')),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
        ],
      ),
    );
  }
}

class AddTodoDialog extends StatefulWidget {
  final TodoItem? todo;

  const AddTodoDialog({Key? key, this.todo}) : super(key: key);

  @override
  State<AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends State<AddTodoDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late Priority _priority;
  DateTime? _dueDate;
  late bool _hasReminder;

  @override
  void initState() {
    super.initState();
    if (widget.todo != null) {
      _titleController = TextEditingController(text: widget.todo!.title);
      _descriptionController = TextEditingController(text: widget.todo!.description);
      _priority = widget.todo!.priority;
      _dueDate = widget.todo!.dueDate;
      _hasReminder = widget.todo!.hasReminder;
    } else {
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _priority = Priority.medium;
      _dueDate = null;
      _hasReminder = false;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _selectTime() async {
    if (_dueDate == null) _dueDate = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate!),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(
          _dueDate!.year,
          _dueDate!.month,
          _dueDate!.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.todo != null ? local.translate('edit_todo') : local.translate('add_todo')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: local.translate('todo_title'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return local.translate('title_required');
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: local.translate('description_optional'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Priority>(
                initialValue: _priority,
                decoration: InputDecoration(
                  labelText: local.translate('todo_priority'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: Priority.urgent,
                    child: Row(children: [
                      const Icon(Icons.error, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(local.translate('urgent'))
                    ]),
                  ),
                  DropdownMenuItem(
                    value: Priority.high,
                    child: Row(children: [
                      const Icon(Icons.warning, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(local.translate('high'))
                    ]),
                  ),
                  DropdownMenuItem(
                    value: Priority.medium,
                    child: Row(children: [
                      const Icon(Icons.info, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(local.translate('medium'))
                    ]),
                  ),
                  DropdownMenuItem(
                    value: Priority.low,
                    child: Row(children: [
                      const Icon(Icons.low_priority, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(local.translate('low'))
                    ]),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _priority = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(local.translate('due_date_optional'),
                      style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectDate,
                          icon: const Icon(Icons.calendar_today),
                          label: Text(_dueDate != null
                              ? DateFormat.yMd().format(_dueDate!)
                              : local.translate('pick_date')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectTime,
                          icon: const Icon(Icons.access_time),
                          label: Text(_dueDate != null
                              ? DateFormat.jm().format(_dueDate!)
                              : local.translate('pick_time')),
                        ),
                      ),
                      if (_dueDate != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() => _dueDate = null);
                          },
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(local.translate('enable_reminder')),
                value: _hasReminder,
                onChanged: (value) {
                  setState(() => _hasReminder = value);
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(local.translate('cancel')),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'title': _titleController.text,
                'description': _descriptionController.text.isEmpty ? null : _descriptionController.text,
                'priority': _priority,
                'dueDate': _dueDate,
                'hasReminder': _hasReminder,
              });
            }
          },
          child: Text(local.translate('save')),
        ),
      ],
    );
  }
}