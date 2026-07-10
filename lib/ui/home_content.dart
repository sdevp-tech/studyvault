import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../services/storage_service.dart';
import '../../models/settings_model.dart';
import '../../models/assignment_model.dart';
import '../../models/todo_model.dart';
import '../ui/screens/assignments_screen.dart';
import '../ui/screens/todo_screen.dart';
import '../ui/screens/search_screen.dart';
import '../ui/screens/field_screen.dart';
import '../ui/screens/lecture_list_screen.dart';
import '../ui/screens/copilot_screen.dart';
import './widgets/quick_access_card.dart';
import '../ui/screens/annotation_screen.dart';
import '../ui/screens/spaced_repetition_screen.dart';
import './widgets/lectures_quick_access_modal.dart';
import '../ui/screens/settings_screen.dart';
import 'l10n/app_localizations.dart';

import './theme/app_theme.dart';

class HomeContent extends StatefulWidget {
  const HomeContent({Key? key}) : super(key: key);

  @override
  State<HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<HomeContent> with AutomaticKeepAliveClientMixin {
  final StorageService storage = StorageService();
  final RefreshController _refreshController = RefreshController(initialRefresh: false);

  List<String> fields = [];
  AppSettings? settings;

  int pendingAssignments = 0;
  int pendingTodos = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _onRefresh() async {
    await _loadData();
    _refreshController.refreshCompleted();
  }

  Future<void> _loadData() async {
    try {
      final fieldsList = await storage.listFields();
      final settingsBox = Hive.box<AppSettings>('settings_box');
      final assignmentsBox = Hive.box<Assignment>('assignments_box');
      final todosBox = Hive.box<TodoItem>('todos_box');

      int assignmentsCount = 0;
      for (var i = 0; i < assignmentsBox.length; i++) {
        final assignment = assignmentsBox.getAt(i);
        if (assignment != null && assignment.status == AssignmentStatus.pending) {
          assignmentsCount++;
        }
      }

      int todosCount = 0;
      for (var i = 0; i < todosBox.length; i++) {
        final todo = todosBox.getAt(i);
        if (todo != null && !todo.isCompleted) {
          todosCount++;
        }
      }

      if (mounted) {
        setState(() {
          fields = fieldsList;
          settings = settingsBox.isNotEmpty ? settingsBox.getAt(0) : null;
          pendingAssignments = assignmentsCount;
          pendingTodos = todosCount;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
    }
  }

  // === دوال ذكية مساعدة للترجمة ===
  String _getFieldsTitle(AppLocalizations local) {
    if (settings != null && settings!.fieldsTitle.isNotEmpty && settings!.fieldsTitle != 'التخصصات') {
      return settings!.fieldsTitle;
    }
    return local.translate('fields');
  }

  String _getAssignmentsTitle(AppLocalizations local) {
    if (settings != null && settings!.assignmentsTitle.isNotEmpty && settings!.assignmentsTitle != 'التكاليف') {
      return settings!.assignmentsTitle;
    }
    return local.translate('assignments');
  }

  String _getTodoTitle(AppLocalizations local) {
    if (settings != null && settings!.todoTitle.isNotEmpty && settings!.todoTitle != 'قائمة المهام') {
      return settings!.todoTitle;
    }
    return local.translate('todo');
  }
  // ===================================

  Future<void> _openLecturesQuickAccess() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return LecturesQuickAccessModal(
              storage: storage,
              settings: settings,
              fields: fields,
              onSelectLecture: (field, year, subject) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LectureListScreen(
                      field: field,
                      year: year,
                      subject: subject,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _showFieldsDialog() async {
    final local = AppLocalizations.of(context);
    if (fields.isEmpty) {
      await _showAddFieldDialog();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _getFieldsTitle(local),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: _showAddFieldDialog,
                        tooltip: local.translate('add_field_tooltip'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: fields.length,
                    itemBuilder: (context, index) {
                      final field = fields[index];
                      return ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(field),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FieldScreen(field: field),
                            ),
                          ).then((_) => _loadData());
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAddFieldDialog() async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(local.translate('add_field').replaceFirst('{name}', _getFieldsTitle(local))),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: local.translate('field_name_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(local.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                if (controller.text.trim().isNotEmpty) {
                  try {
                    await storage.createSubjectFolder(
                      controller.text.trim(),
                      local.translate('default_year'),
                      local.translate('default_subject'),
                    );

                    Navigator.pop(context);
                    await _loadData();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(local.translate('field_added').replaceFirst('{name}', controller.text.trim())),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${local.translate('error_adding')}: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(local.translate('add')),
            ),
          ],
        );
      },
    );
  }

  Widget _buildWelcomeCard() {
    final local = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.school,
                    color: scheme.primary,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        local.translate('welcome'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        local.translate('organize_study'),
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  value: fields.length.toString(),
                  label: _getFieldsTitle(local),
                  color: scheme.primary,
                ),
                _buildStatItem(
                  value: pendingAssignments.toString(),
                  label: _getAssignmentsTitle(local),
                  color: scheme.warning,
                ),
                _buildStatItem(
                  value: pendingTodos.toString(),
                  label: _getTodoTitle(local),
                  color: scheme.success,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              value,
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
        ),
      ],
    );
  }

  Widget _buildQuickAccessSection() {
    final local = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            local.translate('quick_access'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: _getFieldsTitle(local),
                  icon: Icons.category,
                  color: scheme.primary,
                  count: fields.length,
                  onTap: _showFieldsDialog,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('copilot'),
                  icon: Icons.smart_toy,
                  color: Colors.purple,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CopilotScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: _getAssignmentsTitle(local),
                  icon: Icons.assignment,
                  color: scheme.warning,
                  count: pendingAssignments,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssignmentsScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: _getTodoTitle(local),
                  icon: Icons.checklist,
                  color: scheme.success,
                  count: pendingTodos,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TodoScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('search'),
                  icon: Icons.search,
                  color: Colors.teal,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SearchScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('lectures'),
                  icon: Icons.menu_book,
                  color: Colors.red,
                  onTap: _openLecturesQuickAccess,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('spaced_repetition'),
                  icon: Icons.repeat,
                  color: Colors.purple,
                  count: 0,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SpacedRepetitionScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('annotations'),
                  icon: Icons.note,
                  color: Colors.teal,
                  count: 0,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AnnotationScreen(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: QuickAccessCard(
                  title: local.translate('settings'),
                  icon: Icons.settings,
                  color: Colors.grey,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldsSection() {
    final local = AppLocalizations.of(context);
    if (fields.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.folder_open,
                  size: 50,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 12),
                Text(
                  local.translate('no_fields_yet').replaceFirst('{name}', _getFieldsTitle(local)),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  local.translate('tap_add_to_create').replaceFirst('{name}', _getFieldsTitle(local)),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _showAddFieldDialog,
                  icon: const Icon(Icons.add),
                  label: Text(local.translate('add_field').replaceFirst('{name}', _getFieldsTitle(local))),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _getFieldsTitle(local),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle),
                onPressed: _showAddFieldDialog,
                tooltip: local.translate('add_field_tooltip'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...fields.take(3).map((field) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.folder, color: Colors.blue),
                ),
                title: Text(
                  field,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(local.translate('tap_to_enter')),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FieldScreen(field: field),
                    ),
                  ).then((_) => _loadData());
                },
              ),
            )),
        if (fields.length > 3) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              local.translate('and_more_fields').replaceFirst('{count}', (fields.length - 3).toString()).replaceFirst('{name}', _getFieldsTitle(local)),
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final local = AppLocalizations.of(context);
    return Scaffold(
      body: SmartRefresher(
        controller: _refreshController,
        enablePullDown: true,
        enablePullUp: false,
        onRefresh: _onRefresh,
        header: ClassicHeader(
          height: 60,
          textStyle: const TextStyle(
            fontSize: 14,
            color: Colors.black54,
          ),
          refreshingText: local.translate('refreshing'),
          releaseText: local.translate('release_to_refresh'),
          completeText: local.translate('refresh_complete'),
          idleText: local.translate('pull_to_refresh'),
          failedText: local.translate('refresh_failed'),
          releaseIcon: const Icon(Icons.arrow_upward, color: Colors.black54),
          completeIcon: const Icon(Icons.done, color: Colors.green),
          idleIcon: const Icon(Icons.arrow_downward, color: Colors.black54),
          refreshingIcon: const SizedBox(
            width: 25,
            height: 25,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWelcomeCard(),
                  const SizedBox(height: 20),
                  _buildQuickAccessSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: _buildFieldsSection(),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }
}