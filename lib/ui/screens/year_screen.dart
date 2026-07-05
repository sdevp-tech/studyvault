import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import 'subject_screen.dart';
import '../l10n/app_localizations.dart';
class YearScreen extends StatefulWidget {
  final String field;
  final String year;
  const YearScreen({Key? key, required this.field, required this.year}) : super(key: key);
  @override
  State<YearScreen> createState() => _YearScreenState();
}

class _YearScreenState extends State<YearScreen> {
  final StorageService storage = StorageService();
  List<String> subjects = [];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
  }

  Future<void> _loadSubjects() async {
    final list = await storage.listSubjects(widget.field, widget.year);
    print('DEBUG YearScreen: Subjects for ${widget.field}/${widget.year} = $list');
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
        decoration: InputDecoration(hintText: local.translate('subject_example'))
      ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: Text(local.translate('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: Text(local.translate('add'))),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      final vault = await storage.ensureStudyVault();
      final dir = Directory('${vault.path}/${widget.field}/${widget.year}/$res');
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final s in ['videos', 'pdfs', 'photos', 'notes']) {
        final sub = Directory('${dir.path}/$s');
        if (!await sub.exists()) await sub.create(recursive: true);
      }
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(local.translate('cancel'))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text(local.translate('delete'))),
        ],
      ),
    );
    if (confirm == true) {
      final vault = await storage.ensureStudyVault();
      final dir = Directory('${vault.path}/${widget.field}/${widget.year}/$subject');
      if (await dir.exists()) await dir.delete(recursive: true);
      await _loadSubjects();
    }
  }

  @override
  Widget build(BuildContext context) {
    
    return Scaffold(
      appBar: AppBar(title: Text('${widget.field} • ${widget.year}')),
      body: RefreshIndicator(
        onRefresh: _loadSubjects,
        child: ListView.builder(
          itemCount: subjects.length,
          itemBuilder: (_, i) {
            final s = subjects[i];
            return ListTile(
              title: Text(s),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteSubject(s)),
                const Icon(Icons.arrow_forward),
              ]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectScreen(field: widget.field, year: widget.year, subject: s))).then((_) => _loadSubjects()),
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
