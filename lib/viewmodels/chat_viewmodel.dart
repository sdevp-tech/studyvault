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

  // ── تحسين الأداء: تجميع التوكنات وتقييد إعادة الرسم ──
  // Accumulate streamed tokens in a buffer and throttle UI rebuilds so a long
  // response no longer triggers hundreds of full widget-tree rebuilds.
  final StringBuffer _streamBuffer = StringBuffer();
  Timer? _renderThrottle;
  static const Duration _renderInterval = Duration(milliseconds: 40);

  // ── حارس الجيل: يمنع تداخل stream قديم مع stream جديد ──
  // كل استدعاء لـ sendMessage يولّد ID جديد؛ التوكنات القادمة بـ ID قديم تُهمل.
  // يحلّ ظاهرة "**" التي كانت تظهر حين يبدأ الطلب التالي قبل اكتمال إيقاف السابق.
  int _generationId = 0;
  bool _generationInFlight = false;

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
      // تفعيل وضع الاستيراد فوراً ليظهر شريط التقدم بحركة مستمرة (Indeterminate)
      _isImporting = true;
      _importProgress = 0.0;
      notifyListeners();

      // الحل الاحترافي: استخدام withReadStream: true
      // هذا يمنع نظام التشغيل من نسخ الملف إلى الكاش المؤقت، ويفتح تدفقاً مباشراً للبيانات
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['litert', 'litertlm', 'task', 'bin'],
        withReadStream: true,
      );

      // إذا ألغى المستخدم عملية الاختيار أو فشل فتح التدفق المباشر
      if (result == null || result.files.single.readStream == null) {
        _isImporting = false;
        notifyListeners();
        return;
      }

      PlatformFile file = result.files.single;

      Directory appDocDir = await getApplicationDocumentsDirectory();
      String permanentPath = p.join(appDocDir.path, file.name);
      File permanentFile = File(permanentPath);

      // أخذ الحجم الإجمالي للملف من بيانات النظام مباشرة
      final length = file.size;
      int copied = 0;

      // فتح ملف الوجهة للكتابة
      final output = permanentFile.openWrite();
      int lastNotifiedPercent = -1;

      // القراءة من المصدر مباشرة والكتابة في الوجهة مباشرة (عملية نسخ واحدة فقط)
      await for (var chunk in file.readStream!) {
        output.add(chunk);
        copied += chunk.length;

        if (length > 0) {
          _importProgress = copied / length;

          // تحديث الواجهة فقط عند تغير النسبة الصحيحة بمقدار 1% للحفاظ على سلاسة الإطارات
          int currentPercent = (_importProgress * 100).toInt();
          if (currentPercent != lastNotifiedPercent) {
            lastNotifiedPercent = currentPercent;
            notifyListeners();
          }
        }
      }

      // تأكيد كتابة البيانات وإغلاق الملفات
      await output.flush();
      await output.close();

      // تحديث القائمة وإيقاف وضع الاستيراد فوراً
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

  Future<void> initializeModel(String modelPath,
      {bool supportVision = false}) async {
    if (_isInitializingModel) return;

    // إزالة أي صورة محددة مسبقاً قبل تحميل النموذج الجديد كإجراء أمني
    _selectedImage = null;

    _isInitializingModel = true;
    _initializingModelPath = modelPath;
    _setLoading(true);
    notifyListeners();

    final settingsBox = Hive.box<LlmSettings>('llm_settings_box');
    final settings = settingsBox.get(0) ?? LlmSettings();
    settings.modelPath = modelPath;
    settingsBox.put(0, settings);

    // استقبال رسالة الخطأ بدلاً من القيمة المنطقية
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
      // حفظ حالة دعم الصور للنموذج الحالي لكي تستخدمها واجهة المستخدم
      _activeModelSupportsVision = supportVision;
    } else {
      _activeModelPath = null;
      _activeModelSupportsVision = false;
    }

    _isInitializingModel = false;
    _initializingModelPath = null;
    _setLoading(false);

    // إظهار تفاصيل الخطأ بدقة في حال الفشل
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
    _activeModelSupportsVision = false; // إعادة تعيين الحالة عند تفريغ النموذج

    final settingsBox = Hive.box<LlmSettings>('llm_settings_box');
    final settings = settingsBox.get(0) ?? LlmSettings();
    settings.modelPath = '';
    settingsBox.put(0, settings);

    _messages.clear();

    notifyListeners();
  }

  /// Sends a message to the local model.
  ///
  /// [contextInjection] (used by the on-device RAG "Chat With Your Lectures"
  /// feature) is prepended to the prompt that reaches the engine, but is NOT
  /// shown in the UI — the chat bubble still displays only the user's [text].
  Future<void> sendMessage(String text, {String? contextInjection}) async {
    if ((text.trim().isEmpty && _selectedImage == null) ||
        _isLoading ||
        _isStopping) {
      return;
    }

    // ضمان اكتمال إيقاف الجيل السابق قبل بدء جديد (يلغي التتبع المُتداخل)
    if (_generationInFlight) {
      await stopGeneration();
    }

    _setLoading(true);

    final imageToSend = _selectedImage;
    _selectedImage = null;

    _addMessage(ChatMessage(
      content: text,
      side: MessageSide.user,
      imagePath: imageToSend?.path,
    ));

    // ثبّت فهرس الفقاعة الفارغة الآن (قبل أن يبدأ stream) لتفادي سباق المؤشر
    _currentAiMessageIndex = _messages.length;
    _messages.add(ChatMessage(content: '', side: MessageSide.agent));
    notifyListeners();

    // إعادة تهيئة مخزن التوكنات لهذه الاستجابة الجديدة
    _streamBuffer.clear();

    // تعيين ID الجيل الحالي — أي توكن قادم من جيل أقدم سيُهمل
    final int myGenerationId = ++_generationId;
    _generationInFlight = true;

    // بناء الموجّه الفعلي المُرسل للنموذج (مع حقن سياق المحاضرات إن وُجد)
    final String prompt = (contextInjection == null || contextInjection.isEmpty)
        ? text
        : 'اعتمد فقط على المقتطفات التالية من ملفات الطالب للإجابة، '
            'وإذا لم تكفِ المعلومات فاذكر ذلك بوضوح.\n\n'
            '<context>\n$contextInjection\n</context>\n\n'
            'السؤال: $text';

    _currentStopwatch = Stopwatch()..start();

    try {
      _subscription =
          _service.generate(prompt, imagePath: imageToSend?.path).listen(
        (token) {
          // تجاهل التوكنات المتأخرة من جيل سبق (إن وُجدت)
          if (myGenerationId != _generationId) return;
          if (_currentAiMessageIndex == null) return;
          if (_currentAiMessageIndex! >= _messages.length) return;

          _streamBuffer.write(token);
          _messages[_currentAiMessageIndex!] = ChatMessage(
            content: _streamBuffer.toString(),
            side: MessageSide.agent,
          );
          // بدلاً من إعادة رسم الواجهة عند كل توكن، نقيّد التحديث زمنياً
          _scheduleRender();
        },
        onDone: () {
          if (myGenerationId != _generationId) return;
          stopGeneration();
        },
        onError: (error) {
          if (myGenerationId != _generationId) return;
          debugPrint("❌ Error during generation: $error");
          stopGeneration();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint("❌ Exception: $e");
      _generationInFlight = false;
      _setLoading(false);
    }
  }

  /// تقييد معدل إعادة رسم الواجهة أثناء تدفق التوكنات.
  void _scheduleRender() {
    if (_renderThrottle?.isActive ?? false) return;
    _renderThrottle = Timer(_renderInterval, () {
      notifyListeners();
    });
  }

  void _finalizeMessage(int index, double latency) {
    if (index < _messages.length) {
      final lastMsg = _messages[index];
      final backend =
          Hive.box<LlmSettings>('llm_settings_box').get(0)?.backend ?? '';
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

    // إلغاء أي تحديث مؤجل وضمان عرض المحتوى النهائي كاملاً
    _renderThrottle?.cancel();
    _renderThrottle = null;

    // علِّم الـ listener أنّ هذا الجيل قد انتهى — أي توكن متأخّر سيُهمل
    _generationId++;

    try {
      await _subscription?.cancel();
      _subscription = null;

      if (_currentAiMessageIndex != null && _currentStopwatch != null) {
        _currentStopwatch?.stop();
        _finalizeMessage(_currentAiMessageIndex!,
            _currentStopwatch!.elapsedMilliseconds.toDouble());
        _currentAiMessageIndex = null;
        _currentStopwatch = null;
      }

      await _service.stop();
      // إعطاء الوقت للـ Kotlin لإكمال cancelAndJoin + إنشاء المحادثة الجديدة
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (e) {
      debugPrint("❌ خطأ في إيقاف الجيل: $e");
    } finally {
      _isStopping = false;
      _generationInFlight = false;
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
    _renderThrottle?.cancel();
    stopGeneration();
    _service.close();
    super.dispose();
  }
}
