import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/storage_service.dart';
import '../../services/metadata_service.dart';
import '../../models/asset_model.dart';
import 'subject_screen.dart';
import 'main_screen.dart';
import '../l10n/app_localizations.dart';

class SubjectsScreen extends StatefulWidget {
  final String field;
  final String year;
  const SubjectsScreen({Key? key, required this.field, required this.year}) : super(key: key);

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  final StorageService storage = StorageService();
  late final MetadataService metadataService;
  List<String> subjects = [];

  @override
  void initState() {
    super.initState();
    final assetBox = Hive.box<AssetModel>('assets_box');
    metadataService = MetadataService(assetBox, storage);
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final list = await storage.listSubjects(widget.field, widget.year);
    setState(() => subjects = list);
  }

  Future<void> _addSubjectDialog() async {
    final local = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('add_subject')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: local.translate('subject_example')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text(local.translate('add')),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      await storage.createSubjectFolder(widget.field, widget.year, res);
      await _loadSubjects();
    }
  }

  Future<void> _deleteSubject(String subject) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_subject')),
        content: Text(local.translate('confirm_delete_subject').replaceFirst('{subject}', subject)),
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
      final vault = await storage.ensureStudyVault();
      final dir = '${vault.path}/${widget.field}/${widget.year}/$subject';
      try {
        await Directory(dir).delete(recursive: true);
        _loadSubjects();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e')),
        );
      }
    }
  }

  Future<void> _editSubjectName(String oldSubject) async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController(text: oldSubject);
    final newSubject = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('edit_subject_name')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: local.translate('new_name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(local.translate('save')),
          ),
        ],
      ),
    );

    if (newSubject != null && newSubject.isNotEmpty && newSubject != oldSubject) {
      try {
        await storage.renameSubject(widget.field, widget.year, oldSubject, newSubject);
        await metadataService.updateAssetsAfterRename(
          oldField: widget.field,
          oldYear: widget.year,
          oldSubject: oldSubject,
          newField: widget.field,
          newYear: widget.year,
          newSubject: newSubject,
        );
        _loadSubjects();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('subject_renamed_success'))),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.field} • ${widget.year}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadSubjects,
        child: ListView.builder(
          itemCount: subjects.length,
          itemBuilder: (_, i) {
            final s = subjects[i];
            return ListTile(
              title: Text(s),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editSubjectName(s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteSubject(s),
                  ),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectScreen(
                    field: widget.field,
                    year: widget.year,
                    subject: s,
                  ),
                ),
              ).then((_) => _loadSubjects()),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSubjectDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}