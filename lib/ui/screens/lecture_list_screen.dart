import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/storage_service.dart';
import '../../services/metadata_service.dart';
import '../../models/asset_model.dart';
import 'lecture_assets_screen.dart';
import 'main_screen.dart';
import '../l10n/app_localizations.dart';

class LectureListScreen extends StatefulWidget {
  final String field;
  final String year;
  final String subject;
  const LectureListScreen({
    Key? key,
    required this.field,
    required this.year,
    required this.subject,
  }) : super(key: key);

  @override
  State<LectureListScreen> createState() => _LectureListScreenState();
}

class _LectureListScreenState extends State<LectureListScreen> {
  final StorageService storage = StorageService();
  late final MetadataService metadataService;
  List<String> lectures = [];

  @override
  void initState() {
    super.initState();
    final assetBox = Hive.box<AssetModel>('assets_box');
    metadataService = MetadataService(assetBox, storage);
    _loadLectures();
  }

  Future<void> _loadLectures() async {
    final list = await storage.listLectures(widget.field, widget.year, widget.subject);
    setState(() => lectures = list);
  }

  Future<void> _addLectureDialog() async {
    final local = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('add_lecture')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: local.translate('lecture_name_hint')),
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
      await storage.createLectureFolder(widget.field, widget.year, widget.subject, res);
      await _loadLectures();
    }
  }

  Future<void> _deleteLecture(String lecture) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_lecture')),
        content: Text(local.translate('confirm_delete_lecture').replaceFirst('{lecture}', lecture)),
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
      final dir = Directory('${vault.path}/${widget.field}/${widget.year}/${widget.subject}/$lecture');
      if (await dir.exists()) await dir.delete(recursive: true);
      await _loadLectures();
    }
  }

  Future<void> _editLectureName(String oldLecture) async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController(text: oldLecture);
    final newLecture = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('edit_lecture_name')),
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

    if (newLecture != null && newLecture.isNotEmpty && newLecture != oldLecture) {
      try {
        await storage.renameLecture(
          widget.field, widget.year, widget.subject, oldLecture, newLecture,
        );
        await metadataService.updateAssetsAfterRename(
          oldField: widget.field,
          oldYear: widget.year,
          oldSubject: widget.subject,
          oldLecture: oldLecture,
          newField: widget.field,
          newYear: widget.year,
          newSubject: widget.subject,
          newLecture: newLecture,
        );
        _loadLectures();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('lecture_renamed_success'))),
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
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject} • ${local.translate('lectures')}'),
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
        onRefresh: _loadLectures,
        child: ListView.builder(
          itemCount: lectures.length,
          itemBuilder: (_, i) {
            final l = lectures[i];
            return ListTile(
              title: Text(l),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editLectureName(l),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteLecture(l),
                  ),
                  const Icon(Icons.arrow_forward),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LectureAssetsScreen(
                    field: widget.field,
                    year: widget.year,
                    subject: widget.subject,
                    lecture: l,
                  ),
                ),
              ).then((_) => _loadLectures()),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addLectureDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}