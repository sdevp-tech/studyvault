import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:chewie/chewie.dart';
import 'package:video_player/video_player.dart';
import 'package:photo_view/photo_view.dart';
import 'package:hive/hive.dart';
import 'package:study_vault/models/asset_model.dart';
import 'package:study_vault/services/annotation_service.dart';
import 'package:study_vault/services/spaced_repetition_service.dart';
import 'package:study_vault/ui/screens/annotation_screen.dart';
import 'package:study_vault/ui/screens/spaced_repetition_screen.dart';
import 'package:study_vault/ui/screens/audio_recorder_dialog.dart'; // استيراد مسجل الصوت
import 'l10n/app_localizations.dart';

class AssetViewer extends StatefulWidget {
  final AssetModel asset;
  const AssetViewer({Key? key, required this.asset}) : super(key: key);

  @override
  State<AssetViewer> createState() => _AssetViewerState();
}

class _AssetViewerState extends State<AssetViewer> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _videoReady = false;
  late AnnotationService _annotationService;
  late SpacedRepetitionService _cardService;
  List<Annotation> _annotations = [];

  bool _isFullScreen = false;
  int _rotationTurns = 0;

  @override
  void initState() {
    super.initState();

    final annotationBox = Hive.box<Annotation>('annotations_box');
    final cardBox = Hive.box<CardModel>('cards_box');
    _annotationService = AnnotationService(annotationBox);
    _cardService = SpacedRepetitionService(cardBox);
    _loadAnnotations();

    if (widget.asset.type == 'video') {
      _initializeVideoPlayer();
    }
  }

  Future<void> _loadAnnotations() async {
    final annotations = _annotationService.getForAsset(widget.asset.id);
    setState(() {
      _annotations = annotations;
    });
  }

  void _initializeVideoPlayer() {
    _videoController = VideoPlayerController.file(File(widget.asset.filePath))
      ..initialize().then((_) {
        _chewieController = ChewieController(
          videoPlayerController: _videoController!,
          autoPlay: false,
          looping: false,
        );
        setState(() => _videoReady = true);
      }).catchError((e) {
        print('Video initialization error: $e');
        setState(() => _videoReady = false);
      });
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _openExternally() async {
    await OpenFile.open(widget.asset.filePath);
  }

  // ────── إضافة تعليق صوتي ──────
  Future<void> _addAudioAnnotation() async {
    final local = AppLocalizations.of(context);
    final result = await showDialog<File?>(
      context: context,
      builder: (context) => const AudioRecorderDialog(),
    );

    if (result != null) {
      // حفظ مسار الملف الصوتي داخل حقل النص وتحديد النوع كـ audio
      await _annotationService.addAnnotation(
        assetId: widget.asset.id,
        text: result.path,
        type: 'audio',
      );
      await _loadAnnotations();

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

  // ────── إضافة تعليق نصي ──────
  Future<void> _addAnnotation() async {
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
              // زر لتسجيل تعليق صوتي من داخل نفس النافذة
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
                  Navigator.pop(context); // إغلاق نافذة النص
                  _addAudioAnnotation();  // فتح مسجل الصوت
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
      await _annotationService.addAnnotation(
        assetId: widget.asset.id,
        text: result['text'],
        type: result['type'],
      );
      await _loadAnnotations();

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

  Future<void> _addToSpacedRepetition() async {
    final local = AppLocalizations.of(context);
    final textController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('add_to_spaced_repetition')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: local.translate('text_for_review'),
                  hintText: local.translate('enter_text_to_review'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                local.translate('will_be_added_as_card'),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                Navigator.pop(context, {'text': textController.text});
              }
            },
            child: Text(local.translate('add')),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _cardService.createCard(
          assetId: widget.asset.id,
          snippet: result['text'],
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(local.translate('card_added_to_review')),
            duration: const Duration(seconds: 2),
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${local.translate('error')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _viewAnnotations() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnnotationScreen(assetId: widget.asset.id),
      ),
    ).then((_) => _loadAnnotations());
  }

  Widget _buildAnnotationsPreview() {
    final local = AppLocalizations.of(context);
    if (_annotations.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                local.translate('annotations'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              TextButton(
                onPressed: _viewAnnotations,
                child: Text(local.translate('view_all')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Column(
            children: _annotations.take(3).map((annotation) => ListTile(
              dense: true,
              leading: Icon(
                annotation.type == 'audio' ? Icons.mic : Icons.note, 
                size: 20, 
                color: annotation.type == 'audio' ? Colors.red : Colors.blue,
              ),
              title: Text(
                annotation.type == 'audio' ? local.translate('audio_annotation') : annotation.shortText, 
                style: const TextStyle(fontSize: 14)
              ),
              subtitle: Text(
                '${annotation.page.isNotEmpty ? '${local.translate('page')} ${annotation.page} • ' : ''}'
                '${annotation.type == 'text' ? local.translate('type_text') : annotation.type == 'highlight' ? local.translate('type_highlight') : annotation.type == 'audio' ? local.translate('type_audio') : local.translate('type_question')}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: annotation.type == 'audio' 
                ? IconButton(
                    icon: const Icon(Icons.play_circle_fill, color: Colors.green, size: 28),
                    onPressed: () => OpenFile.open(annotation.text), // تشغيل المقطع
                  ) 
                : null,
            )).toList(),
          ),
          if (_annotations.length > 3)
            Center(
              child: Text(
                local.translate('and_more_annotations').replaceFirst('{count}', (_annotations.length - 3).toString()),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final local = AppLocalizations.of(context);
    if (!_videoReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(local.translate('loading_video')),
          ],
        ),
      );
    }

    return _chewieController != null
        ? Directionality(
            textDirection: TextDirection.ltr,
            child: Chewie(controller: _chewieController!),
          )
        : Center(child: Text(local.translate('video_not_available')));
  }

  Widget _buildPdfViewer() {
    final local = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 80, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            widget.asset.fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: Text(local.translate('open_file')),
                onPressed: _openExternally,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.repeat),
                label: Text(local.translate('add_to_review')),
                onPressed: _addToSpacedRepetition,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoViewer() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isFullScreen = !_isFullScreen;
        });
      },
      child: Stack(
        children: [
          Container(
            color: Colors.black, 
            child: RotatedBox(
              quarterTurns: _rotationTurns,
              child: PhotoView(
                imageProvider: FileImage(File(widget.asset.filePath)),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 3.0,
                initialScale: PhotoViewComputedScale.contained,
                enableRotation: false, // تم إيقاف التدوير الحر لمنع الميلان
                backgroundDecoration: const BoxDecoration(color: Colors.black),
              ),
            ),
          ),
          if (!_isFullScreen)
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton(
                heroTag: 'rotate_photo_btn',
                backgroundColor: Colors.black54,
                child: const Icon(Icons.rotate_right, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _rotationTurns = (_rotationTurns + 1) % 4;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayer() {
    final local = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.audiotrack, size: 80, color: Colors.green),
          const SizedBox(height: 20),
          Text(
            widget.asset.fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow),
            label: Text(local.translate('play_audio')),
            onPressed: _openExternally,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.repeat),
            label: Text(local.translate('add_to_review')),
            onPressed: _addToSpacedRepetition,
          ),
        ],
      ),
    );
  }

  Widget _buildTextViewer() {
    final local = AppLocalizations.of(context);
    try {
      final file = File(widget.asset.filePath);
      final content = file.readAsStringSync();

      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                content,
                style: const TextStyle(fontSize: 16, height: 1.6),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.repeat),
                  label: Text(local.translate('add_to_review')),
                  onPressed: _addToSpacedRepetition,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: Text(local.translate('copy_text')),
                  onPressed: () {
                    // Implement copy to clipboard
                  },
                ),
              ],
            ),
          ),
        ],
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 60, color: Colors.red),
            const SizedBox(height: 20),
            Text(
              local.translate('cannot_read_file'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              '${local.translate('error')}: $e',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
  }

  Widget _buildGenericFileViewer() {
    final local = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          Text(
            widget.asset.fileName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.open_in_new),
            label: Text(local.translate('open_file')),
            onPressed: _openExternally,
          ),
        ],
      ),
    );
  }

  Widget _buildContentViewer() {
    switch (widget.asset.type) {
      case 'photo':
        return _buildPhotoViewer();
      case 'video':
        return _buildVideoPlayer();
      case 'pdf':
        return _buildPdfViewer();
      case 'audio':
        return _buildAudioPlayer();
      case 'note':
        return _buildTextViewer();
      default:
        return _buildGenericFileViewer();
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    
    final bool isImage = widget.asset.type.toString().contains('photo') || widget.asset.type.toString().contains('image') || widget.asset.fileName.endsWith('.jpg') || widget.asset.fileName.endsWith('.png');
    final bool hideUI = _isFullScreen && isImage;

    return Scaffold(
      backgroundColor: hideUI ? Colors.black : Theme.of(context).scaffoldBackgroundColor,
      appBar: hideUI 
          ? null 
          : AppBar(
              title: Text(
                widget.asset.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              actions: [
                PopupMenuButton<String>(
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'annotations',
                      child: Row(
                        children: [
                          const Icon(Icons.note, color: Colors.blue, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('annotations')),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'add_audio',
                      child: Row(
                        children: [
                          const Icon(Icons.mic, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('record_audio')),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'add_annotation',
                      child: Row(
                        children: [
                          const Icon(Icons.add_comment, color: Colors.green, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('add_annotation')),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'add_to_repetition',
                      child: Row(
                        children: [
                          const Icon(Icons.repeat, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('add_to_review')),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'open_external',
                      child: Row(
                        children: [
                          const Icon(Icons.open_in_new, color: Colors.purple, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('open_externally')),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'spaced_repetition',
                      child: Row(
                        children: [
                          const Icon(Icons.school, color: Colors.indigo, size: 20),
                          const SizedBox(width: 8),
                          Text(local.translate('spaced_repetition')),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    switch (value) {
                      case 'annotations':
                        _viewAnnotations();
                        break;
                      case 'add_audio':
                        await _addAudioAnnotation();
                        break;
                      case 'add_annotation':
                        await _addAnnotation();
                        break;
                      case 'add_to_repetition':
                        await _addToSpacedRepetition();
                        break;
                      case 'open_external':
                        await _openExternally();
                        break;
                      case 'spaced_repetition':
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SpacedRepetitionScreen(),
                          ),
                        );
                        break;
                    }
                  },
                ),
              ],
            ),
      body: Column(
        children: [
          Expanded(child: _buildContentViewer()),
          if (!hideUI) _buildAnnotationsPreview(), 
        ],
      ),
      floatingActionButton: hideUI
          ? null 
          : FloatingActionButton.extended(
              onPressed: _addAnnotation,
              icon: const Icon(Icons.add_comment),
              label: Text(local.translate('add_annotation')),
            ),
    );
  }
}