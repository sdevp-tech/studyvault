import 'dart:io';

import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecorderService {
  FlutterSoundRecorder? _recorder;
  String? _recordingPath;
  bool _isRecording = false;
  bool _isPaused = false;

  AudioRecorderService() {
    _recorder = FlutterSoundRecorder();
  }

  Future<bool> _checkPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _initializeRecorder() async {
    await _recorder!.openRecorder();
    // يمكنك ضبط إعدادات التسجيل هنا
  }

  Future<String?> startRecording() async {
    try {
      final hasPermission = await _checkPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied');
      }

      await _initializeRecorder();

      // إنشاء مسار للملف الصوتي
      final directory = await getTemporaryDirectory();
      final fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordingPath = '${directory.path}/$fileName';

      await _recorder!.startRecorder(
        toFile: _recordingPath!,
        codec: Codec.aacMP4,
      );

      _isRecording = true;
      _isPaused = false;

      return _recordingPath;
    } catch (e) {
      print('Error starting recording: $e');
      return null;
    }
  }

  Future<void> pauseRecording() async {
    if (_isRecording && !_isPaused) {
      await _recorder!.pauseRecorder();
      _isPaused = true;
    }
  }

  Future<void> resumeRecording() async {
    if (_isRecording && _isPaused) {
      await _recorder!.resumeRecorder();
      _isPaused = false;
    }
  }

  Future<String?> stopRecording() async {
    if (_isRecording) {
      await _recorder!.stopRecorder();
      _isRecording = false;
      _isPaused = false;
      await _recorder!.closeRecorder();
      return _recordingPath;
    }
    return null;
  }

  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder!.stopRecorder();
      _isRecording = false;
      _isPaused = false;
      await _recorder!.closeRecorder();
      // حذف الملف المؤقت
      if (_recordingPath != null) {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;

  void dispose() {
    _recorder?.closeRecorder();
    _recorder = null;
  }
}