import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../services/storage_service.dart';
import '../../services/metadata_service.dart';
import '../../services/indexer_service.dart';
import '../../services/path_resolver.dart';
import '../../models/asset_model.dart';
import '../asset_viewer.dart';
import '../widgets/empty_state.dart';
import '../../ui/screens/audio_recorder_dialog.dart';
import 'main_screen.dart';
import '../l10n/app_localizations.dart';

class LectureAssetsScreen extends StatefulWidget {
  final String field;
  final String year;
  final String subject;
  final String lecture;

  const LectureAssetsScreen({
    Key? key,
    required this.field,
    required this.year,
    required this.subject,
    required this.lecture,
  }) : super(key: key);

  @override
  State<LectureAssetsScreen> createState() => _LectureAssetsScreenState();
}

class _LectureAssetsScreenState extends State<LectureAssetsScreen> {
  final StorageService storage = StorageService();
  late final MetadataService metadataService;
  late final IndexerService indexer;

  List<AssetModel> assets = [];
  bool _isLoading = false;

  String searchQuery = '';
  List<String> activeTags = [];
  String? filterType;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final box = Hive.box<AssetModel>('assets_box');
    metadataService = MetadataService(box, storage);
    indexer = IndexerService(storage, metadataService);

    searchQuery = '';
    activeTags = [];
    filterType = null;

    _applyFilters();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _applyFilters() {
    setState(() => _isLoading = true);
    final list = metadataService.searchAssets(
      field: widget.field,
      year: widget.year,
      subject: widget.subject,
      lecture: widget.lecture,
      query: searchQuery,
      tags: activeTags,
      type: filterType,
    );
    setState(() {
      assets = list;
      _isLoading = false;
    });
  }

  Future<void> _uploadMultipleFilesWithProgress(List<PlatformFile> files) async {
    final local = AppLocalizations.of(context);
    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0.0);
    final currentFileNotifier = ValueNotifier<String>('');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text('${local.translate('uploading_file')} (${files.length})'),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 16),
                Text('${(progress * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: currentFileNotifier,
                  builder: (_, fileName, __) => Text(
                    fileName,
                    style: const TextStyle(fontSize: 13),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelToken.cancel();
              Navigator.pop(dialogCtx);
            },
            child: Text(local.translate('cancel')),
          ),
        ],
      ),
    );

    try {
      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        if (f.path == null) continue;

        final file = File(f.path!);
        final type = storage.getFileType(f.name);
        final subDir = _getSubDirForType(type);
        currentFileNotifier.value = '${i + 1}/${files.length}: ${f.name}';

        final lectureDir = await storage.createLectureFolder(
          widget.field,
          widget.year,
          widget.subject,
          widget.lecture,
        );
        final destDirPath = p.join(lectureDir.path, subDir);

        final copiedFile = await storage.importFileWithProgress(
          sourceFile: file,
          destDirPath: destDirPath,
          cancelToken: cancelToken,
          onProgress: (pProgress) {
            progressNotifier.value = (i + pProgress) / files.length;
          },
        );

        final asset = await metadataService.addAsset(
          field: widget.field,
          year: widget.year,
          subject: widget.subject,
          lecture: widget.lecture,
          fileName: p.basename(copiedFile.path),
          filePath: copiedFile.path,
          type: type,
        );
        indexer.indexFile(asset);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(local.translate('upload_success')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (e is CancelException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('upload_cancelled'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${local.translate('upload_failed')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) Navigator.pop(context);
      progressNotifier.dispose();
      currentFileNotifier.dispose();
    }
  }

  Future<void> _uploadFileWithProgress(
    File sourceFile,
    String type,
    String subDir,
  ) async {
    final local = AppLocalizations.of(context);
    final lectureDir = await storage.createLectureFolder(
      widget.field,
      widget.year,
      widget.subject,
      widget.lecture,
    );
    final destDirPath = p.join(lectureDir.path, subDir);

    final cancelToken = CancelToken();
    final progressNotifier = ValueNotifier<double>(0.0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(local.translate('uploading_file')),
        content: ValueListenableBuilder<double>(
          valueListenable: progressNotifier,
          builder: (_, progress, __) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 16),
                Text('${(progress * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 12),
                Text(
                  p.basename(sourceFile.path),
                  style: const TextStyle(fontSize: 13),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelToken.cancel();
              Navigator.pop(dialogCtx);
            },
            child: Text(local.translate('cancel')),
          ),
        ],
      ),
    );

    try {
      final copiedFile = await storage.importFileWithProgress(
        sourceFile: sourceFile,
        destDirPath: destDirPath,
        cancelToken: cancelToken,
        onProgress: (p) {
          progressNotifier.value = p;
        },
      );

      final asset = await metadataService.addAsset(
        field: widget.field,
        year: widget.year,
        subject: widget.subject,
        lecture: widget.lecture,
        fileName: p.basename(copiedFile.path),
        filePath: copiedFile.path,
        type: type,
      );

      indexer.indexFile(asset);

      if (await sourceFile.exists()) await sourceFile.delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(local.translate('upload_success')),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (e is CancelException) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('upload_cancelled'))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${local.translate('upload_failed')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
      progressNotifier.dispose();
    }
  }

  String _getSubDirForType(String type) {
    switch (type) {
      case 'video':
        return 'videos';
      case 'pdf':
        return 'pdfs';
      case 'audio':
        return 'audios';
      case 'photo':
        return 'photos';
      case 'note':
        return 'notes';
      default:
        return 'other';
    }
  }

  Future<void> _capturePhoto() async {
    final photo = await storage.capturePhoto();
    if (photo != null) {
      await _uploadFileWithProgress(photo, 'photo', 'photos');
      await storage.clearTemporaryCache();
      await storage.cleanUnusedCache();
      _applyFilters();
    }
  }

  Future<void> _captureVideo() async {
    final video = await storage.captureVideo();
    if (video != null) {
      await _uploadFileWithProgress(video, 'video', 'videos');
      await storage.clearTemporaryCache();
      await storage.cleanUnusedCache();
      _applyFilters();
    }
  }

  Future<void> _addFromGallery() async {
    final image = await storage.pickImage();
    if (image != null) {
      await _uploadFileWithProgress(image, 'photo', 'photos');
      await storage.clearTemporaryCache();
      await storage.cleanUnusedCache();
      _applyFilters();
    }
  }

  Future<void> _addAudio() async {
    final audio = await storage.pickAudio();
    if (audio != null) {
      await _uploadFileWithProgress(audio, 'audio', 'audios');
      await storage.clearTemporaryCache();
      await storage.cleanUnusedCache();
      _applyFilters();
    }
  }

  Future<void> _recordAudio() async {
    final result = await showDialog<File?>(
      context: context,
      builder: (context) => const AudioRecorderDialog(),
    );
    if (result != null) {
      await _uploadFileWithProgress(result, 'audio', 'audios');
      await storage.clearTemporaryCache();
      await storage.cleanUnusedCache();
      _applyFilters();
    }
  }

  Future<void> _addTextNote() async {
    final local = AppLocalizations.of(context);
    final textController = TextEditingController();
    final titleController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('add_text_note')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: local.translate('note_title'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: local.translate('note_text'),
                  border: const OutlineInputBorder(),
                ),
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
            onPressed: () async {
              if (textController.text.isNotEmpty) {
                final title = titleController.text.isEmpty
                    ? '${local.translate('note')} ${DateTime.now().millisecondsSinceEpoch}'
                    : titleController.text;

                final lectureDir = await storage.createLectureFolder(
                  widget.field,
                  widget.year,
                  widget.subject,
                  widget.lecture,
                );
                final notesDir = p.join(lectureDir.path, 'notes');
                final file = await storage.saveTextNote(
                  textController.text,
                  title,
                  notesDir,
                );

                final asset = await metadataService.addAsset(
                  field: widget.field,
                  year: widget.year,
                  subject: widget.subject,
                  lecture: widget.lecture,
                  fileName: p.basename(file.path),
                  filePath: file.path,
                  type: 'note',
                  notes: textController.text,
                );

                indexer.indexFile(asset);
                _applyFilters();
                Navigator.pop(context);
              }
            },
            child: Text(local.translate('save')),
          ),
        ],
      ),
    );
  }

  Future<void> _importFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    await _uploadMultipleFilesWithProgress(result.files);

    await storage.clearTemporaryCache();
    await storage.cleanUnusedCache();
    _applyFilters();
  }

  Future<void> _showFileDetails(AssetModel asset) async {
    final local = AppLocalizations.of(context);
    final file = File(asset.resolvedFilePath);
    String fileSize = "Unknown";

    if (await file.exists()) {
      final bytes = await file.length();
      if (bytes < 1024) {
        fileSize = "$bytes B";
      } else if (bytes < 1048576) {
        fileSize = "${(bytes / 1024).toStringAsFixed(1)} KB";
      } else {
        fileSize = "${(bytes / 1048576).toStringAsFixed(2)} MB";
      }
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _getAssetIcon(asset.type),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    asset.fileName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const Divider(height: 30),
            _buildDetailRow(Icons.type_specimen, local.translate('type'), _getTypeArabic(asset.type)),
            _buildDetailRow(Icons.sd_storage, local.translate('size'), fileSize),
            _buildDetailRow(Icons.calendar_today, local.translate('date_added'), _formatDate(asset.createdAt)),
            if (asset.tags.isNotEmpty)
              _buildDetailRow(Icons.label, local.translate('tags'), asset.tags.join(', ')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(local.translate('cancel')),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _deleteAsset(AssetModel asset) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('delete_file')),
        content: Text(local.translate('confirm_delete_file').replaceFirst('{name}', asset.fileName)),
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
      await metadataService.deleteAsset(asset);
      _applyFilters();
    }
  }

  Future<void> _editAssetName(AssetModel asset) async {
    final local = AppLocalizations.of(context);
    final oldPath = asset.resolvedFilePath;
    final oldName = asset.fileName;
    final extension = p.extension(oldName);
    final baseName = p.basenameWithoutExtension(oldName);
    final controller = TextEditingController(text: baseName);

    final newName = await showDialog<String?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.translate('edit_file_name')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: local.translate('new_name'),
            suffixText: extension,
          ),
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

    if (newName != null && newName.isNotEmpty && '$newName$extension' != oldName) {
      try {
        final newFile = await storage.renameAssetFile(oldPath, newName);
        asset.fileName = p.basename(newFile.path);
        asset.filePath = PathResolver.toStorable(newFile.path);
        await asset.save();
        _applyFilters();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('file_renamed_success'))),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e')),
        );
      }
    }
  }

  Future<void> _editNoteContent(AssetModel asset) async {
    final local = AppLocalizations.of(context);
    if (asset.type != 'note' && !asset.fileName.endsWith('.txt')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('file_not_editable'))),
      );
      return;
    }

    try {
      final currentContent = await File(asset.resolvedFilePath).readAsString();
      final controller = TextEditingController(text: currentContent);

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${local.translate('edit')}: ${asset.fileName}'),
          content: Container(
            width: double.maxFinite,
            height: 400,
            child: TextField(
              controller: controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: local.translate('write_new_content'),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(local.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                await storage.updateNoteContent(asset.resolvedFilePath, controller.text);
                asset.notes = controller.text;
                await asset.save();
                Navigator.pop(context);
                _applyFilters();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(local.translate('changes_saved'))),
                );
              },
              child: Text(local.translate('save')),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${local.translate('error_reading_file')}: $e')),
      );
    }
  }

  Future<void> _shareAsset(AssetModel asset) async {
    final local = AppLocalizations.of(context);
    final file = File(asset.resolvedFilePath);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(file.path)], text: asset.fileName);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('file_not_found'))),
        );
      }
    }
  }

  Widget _buildSearchBar() {
    final local = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: local.translate('search_files'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) {
                setState(() => searchQuery = v);
                if (_debounce?.isActive ?? false) _debounce!.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () {
                  _applyFilters();
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (val) {
              setState(() => filterType = val == 'all' ? null : val);
              _applyFilters();
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'all', child: Text(local.translate('all'))),
              PopupMenuItem(value: 'video', child: Text(local.translate('video'))),
              PopupMenuItem(value: 'pdf', child: Text(local.translate('pdf'))),
              PopupMenuItem(value: 'photo', child: Text(local.translate('photo'))),
              PopupMenuItem(value: 'audio', child: Text(local.translate('audio'))),
              PopupMenuItem(value: 'note', child: Text(local.translate('note'))),
              PopupMenuItem(value: 'other', child: Text(local.translate('other'))),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture),
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
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async => _applyFilters(),
                    child: assets.isEmpty
                        ? EmptyState(
                            title: local.translate('no_files_in_lecture'),
                            message: local.translate('tap_plus_to_add_files'),
                            icon: Icons.folder_open,
                          )
                        : ListView.builder(
                            itemCount: assets.length,
                            itemBuilder: (_, i) {
                              final a = assets[i];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  leading: a.resolvedThumbnailPath != null
                                      ? Image.file(
                                          File(a.resolvedThumbnailPath!),
                                          width: 56,
                                          height: 56,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              _getAssetIcon(a.type),
                                        )
                                      : _getAssetIcon(a.type),
                                  title: Text(
                                    a.fileName,
                                    maxLines: 1, 
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${_getTypeArabic(a.type)} • ${_formatDate(a.createdAt)}'),
                                      if (a.tags.isNotEmpty)
                                        Text(
                                          '${local.translate('tags')}: ${a.tags.join(', ')}',
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      if ((a.notes ?? '').isNotEmpty)
                                        Text(
                                          '${local.translate('note')}: ${a.notes!.substring(0, min(a.notes!.length, 50))}...',
                                          style: const TextStyle(fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  isThreeLine: a.tags.isNotEmpty || (a.notes ?? '').isNotEmpty,
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => AssetViewer(asset: a)),
                                  ).then((_) => _applyFilters()),
                                  onLongPress: () => _showFileDetails(a), 
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (a.type == 'note' || a.fileName.endsWith('.txt'))
                                        IconButton(
                                          icon: const Icon(Icons.edit_note, color: Colors.green),
                                          onPressed: () => _editNoteContent(a),
                                          tooltip: local.translate('edit_content'),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.share, color: Colors.indigo),
                                        onPressed: () => _shareAsset(a),
                                        tooltip: local.translate('share'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, color: Colors.blue),
                                        onPressed: () => _editAssetName(a),
                                        tooltip: local.translate('edit_name'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _deleteAsset(a),
                                        tooltip: local.translate('delete'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddOptions,
        icon: const Icon(Icons.add),
        label: Text(local.translate('add')),
      ),
    );
  }

  Widget _getAssetIcon(String type) {
    switch (type) {
      case 'video':
        return const Icon(Icons.videocam, size: 40, color: Colors.red);
      case 'pdf':
        return const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red);
      case 'audio':
        return const Icon(Icons.audiotrack, size: 40, color: Colors.green);
      case 'photo':
        return const Icon(Icons.image, size: 40, color: Colors.blue);
      case 'note':
        return const Icon(Icons.note, size: 40, color: Colors.orange);
      default:
        return const Icon(Icons.insert_drive_file, size: 40, color: Colors.grey);
    }
  }

  String _getTypeArabic(String type) {
    final local = AppLocalizations.of(context);
    switch (type) {
      case 'video':
        return local.translate('video');
      case 'pdf':
        return local.translate('pdf');
      case 'audio':
        return local.translate('audio');
      case 'photo':
        return local.translate('photo');
      case 'note':
        return local.translate('note');
      default:
        return local.translate('file');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _showAddOptions() async {
    final local = AppLocalizations.of(context);
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                local.translate('add_to_lecture').replaceFirst('{lecture}', widget.lecture),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _buildOptionButton(
                    icon: Icons.photo_camera,
                    label: local.translate('capture_photo'),
                    color: Colors.blue,
                    onTap: () => Navigator.pop(context, {'type': 'camera_photo'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.videocam,
                    label: local.translate('record_video'),
                    color: Colors.red,
                    onTap: () => Navigator.pop(context, {'type': 'camera_video'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.mic,
                    label: local.translate('record_audio'),
                    color: Colors.green,
                    onTap: () => Navigator.pop(context, {'type': 'record_audio'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.audio_file,
                    label: local.translate('upload_audio'),
                    color: Colors.teal,
                    onTap: () => Navigator.pop(context, {'type': 'audio_file'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.note,
                    label: local.translate('text_note'),
                    color: Colors.orange,
                    onTap: () => Navigator.pop(context, {'type': 'note'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.image,
                    label: local.translate('gallery'),
                    color: Colors.purple,
                    onTap: () => Navigator.pop(context, {'type': 'gallery'}),
                  ),
                  _buildOptionButton(
                    icon: Icons.attach_file,
                    label: local.translate('upload_file'),
                    color: Colors.brown,
                    onTap: () => Navigator.pop(context, {'type': 'file'}),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(local.translate('cancel')),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    switch (result['type']) {
      case 'camera_photo':
        await _capturePhoto();
        break;
      case 'camera_video':
        await _captureVideo();
        break;
      case 'record_audio':
        await _recordAudio();
        break;
      case 'audio_file':
        await _addAudio();
        break;
      case 'note':
        await _addTextNote();
        break;
      case 'gallery':
        await _addFromGallery();
        break;
      case 'file':
        await _importFiles();
        break;
    }
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 80,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withAlpha(76)),
            ),
            child: IconButton(
              icon: Icon(icon, color: color),
              onPressed: onTap,
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,),
        ],
      ),
    );
  }
}