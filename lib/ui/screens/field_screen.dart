import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../services/storage_service.dart';
import '../../services/metadata_service.dart';
import '../../models/asset_model.dart';
import 'subjects_screen.dart';
import '../l10n/app_localizations.dart';

class FieldScreen extends StatefulWidget {
  final String field;
  const FieldScreen({Key? key, required this.field}) : super(key: key);

  @override
  State<FieldScreen> createState() => _FieldScreenState();
}

class _FieldScreenState extends State<FieldScreen> {
  final StorageService storage = StorageService();
  late final MetadataService metadataService;
  List<String> years = [];

  @override
  void initState() {
    super.initState();
    final assetBox = Hive.box<AssetModel>('assets_box');
    metadataService = MetadataService(assetBox, storage);
    _loadYears();
  }

  Future<void> _loadYears() async {
    final list = await storage.listYears(widget.field);
    setState(() => years = list);
  }

  Future<void> _addYearDialog() async {
    final local = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    final res = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('add_year')),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(hintText: local.translate('year_example')),
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
      await storage.createSubjectFolder(widget.field, res, local.translate('default_subject'));
      await _loadYears();
    }
  }

  Future<void> _deleteYear(String year) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_year')),
        content: Text(local.translate('confirm_delete_year').replaceFirst('{year}', year)),
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
      final dir = '${vault.path}/${widget.field}/$year';
      try {
        await Directory(dir).delete(recursive: true);
        _loadYears();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error_deleting')}: $e')),
        );
      }
    }
  }

  Future<void> _editFieldName() async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController(text: widget.field);
    final newName = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('edit_field_name')),
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

    if (newName != null && newName.isNotEmpty && newName != widget.field) {
      try {
        await storage.renameField(widget.field, newName);
        // تحديث الأصول يدوياً (لأن تغيير field يؤثر على جميع السنوات)
        final assetBox = Hive.box<AssetModel>('assets_box');
        final assets = assetBox.values.where((a) => a.field == widget.field).toList();
        for (var a in assets) {
          a.field = newName;
          a.filePath = a.filePath.replaceFirst('/${widget.field}/', '/$newName/');
          await a.save();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('field_renamed_success'))),
        );
        Navigator.pop(context, true);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e')),
        );
      }
    }
  }

  Future<void> _editYearName(String oldYear) async {
    final local = AppLocalizations.of(context);
    final controller = TextEditingController(text: oldYear);
    final newYear = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('edit_year_name')),
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

    if (newYear != null && newYear.isNotEmpty && newYear != oldYear) {
      try {
        await storage.renameYear(widget.field, oldYear, newYear);
        await metadataService.updateAssetsAfterRename(
          oldField: widget.field,
          oldYear: oldYear,
          newField: widget.field,
          newYear: newYear,
        );
        _loadYears();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('year_renamed_success'))),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e')),
        );
      }
    }
  }

  Future<void> _deleteField() async {
    final local = AppLocalizations.of(context);
    
    // 1. التحقق من قاعدة البيانات (Hive) باستخدام AssetModel
    final assetBox = Hive.box<AssetModel>('assets_box');
    final hasIndexedFiles = assetBox.values.any((a) => a.field == widget.field);

    // 2. التحقق من نظام الملفات الفعلي
    final vault = await storage.ensureStudyVault();
    final fieldDir = Directory('${vault.path}/${widget.field}');
    
    bool hasPhysicalFiles = false;
    if (await fieldDir.exists()) {
      await for (var entity in fieldDir.list(recursive: true)) {
        if (entity is File) {
          hasPhysicalFiles = true;
          break;
        }
      }
    }

    // إذا وُجدت ملفات سواء في Hive أو النظام، نمنع الحذف
    if (hasIndexedFiles || hasPhysicalFiles) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(local.translate('cannot_delete_has_files')), // تم إزالة الاختصار هنا
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // إذا كان فارغاً (أو يحتوي فقط على مجلدات سنوات ومواد فارغة)، نطلب التأكيد
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_field')), // تم إزالة الاختصار هنا
        content: Text('${local.translate('confirm_delete_field')} "${widget.field}"؟'), // تم إزالة الاختصار هنا
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(local.translate('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (await fieldDir.exists()) {
          await fieldDir.delete(recursive: true); 
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(local.translate('field_deleted_success')), // تم إزالة الاختصار هنا
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true); 
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${local.translate('error_deleting')}: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.field),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editFieldName,
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: _deleteField,
            tooltip: 'حذف التخصص', // يمكن تبديله بـ local.translate('delete_field_tooltip')
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadYears,
        child: ListView.builder(
          itemCount: years.length,
          itemBuilder: (_, i) {
            final y = years[i];
            return ListTile(
              title: Text(y),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _editYearName(y),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteYear(y),
                  ),
                ],
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SubjectsScreen(field: widget.field, year: y),
                ),
              ).then((_) => _loadYears()),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addYearDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}