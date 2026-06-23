import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:study_vault/models/asset_model.dart';
import 'package:study_vault/services/annotation_service.dart';
import 'package:study_vault/ui/widgets/empty_state.dart';
import 'package:study_vault/ui/asset_viewer.dart';
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

    // تطبيق الفلترة
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
      await annotationService.deleteAnnotation(annotation.id);
      await _loadData();
    }
  }

  Future<void> _editAnnotation(Annotation annotation) async {
    final local = AppLocalizations.of(context);
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
      default:
        return type;
    }
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
          annotation.shortText,
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
        trailing: PopupMenuButton(
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
        onTap: () {
          if (asset != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AssetViewer(asset: asset),
              ),
            );
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
    return Column(
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
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(local.translate('annotation_added')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}