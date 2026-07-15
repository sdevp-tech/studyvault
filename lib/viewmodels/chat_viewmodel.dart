// chat_viewmodel.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/chat_message.dart';
import '../models/llm_settings.dart';
import '../services/litert_service.dart';

class ChatViewModel extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  final LiteRtService _service = LiteRtService();
  bool _isLoading = false;
  StreamSubscription<String>? _subscription;
  bool _isStopping = false;
  List<File> _availableModels = [];

  int? _currentAiMessageIndex;
  Stopwatch? _currentStopwatch;

  bool _isModelLoaded = false;
  String? _activeModelPath;

  // متغير لمعرفة ما إذا كان النموذج النشط حالياً يدعم الصور
  bool _activeModelSupportsVision = false;

  File? _selectedImage;

  bool _isImporting = false;
  double _importProgress = 0.0;
  bool _isInitializingModel = false;
  String? _initializingModelPath;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  List<File> get availableModels => _availableModels;
  bool get isModelLoaded => _isModelLoaded;

  // Getter للمتغير
  bool get activeModelSupportsVision => _activeModelSupportsVision;

  File? get selectedImage => _selectedImage;

  bool get isImporting => _isImporting;
  double get importProgress => _importProgress;
  bool get isInitializingModel => _isInitializingModel;
  String? get initializingModelPath => _initializingModelPath;

  String? get activeModelName {
    if (!_isModelLoaded || _activeModelPath == null) return null;
    return p.basename(_activeModelPath!);
  }

  ChatViewModel() {
    refreshAvailableModels();
  }

  void setImage(File? image) {
    _selectedImage = image;
    notifyListeners();
  }

  Future<void> refreshAvailableModels() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      _availableModels = files
          .whereType<File>()
          .where((file) {
            final path = file.path.toLowerCase();
            return path.endsWith('.litert') ||
                path.endsWith('.litertlm') ||
                path.endsWith('.task') ||
                path.endsWith('.bin');
          })
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error refreshing models: $e");
    }
  }

  Future<void> pickAndImportModel() async {
    try {
      _isImporting = true;
      _importProgress = 0.0;
      notifyListeners();

      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litert', 'litertlm', 'task', 'bin'],
        withReadStream: true,
      );

      if (result == null || result.files.single.readStream == null) {
        _isImporting = false;
        notifyListeners();
        return;
      }

      PlatformFile file = result.files.single;

      Directory appDocDir = await getApplicationDocumentsDirectory();
      String permanentPath = p.join(appDocDir.path, file.name);
      File permanentFile = File(permanentPath);

      final length = file.size;
      int copied = 0;

      final output = permanentFile.openWrite();
      int lastNotifiedPercent = -1;

      await for (var chunk in file.readStream!) {
        output.add(chunk);
        copied += chunk.length;

        if (length > 0) {
          _importProgress = copied / length;

          int currentPercent = (_importProgress * 100).toInt();
          if (currentPercent != lastNotifiedPercent) {
            lastNotifiedPercent = currentPercent;
            notifyListeners();
          }
        }
      }

      await output.flush();
      await output.close();

      await refreshAvailableModels();
      _isImporting = false;
      notifyListeners();
    } catch (e) {
      debugPrint("❌ حدث خطأ أثناء استيراد النموذج: $e");
      _isImporting = false;
      notifyListeners();
    }
  }

  Future<void> deleteModel(File modelFile) async {
    try {
      if (await modelFile.exists()) {
        await modelFile.delete();
        final settingsBox = Hive.box<LlmSettings>('llm_settings_box');
        final settings = settingsBox.get(0) ?? LlmSettings();
        if (settings.modelPath == modelFile.path) {
          settings.modelPath = '';
          settingsBox.put(0, settings);
        }
        await refreshAvailableModels();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error deleting model: $e");
    }
  }

  Future<void> initializeModel(String modelPath, {bool supportVision = false}) async {
    if (_isInitializingModel) return;

    _selectedImage = null;

    _isInitializingModel = true;
    _initializingModelPath = modelPath;
    _setLoading(true);
    notifyListeners();

    final settingsBox = Hive.box<LlmSettings>('llm_settings_box');
    final settings = settingsBox.get(0) ?? LlmSettings();
    settings.modelPath = modelPath;
    settingsBox.put(0, settings);

    final errorMessage = await _service.initialize(
      modelPath,
      backend: settings.backend,
      systemPrompt: settings.useSystemPrompt ? settings.systemPrompt : '',
      supportVision: supportVision,
    );

    final ok = errorMessage == null;

    _isModelLoaded = ok;
    if (ok) {
      _activeModelPath = modelPath;
      _activeModelSupportsVision = supportVision;
    } else {
      _activeModelPath = null;
      _activeModelSupportsVision = false;
    }

    _isInitializingModel = false;
    _initializingModelPath = null;
    _setLoading(false);

    _addMessage(ChatMessage(
      content: ok
          ? 'النموذج جاهز للعمل! يمكنك البدء بالدردشة.'
          : '⚠️ فشل تهيئة النموذج.\nالسبب:\n$errorMessage',
      side: MessageSide.agent,
    ));

    notifyListeners();
  }

  Future<void> unloadModel() async {
    if (!_isModelLoaded) return;

    await stopGeneration();
    await _service.close();

    _isModelLoaded = false;
    _activeModelPath = null;
    _isLoading = false;
    _isStopping = false;
    _selectedImage = null;
    _activeModelSupportsVision = false;

    final settingsBox = Hive.box<LlmSettings>('llm_settings_box');
    final settings = settingsBox.get(0) ?? LlmSettings();
    settings.modelPath = '';
    settingsBox.put(0, settings);

    _messages.clear();

    notifyListeners();
  }

  /// Sends a user message to the local LLM.
  ///
  /// If [contextInjection] is provided (e.g. RAG passages retrieved from the
  /// user's own lectures), it is prepended to the prompt so the model can
  /// ground its answer in the material. The original [text] is what gets
  /// stored in the user-facing chat bubble.
  Future<void> sendMessage(String text, {String? contextInjection}) async {
    if ((text.trim().isEmpty && _selectedImage == null) || _isLoading || _isStopping) return;

    _setLoading(true);

    final imageToSend = _selectedImage;
    _selectedImage = null;

    _addMessage(ChatMessage(
      content: text,
      side: MessageSide.user,
      imagePath: imageToSend?.path,
    ));

    _currentAiMessageIndex = _messages.length;
    _messages.add(ChatMessage(content: '', side: MessageSide.agent));
    notifyListeners();

    // ✅ Build the actual prompt that goes to the model.
    //    We keep the user-facing bubble showing the raw [text], but
    //    prepend the retrieved context so the LLM has the grounding material.
    String prompt = text;
    if (contextInjection != null && contextInjection.trim().isNotEmpty) {
      prompt =
          'استعن بالمعلومات التالية من محاضراتك للإجابة على السؤال. '
          'إذا كانت المعلومات غير ذات صلة، تجاهلها وأجب بقدرتك العامة.\n\n'
          'معلومات مرجعية:\n$contextInjection\n\n'
          'سؤال المستخدم:\n$text';
    }

    _currentStopwatch = Stopwatch()..start();

    try {
      _subscription = _service.generate(prompt, imagePath: imageToSend?.path).listen(
        (token) {
          if (_currentAiMessageIndex != null && _currentAiMessageIndex! < _messages.length) {
            final currentContent = _messages[_currentAiMessageIndex!].content;
            _messages[_currentAiMessageIndex!] = ChatMessage(
              content: currentContent + token,
              side: MessageSide.agent,
            );
            notifyListeners();
          }
        },
        onDone: () {
          stopGeneration();
        },
        onError: (error) {
          debugPrint("❌ Error during generation: $error");
          stopGeneration();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("❌ Exception: $e");
      _setLoading(false);
    }
  }

  void _finalizeMessage(int index, double latency) {
    if (index < _messages.length) {
      final lastMsg = _messages[index];
      final backend = Hive.box<LlmSettings>('llm_settings_box').get(0)?.backend ?? '';
      _messages[index] = ChatMessage(
        content: lastMsg.content.trim(),
        side: MessageSide.agent,
        latencyMs: latency,
        accelerator: backend,
        imagePath: lastMsg.imagePath,
      );
    }
    _setLoading(false);
  }

  Future<void> stopGeneration() async {
    if (_isStopping) return;
    _isStopping = true;

    try {
      await _subscription?.cancel();
      _subscription = null;

      if (_currentAiMessageIndex != null && _currentStopwatch != null) {
        _currentStopwatch?.stop();
        _finalizeMessage(_currentAiMessageIndex!, _currentStopwatch!.elapsedMilliseconds.toDouble());
        _currentAiMessageIndex = null;
        _currentStopwatch = null;
      }

      await _service.stop();
      await Future.delayed(const Duration(milliseconds: 50));
    } catch (e) {
      debugPrint("❌ خطأ في إيقاف الجيل: $e");
    } finally {
      _isStopping = false;
      _setLoading(false);
      notifyListeners();
    }
  }

  void _addMessage(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    stopGeneration();
    _service.close();
    super.dispose();
  }
}
