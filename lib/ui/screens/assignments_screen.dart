// assignments_screen.dart - كود كامل مع دعم الترجمة وتعديلات الإشعارات (بما في ذلك تحسينات Gemini AI)
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import '../../models/assignment_model.dart';
import '../../services/assignment_service.dart';
import '../widgets/empty_state.dart';
import '../theme/app_theme.dart';
import '../../services/notification_service.dart';
import '../l10n/app_localizations.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({Key? key}) : super(key: key);

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AssignmentService assignmentService;
  late TabController _tabController;
  List<Assignment> _assignments = [];
  Map<AssignmentStatus, int> _stats = {};
  String _searchQuery = '';

  final List<AssignmentStatus> _tabs = [
    AssignmentStatus.pending,
    AssignmentStatus.inProgress,
    AssignmentStatus.completed,
    AssignmentStatus.overdue,
  ];

  @override
  void initState() {
    super.initState();
    final box = Hive.box<Assignment>('assignments_box');
    assignmentService = AssignmentService(box);
    _tabController = TabController(length: 5, vsync: this);
    _loadAssignments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAssignments() async {
    assignmentService.updateOverdueAssignments();
    setState(() {
      _assignments = assignmentService.getAllAssignments();
      _stats = assignmentService.getStatistics();
    });
  }

  List<Assignment> _getFilteredAssignments() {
    if (_searchQuery.isEmpty) {
      return _assignments;
    }
    final query = _searchQuery.toLowerCase();
    return _assignments.where((a) {
      return a.title.toLowerCase().contains(query) ||
          (a.description ?? '').toLowerCase().contains(query) ||
          (a.subject ?? '').toLowerCase().contains(query) ||
          (a.lecture ?? '').toLowerCase().contains(query);
    }).toList();
  }

  List<Assignment> _getTabAssignments(int index) {
    final filtered = _getFilteredAssignments();
    if (index == 0) return filtered;

    final status = _tabs[index - 1];
    return filtered.where((a) => a.status == status).toList();
  }

  Future<void> _addAssignment() async {
    final local = AppLocalizations.of(context);
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddAssignmentDialog(),
    );

    if (result != null && result.isNotEmpty) {
      try {
        // 1. حفظ المعرفات الموجودة قبل الإضافة
        final oldIds = _assignments.map((a) => a.id).toSet();

        await assignmentService.addAssignment(
          title: result['title'],
          description: result['description'],
          type: result['type'],
          dueDate: result['dueDate'],
          field: result['field'],
          year: result['year'],
          subject: result['subject'],
          lecture: result['lecture'],
          hasReminder: result['hasReminder'],
        );
        await _loadAssignments();

        // 2. العثور على التكليف الجديد (الموجود في القائمة الجديدة وليس في القديمة)
        final newAssignments = _assignments.where((a) => !oldIds.contains(a.id)).toList();

        if (newAssignments.isNotEmpty) {
          final addedAssignment = newAssignments.first;

          // 3. توليد معرف آمن للإشعار (لا يتجاوز 32-bit)
          final safeNotificationId = addedAssignment.id.hashCode & 0x7FFFFFFF;

          // 4. جدولة التذكير فقط إذا كان مناسباً
          if (addedAssignment.hasReminder &&
              addedAssignment.dueDate.isAfter(DateTime.now()) &&
              addedAssignment.status != AssignmentStatus.completed) {
            await NotificationService().scheduleNotification(
              id: safeNotificationId,
              title: '${local.translate('reminder_for')}: ${addedAssignment.title}',
              body: addedAssignment.description ?? local.translate('due_soon'),
              scheduledTime: addedAssignment.dueDate,
            );
          } else if (addedAssignment.hasReminder && addedAssignment.dueDate.isBefore(DateTime.now())) {
            print('⚠️ [AssignmentsScreen] التكليف مضى وقت استحقاقه، لن يتم جدولة إشعار');
          }
        }
      } catch (e) {
        debugPrint('❌ [AssignmentsScreen] فشل إضافة التكليف: $e');
      }
    }
  }

  Future<void> _editAssignment(Assignment assignment) async {
    final local = AppLocalizations.of(context);
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (_) => AddAssignmentDialog(assignment: assignment),
    );

    if (result != null && result.isNotEmpty) {
      // إلغاء التذكير القديم باستخدام معرف آمن
      final safeNotificationId = assignment.id.hashCode & 0x7FFFFFFF;
      await NotificationService().cancelNotification(safeNotificationId);

      assignment.title = result['title'];
      assignment.description = result['description'];
      assignment.type = result['type'];
      assignment.dueDate = result['dueDate'];
      assignment.field = result['field'];
      assignment.year = result['year'];
      assignment.subject = result['subject'];
      assignment.lecture = result['lecture'];
      assignment.hasReminder = result['hasReminder'];
      await assignment.save();
      await _loadAssignments();

      // إعادة جدولة التذكير الجديد إذا كان مناسباً
      if (assignment.hasReminder &&
          assignment.dueDate.isAfter(DateTime.now()) &&
          assignment.status != AssignmentStatus.completed) {
        await NotificationService().scheduleNotification(
          id: safeNotificationId,
          title: '${local.translate('reminder_for')}: ${assignment.title}',
          body: assignment.description ?? local.translate('due_soon'),
          scheduledTime: assignment.dueDate,
        );
      }
    }
  }

  Future<void> _deleteAssignment(Assignment assignment) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_assignment')),
        content: Text(local.translate('confirm_delete')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(local.translate('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final safeNotificationId = assignment.id.hashCode & 0x7FFFFFFF;
      await NotificationService().cancelNotification(safeNotificationId);
      await assignmentService.deleteAssignment(assignment.id);
      await _loadAssignments();
    }
  }

  Future<void> _changeStatus(Assignment assignment, AssignmentStatus status) async {
    await assignmentService.changeStatus(assignment.id, status);

    final safeNotificationId = assignment.id.hashCode & 0x7FFFFFFF;
    if (status == AssignmentStatus.completed) {
      await NotificationService().cancelNotification(safeNotificationId);
    } else if (assignment.hasReminder && assignment.dueDate.isAfter(DateTime.now())) {
      final local = AppLocalizations.of(context);
      await NotificationService().scheduleNotification(
        id: safeNotificationId,
        title: '${local.translate('reminder_for')}: ${assignment.title}',
        body: assignment.description ?? local.translate('due_soon'),
        scheduledTime: assignment.dueDate,
      );
    }

    await _loadAssignments();
  }

  Color _getStatusColor(AssignmentStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case AssignmentStatus.pending:
        return scheme.warning;
      case AssignmentStatus.inProgress:
        return scheme.secondary;
      case AssignmentStatus.completed:
        return scheme.success;
      case AssignmentStatus.overdue:
        return scheme.error;
    }
  }

  String _getStatusText(AssignmentStatus status) {
    final local = AppLocalizations.of(context);
    switch (status) {
      case AssignmentStatus.pending:
        return local.translate('pending');
      case AssignmentStatus.inProgress:
        return local.translate('in_progress');
      case AssignmentStatus.completed:
        return local.translate('completed');
      case AssignmentStatus.overdue:
        return local.translate('overdue');
    }
  }

  String _getTypeText(AssignmentType type) {
    final local = AppLocalizations.of(context);
    switch (type) {
      case AssignmentType.assignment:
        return local.translate('assignment');
      case AssignmentType.exam:
        return local.translate('exam');
      case AssignmentType.reminder:
        return local.translate('reminder');
    }
  }

  IconData _getTypeIcon(AssignmentType type) {
    switch (type) {
      case AssignmentType.assignment:
        return Icons.assignment;
      case AssignmentType.exam:
        return Icons.quiz;
      case AssignmentType.reminder:
        return Icons.notifications;
    }
  }

  Widget _buildAssignmentCard(Assignment assignment) {
    final local = AppLocalizations.of(context);
    final isOverdue = assignment.status == AssignmentStatus.overdue;
    final isCompleted = assignment.status == AssignmentStatus.completed;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: isCompleted
          ? scheme.success.withValues(alpha: 0.05)
          : isOverdue
              ? scheme.error.withValues(alpha: 0.05)
              : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editAssignment(assignment),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getTypeIcon(assignment.type),
                    color: _getStatusColor(assignment.status),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      assignment.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted ? scheme.onSurface.withValues(alpha: 0.6) : null,
                      ),
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      if (assignment.status != AssignmentStatus.completed)
                        PopupMenuItem(
                          value: 'complete',
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: scheme.success),
                              const SizedBox(width: 8),
                              Text(local.translate('mark_completed')),
                            ],
                          ),
                        ),
                      if (assignment.status != AssignmentStatus.inProgress)
                        PopupMenuItem(
                          value: 'progress',
                          child: Row(
                            children: [
                              Icon(Icons.autorenew, color: scheme.secondary),
                              const SizedBox(width: 8),
                              Text(local.translate('mark_in_progress')),
                            ],
                          ),
                        ),
                      if (assignment.status != AssignmentStatus.pending)
                        PopupMenuItem(
                          value: 'pending',
                          child: Row(
                            children: [
                              Icon(Icons.pending, color: scheme.warning),
                              const SizedBox(width: 8),
                              Text(local.translate('mark_pending')),
                            ],
                          ),
                        ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.blue),
                            const SizedBox(width: 8),
                            Text(local.translate('edit')),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red),
                            const SizedBox(width: 8),
                            Text(local.translate('delete')),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'complete':
                          _changeStatus(assignment, AssignmentStatus.completed);
                          break;
                        case 'progress':
                          _changeStatus(assignment, AssignmentStatus.inProgress);
                          break;
                        case 'pending':
                          _changeStatus(assignment, AssignmentStatus.pending);
                          break;
                        case 'edit':
                          _editAssignment(assignment);
                          break;
                        case 'delete':
                          _deleteAssignment(assignment);
                          break;
                      }
                    },
                  ),
                ],
              ),
              if (assignment.description != null && assignment.description!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    assignment.description!,
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_getTypeText(assignment.type)),
                    backgroundColor: scheme.secondary.withValues(alpha: 0.1),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  Chip(
                    label: Text(
                      _getStatusText(assignment.status),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: _getStatusColor(assignment.status),
                  ),
                  Chip(
                    label: Text(
                      DateFormat.yMd().format(assignment.dueDate),
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: isOverdue
                        ? scheme.error.withValues(alpha: 0.1)
                        : scheme.surface.withValues(alpha: 0.6),
                  ),
                  if (assignment.subject != null)
                    Chip(
                      label: Text(
                        assignment.subject!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: scheme.success.withValues(alpha: 0.1),
                    ),
                  if (assignment.lecture != null)
                    Chip(
                      label: Text(
                        assignment.lecture!,
                        style: const TextStyle(fontSize: 12),
                      ),
                      backgroundColor: Colors.purple.withValues(alpha: 0.1),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${local.translate('due_date')}: ${DateFormat.yMMMd('ar').add_jm().format(assignment.dueDate)}',
                style: TextStyle(
                  fontSize: 12,
                  color: isOverdue ? scheme.error : scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: isOverdue ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final local = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              local.translate('assignment_stats'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  count: _stats[AssignmentStatus.pending] ?? 0,
                  label: local.translate('pending'),
                  color: scheme.warning,
                ),
                _buildStatItem(
                  count: _stats[AssignmentStatus.inProgress] ?? 0,
                  label: local.translate('in_progress'),
                  color: scheme.secondary,
                ),
                _buildStatItem(
                  count: _stats[AssignmentStatus.completed] ?? 0,
                  label: local.translate('completed'),
                  color: scheme.success,
                ),
                _buildStatItem(
                  count: _stats[AssignmentStatus.overdue] ?? 0,
                  label: local.translate('overdue'),
                  color: scheme.error,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({required int count, required String label, required Color color}) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: color),
          ),
          child: Center(
            child: Text(
              count.toString(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 10),
          textAlign: TextAlign.center,
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
              title: Text(local.translate('assignments')),
              floating: true,
              snap: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: local.translate('add_assignment'),
                  onPressed: _addAssignment,
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(110),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: local.translate('search_assignments'),
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
                      tabs: [
                        Tab(text: local.translate('all')),
                        Tab(text: local.translate('pending')),
                        Tab(text: local.translate('in_progress')),
                        Tab(text: local.translate('completed')),
                        Tab(text: local.translate('overdue')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: List.generate(5, (index) {
            final tabAssignments = _getTabAssignments(index);
            return RefreshIndicator(
              onRefresh: _loadAssignments,
              child: Builder(
                builder: (context) {
                  return tabAssignments.isEmpty
                      ? EmptyState(
                          title: local.translate('no_assignments'),
                          message: index == 0
                              ? local.translate('tap_plus_to_add_assignment')
                              : local.translate('no_assignments_in_section'),
                          icon: Icons.assignment,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(top: 8),
                          itemCount: index == 0 ? tabAssignments.length + 1 : tabAssignments.length,
                          itemBuilder: (context, i) {
                            if (index == 0 && i == 0) {
                              return _buildStatsCard();
                            }
                            final actualIndex = index == 0 ? i - 1 : i;
                            return _buildAssignmentCard(tabAssignments[actualIndex]);
                          },
                        );
                },
              ),
            );
          }),
        ),
      ),
    );
  }
}

class AddAssignmentDialog extends StatefulWidget {
  final Assignment? assignment;

  const AddAssignmentDialog({Key? key, this.assignment}) : super(key: key);

  @override
  State<AddAssignmentDialog> createState() => _AddAssignmentDialogState();
}

class _AddAssignmentDialogState extends State<AddAssignmentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late AssignmentType _type;
  late DateTime _dueDate;
  late bool _hasReminder;
  String? _selectedField;
  String? _selectedYear;
  String? _selectedSubject;
  String? _selectedLecture;

  @override
  void initState() {
    super.initState();
    if (widget.assignment != null) {
      _titleController = TextEditingController(text: widget.assignment!.title);
      _descriptionController = TextEditingController(text: widget.assignment!.description);
      _type = widget.assignment!.type;
      _dueDate = widget.assignment!.dueDate;
      _hasReminder = widget.assignment!.hasReminder;
      _selectedField = widget.assignment!.field;
      _selectedYear = widget.assignment!.year;
      _selectedSubject = widget.assignment!.subject;
      _selectedLecture = widget.assignment!.lecture;
    } else {
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _type = AssignmentType.assignment;
      _dueDate = DateTime.now().add(const Duration(days: 7));
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
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDate),
    );
    if (picked != null) {
      setState(() {
        _dueDate = DateTime(
          _dueDate.year,
          _dueDate.month,
          _dueDate.day,
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
      title: Text(widget.assignment != null 
          ? local.translate('edit_assignment') 
          : local.translate('add_assignment')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: local.translate('assignment_title'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return local.translate('title_required');
                  }
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
              DropdownButtonFormField<AssignmentType>(
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: local.translate('assignment_type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: AssignmentType.assignment,
                    child: Text(local.translate('assignment')),
                  ),
                  DropdownMenuItem(
                    value: AssignmentType.exam,
                    child: Text(local.translate('exam')),
                  ),
                  DropdownMenuItem(
                    value: AssignmentType.reminder,
                    child: Text(local.translate('reminder')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _type = value);
                  }
                },
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    local.translate('due_date_label'),
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectDate,
                          icon: const Icon(Icons.calendar_today),
                          label: Text(DateFormat.yMd().format(_dueDate)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectTime,
                          icon: const Icon(Icons.access_time),
                          label: Text(DateFormat.jm().format(_dueDate)),
                        ),
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
                'description': _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
                'type': _type,
                'dueDate': _dueDate,
                'hasReminder': _hasReminder,
                'field': _selectedField,
                'year': _selectedYear,
                'subject': _selectedSubject,
                'lecture': _selectedLecture,
              });
            }
          },
          child: Text(local.translate('save')),
        ),
      ],
    );
  }
}