import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart'; // لتشغيل الصوت
import 'package:study_vault/models/asset_model.dart';
import 'package:study_vault/services/annotation_service.dart';
import 'package:study_vault/ui/widgets/empty_state.dart';
import 'package:study_vault/ui/asset_viewer.dart';
import 'package:study_vault/ui/screens/audio_recorder_dialog.dart'; // استيراد مسجل الصوت
import '../l10n/app_localizations.dart';

class AnnotationScreen extends StatefulWidget {
  final String? assetId;
  const AnnotationScreen({super.key, this.assetId});

  @override
  State<AnnotationScreen> createState() => _AnnotationScreenState();
}

class _AnnotationScreenState extends State<AnnotationScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late AnnotationService annotationService;
  late Box<AssetModel> assetBox;

  List<Annotation> annotations = [];
  Map<String, int> stats = {};
  String _searchQuery = '';
  String? _filterType;

  @override
  void initState() {
    super.initState();
    final annotationBox = Hive.box<Annotation>('annotations_box');
    annotationService = AnnotationService(annotationBox);
    assetBox = Hive.box<AssetModel>('assets_box');
    _loadData();
  }

  Future<void> _loadData() async {
    List<Annotation> allAnnotations;

    if (widget.assetId != null) {
      allAnnotations = annotationService.getForAsset(widget.assetId!);
    } else {
      final box = Hive.box<Annotation>('annotations_box');
      allAnnotations = box.values.toList();
    }

    allAnnotations = allAnnotations.where((annotation) {
      if (_searchQuery.isNotEmpty &&
          !annotation.text.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }

      if (_filterType != null && annotation.type != _filterType) {
        return false;
      }

      return true;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      annotations = allAnnotations;
      stats = annotationService.getStatistics();
    });
  }

  Future<void> _deleteAnnotation(Annotation annotation) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('delete_annotation')),
        content: Text(local.translate('confirm_delete_annotation')),
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
      // حذف الملف الصوتي من الجهاز لتوفير المساحة التخزينية
      if (annotation.type == 'audio') {
        final audioFile = File(annotation.text);
        if (await audioFile.exists()) {
          await audioFile.delete();
        }
      }
      await annotationService.deleteAnnotation(annotation.id);
      await _loadData();
    }
  }

  Future<void> _editAnnotation(Annotation annotation) async {
    final local = AppLocalizations.of(context);
    
    // منع تعديل التعليق الصوتي يدوياً لتجنب إتلاف مسار الملف
    if (annotation.type == 'audio') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('cannot_edit_audio'))),
      );
      return;
    }

    final textController = TextEditingController(text: annotation.text);
    final typeController = TextEditingController(text: annotation.type);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('edit_annotation')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: local.translate('annotation_text'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: annotation.type,
                decoration: InputDecoration(
                  labelText: local.translate('annotation_type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'text',
                    child: Text(local.translate('type_text')),
                  ),
                  DropdownMenuItem(
                    value: 'highlight',
                    child: Text(local.translate('type_highlight')),
                  ),
                  DropdownMenuItem(
                    value: 'question',
                    child: Text(local.translate('type_question')),
                  ),
                ],
                onChanged: (value) {
                  typeController.text = value ?? 'text';
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, {
                'text': textController.text,
                'type': typeController.text,
              });
            },
            child: Text(local.translate('save')),
          ),
        ],
      ),
    );

    if (result != null) {
      annotation.text = result['text'];
      annotation.type = result['type'];
      await annotationService.updateAnnotation(annotation);
      await _loadData();
    }
  }

  Color _getAnnotationColor(Annotation annotation) {
    switch (annotation.type) {
      case 'highlight':
        return Colors.yellow;
      case 'question':
        return Colors.orange;
      case 'audio': // إضافة لون مميز للصوت
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getAnnotationIcon(Annotation annotation) {
    switch (annotation.type) {
      case 'highlight':
        return Icons.highlight;
      case 'question':
        return Icons.question_mark;
      case 'audio': // إضافة أيقونة الميكروفون
        return Icons.mic;
      default:
        return Icons.note;
    }
  }

  String _getTypeArabic(String type) {
    final local = AppLocalizations.of(context);
    switch (type) {
      case 'text':
        return local.translate('type_text');
      case 'highlight':
        return local.translate('type_highlight');
      case 'question':
        return local.translate('type_question');
      case 'audio': // ترجمة نوع الصوت
        return local.translate('type_audio');
      default:
        return type;
    }
  }
  void _showAnnotationDetails(Annotation annotation, AssetModel? asset) {
    final local = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              _getAnnotationIcon(annotation),
              color: _getAnnotationColor(annotation),
            ),
            const SizedBox(width: 8),
            Text(
              _getTypeArabic(annotation.type ?? 'text'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            annotation.text,
            style: const TextStyle(fontSize: 16, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(local.translate('close')),
          ),
          if (asset != null)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context); // إغلاق النافذة المنبثقة أولاً
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssetViewer(asset: asset),
                  ),
                );
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(local.translate('open_file')),
            ),
        ],
      ),
    );
  }
  Widget _buildAnnotationCard(Annotation annotation) {
    final local = AppLocalizations.of(context);
    final asset = assetBox.get(annotation.assetId);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _getAnnotationColor(annotation).withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getAnnotationIcon(annotation),
            color: _getAnnotationColor(annotation),
          ),
        ),
        title: Text(
          // إخفاء مسار الملف إذا كان التعليق صوتياً وإظهار اسم بديل
          annotation.type == 'audio' ? local.translate('audio_annotation') : annotation.shortText,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset != null) Text('${local.translate('file')}: ${asset.fileName}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                  label: Text(_getTypeArabic(annotation.type!)),
                  backgroundColor: _getAnnotationColor(annotation).withAlpha(30),
                  labelStyle: TextStyle(
                    color: _getAnnotationColor(annotation),
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  DateFormat.yMd().add_jm().format(annotation.createdAt),
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // زر تشغيل التعليق الصوتي
            if (annotation.type == 'audio')
              IconButton(
                icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 30),
                onPressed: () => OpenFile.open(annotation.text),
              ),
            PopupMenuButton(
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, color: Colors.blue),
                      const SizedBox(width: 8),
                      Text(local.translate('edit')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(local.translate('delete')),
                    ],
                  ),
                ),
              ],
              onSelected: (value) async {
                if (value == 'edit') {
                  await _editAnnotation(annotation);
                } else if (value == 'delete') {
                  await _deleteAnnotation(annotation);
                }
              },
            ),
          ],
        ),
        onTap: () {
          if (annotation.type == 'audio') {
            // النقر على الملاحظة الصوتية يقوم بتشغيلها
            OpenFile.open(annotation.text);
          } else {
            // النقر على الملاحظات النصية يعرض محتواها الكامل
            _showAnnotationDetails(annotation, asset);
          }
        },
      ),
    );
  }

  Widget _buildStatsCard() {
    final local = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              local.translate('annotation_stats'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCircle(
                  value: stats['total']?.toString() ?? '0',
                  label: local.translate('all_annotations'),
                  color: Colors.blue,
                ),
                _buildStatCircle(
                  value: stats['text']?.toString() ?? '0',
                  label: local.translate('type_text'),
                  color: Colors.green,
                ),
                _buildStatCircle(
                  value: stats['highlight']?.toString() ?? '0',
                  label: local.translate('type_highlight'),
                  color: Colors.yellow,
                ),
                _buildStatCircle(
                  value: stats['question']?.toString() ?? '0',
                  label: local.translate('type_question'),
                  color: Colors.orange,
                ),
                // إحصائيات التعليقات الصوتية
                _buildStatCircle(
                  value: stats['audio']?.toString() ?? '0',
                  label: local.translate('type_audio'),
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle({
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                value,
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
            label, 
            style: const TextStyle(fontSize: 10),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final local = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: local.translate('search_annotations'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _loadData();
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() => _filterType = value);
              _loadData();
            },
            itemBuilder: (_) => <PopupMenuEntry<String?>>[
              PopupMenuItem(
                value: null,
                child: Text(local.translate('all')),
              ),
              PopupMenuItem(
                value: 'text',
                child: Text(local.translate('type_text')),
              ),
              PopupMenuItem(
                value: 'highlight',
                child: Text(local.translate('type_highlight')),
              ),
              PopupMenuItem(
                value: 'question',
                child: Text(local.translate('type_question')),
              ),
              PopupMenuItem(
                value: 'audio',
                child: Text(local.translate('type_audio')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: widget.assetId != null
            ? Text(local.translate('file_annotations'))
            : Text(local.translate('all_annotations')),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: Column(
          children: [
            if (widget.assetId == null) _buildSearchBar(),
            Expanded(
              child: annotations.isEmpty
                  ? EmptyState(
                      title: local.translate('no_annotations'),
                      message: _searchQuery.isNotEmpty
                          ? local.translate('no_annotations_match')
                          : local.translate('add_annotations_hint'),
                      icon: Icons.note_add,
                    )
                  : ListView.builder(
                      itemCount: annotations.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0 && widget.assetId == null) {
                          return _buildStatsCard();
                        }
                        final annotationIndex = widget.assetId == null ? index - 1 : index;
                        return _buildAnnotationCard(annotations[annotationIndex]);
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.assetId != null
          ? FloatingActionButton.extended(
              onPressed: () => _addAnnotationForAsset(),
              icon: const Icon(Icons.add_comment),
              label: Text(local.translate('add_annotation')),
            )
          : null,
    );
  }

  // ────── إضافة تعليق صوتي أو نصي من داخل شاشة التعليقات ──────
  Future<void> _addAudioAnnotationForAsset() async {
    if (widget.assetId == null) return;

    final local = AppLocalizations.of(context);
    final result = await showDialog<File?>(
      context: context,
      builder: (context) => const AudioRecorderDialog(),
    );

    if (result != null) {
      await annotationService.addAnnotation(
        assetId: widget.assetId!,
        text: result.path,
        type: 'audio',
      );
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(local.translate('annotation_added')),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _addAnnotationForAsset() async {
    if (widget.assetId == null) return;

    final local = AppLocalizations.of(context);
    final textController = TextEditingController();
    final typeController = TextEditingController(text: 'text');

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('add_annotation')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // زر التسجيل الصوتي
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 45),
                  backgroundColor: Colors.red.withAlpha(20),
                  foregroundColor: Colors.red,
                  elevation: 0,
                ),
                icon: const Icon(Icons.mic),
                label: Text(local.translate('record_audio')),
                onPressed: () {
                  Navigator.pop(context);
                  _addAudioAnnotationForAsset();
                },
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: local.translate('annotation_text'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: 'text',
                decoration: InputDecoration(
                  labelText: local.translate('annotation_type'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'text',
                    child: Text(local.translate('type_text')),
                  ),
                  DropdownMenuItem(
                    value: 'highlight',
                    child: Text(local.translate('type_highlight')),
                  ),
                  DropdownMenuItem(
                    value: 'question',
                    child: Text(local.translate('type_question')),
                  ),
                ],
                onChanged: (value) {
                  typeController.text = value ?? 'text';
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(local.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                Navigator.pop(context, {
                  'text': textController.text,
                  'type': typeController.text,
                });
              }
            },
            child: Text(local.translate('add')),
          ),
        ],
      ),
    );

    if (result != null) {
      await annotationService.addAnnotation(
        assetId: widget.assetId!,
        text: result['text'],
        type: result['type'],
      );
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(local.translate('annotation_added')),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }
}