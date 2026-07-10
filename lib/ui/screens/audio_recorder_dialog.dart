import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/audio_recorder_service.dart';
import '../l10n/app_localizations.dart';

class AudioRecorderDialog extends StatefulWidget {
  const AudioRecorderDialog({Key? key}) : super(key: key);

  @override
  _AudioRecorderDialogState createState() => _AudioRecorderDialogState();
}

class _AudioRecorderDialogState extends State<AudioRecorderDialog> {
  late AudioRecorderService _recorderService;
  String _status = '';
  String? _recordingPath;
  Timer? _timer;
  Duration _recordingDuration = Duration.zero;
  bool _isCompleted = false; // للتبديل بين وضعي التسجيل وما بعد التوقف

  @override
  void initState() {
    super.initState();
    _recorderService = AudioRecorderService();
    _updateStatusMessage('ready');
  }

  void _updateStatusMessage(String key) {
    final local = AppLocalizations.of(context);
    setState(() {
      switch (key) {
        case 'ready':
          _status = local.translate('ready_to_record');
          break;
        case 'recording':
          _status = local.translate('recording');
          break;
        case 'paused':
          _status = local.translate('paused');
          break;
        case 'start_failed':
          _status = local.translate('recording_start_failed');
          break;
        case 'success':
          _status = local.translate('recording_success');
          _isCompleted = true;
          break;
        case 'save_failed':
          _status = local.translate('recording_save_failed');
          _isCompleted = true;
          break;
        default:
          _status = key;
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    _updateStatusMessage('recording');
    setState(() => _recordingDuration = Duration.zero);

    final path = await _recorderService.startRecording();
    if (path != null) {
      _recordingPath = path;
      _startTimer();
    } else {
      _updateStatusMessage('start_failed');
    }
  }

  void _pauseRecording() {
    _recorderService.pauseRecording();
    _timer?.cancel();
    _updateStatusMessage('paused');
  }

  void _resumeRecording() {
    _recorderService.resumeRecording();
    _startTimer();
    _updateStatusMessage('recording');
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final path = await _recorderService.stopRecording();

    if (path != null && await File(path).exists()) {
      _updateStatusMessage('success');
    } else {
      _updateStatusMessage('save_failed');
    }
  }

  void _cancelRecording() async {
    _timer?.cancel();
    await _recorderService.cancelRecording();
    Navigator.pop(context); // يغلق الحوار ولا يعيد شيئاً
  }

  void _saveRecording() {
    if (_recordingPath != null) {
      Navigator.pop(context, File(_recordingPath!));
    } else {
      Navigator.pop(context);
    }
  }

  void _deleteRecording() async {
    if (_recordingPath != null) {
      final file = File(_recordingPath!);
      if (await file.exists()) {
        await file.delete();
      }
    }
    Navigator.pop(context); // إغلاق بدون ملف
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mic,
              size: 50,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            Text(
              _status.isEmpty ? local.translate('ready_to_record') : _status,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            if (_recorderService.isRecording)
              Column(
                children: [
                  Text(
                    _formatDuration(_recordingDuration),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.red,
                    size: 20,
                  ),
                ],
              ),
            const SizedBox(height: 20),
            // ── وضع التسجيل النشط / الإيقاف ──
            if (!_isCompleted)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (!_recorderService.isRecording) ...[
                    ElevatedButton.icon(
                      onPressed: _startRecording,
                      icon: const Icon(Icons.mic),
                      label: Text(local.translate('start_recording')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ] else if (_recorderService.isRecording &&
                      !_recorderService.isPaused) ...[
                    ElevatedButton.icon(
                      onPressed: _pauseRecording,
                      icon: const Icon(Icons.pause),
                      label: Text(local.translate('pause')),
                    ),
                    ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: Text(local.translate('stop')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ] else if (_recorderService.isPaused) ...[
                    ElevatedButton.icon(
                      onPressed: _resumeRecording,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(local.translate('resume')),
                    ),
                    ElevatedButton.icon(
                      onPressed: _stopRecording,
                      icon: const Icon(Icons.stop),
                      label: Text(local.translate('stop')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                  if (!_recorderService.isRecording)
                    TextButton(
                      onPressed: _cancelRecording,
                      child: Text(local.translate('cancel')),
                    ),
                ],
              )
            else
              // ── وضع إكمال التسجيل: زران حفظ وحذف ──
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _saveRecording,
                    icon: const Icon(Icons.save),
                    label: Text(local.translate('save')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _deleteRecording,
                    icon: const Icon(Icons.delete),
                    label: Text(local.translate('delete')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}