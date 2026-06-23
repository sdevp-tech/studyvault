// chat_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // تم استيرادها لتمكين استخدام الحافظة (Clipboard)
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_markdown_community/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart'; 
import '../../viewmodels/chat_viewmodel.dart';
import '../../models/chat_message.dart';
import '../l10n/app_localizations.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker(); 

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImage(ChatViewModel viewModel) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80, 
      );
      if (image != null) {
        viewModel.setImage(File(image.path));
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showAvailableModels(BuildContext context, ChatViewModel viewModel) {
    final local = AppLocalizations.of(context);
    final theme = Theme.of(context);
    
    bool isVisionEnabled = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: !viewModel.isInitializingModel && !viewModel.isImporting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Consumer<ChatViewModel>(
                builder: (context, vm, child) {
                  final models = vm.availableModels;
                  final bool isAnyModelActive = vm.isModelLoaded;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            local.translate('available_models'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              fontSize: 20,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        
                        if (isAnyModelActive)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orange, size: 22),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    "يوجد نموذج قيد العمل حالياً. يرجى إيقافه من أيقونة الطاقة في الشريط العلوي لتتمكن من تشغيل نموذج آخر.",
                                    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        SwitchListTile(
                          title: const Text("دعم قراءة الصور (Vision)"),
                          subtitle: const Text("قم بتفعيله فقط للنماذج المتعددة الوسائط"),
                          value: isVisionEnabled,
                          activeThumbColor: theme.colorScheme.primary,
                          secondary: const Icon(Icons.image_search),
                          onChanged: (vm.isInitializingModel || vm.isImporting || isAnyModelActive)
                              ? null 
                              : (val) {
                                  setModalState(() {
                                    isVisionEnabled = val;
                                  });
                                },
                        ),
                        
                        const Divider(),

                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.withValues(alpha: 0.2),
                            child: const Icon(Icons.add, color: Colors.green),
                          ),
                          title: Text(
                            local.translate('import_new_model'),
                            style: TextStyle(color: theme.colorScheme.onSurface),
                          ),
                          onTap: vm.isImporting 
                              ? null 
                              : () {
                                  vm.pickAndImportModel();
                                },
                        ),
                        
                        if (vm.isImporting)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      vm.importProgress == 0.0 
                                          ? "جاري اختيار وتحضير الملف..." 
                                          : "جاري النقل والتجهيز...",
                                      style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
                                    ),
                                    Text(
                                      "${(vm.importProgress * 100).toStringAsFixed(1)}%",
                                      style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                LinearProgressIndicator(
                                  value: vm.importProgress > 0.0 ? vm.importProgress : null,
                                  borderRadius: BorderRadius.circular(10),
                                  minHeight: 6,
                                ),
                              ],
                            ),
                          ),

                        const Divider(),
                        if (models.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              local.translate('no_models_imported'),
                              style: TextStyle(color: theme.colorScheme.onSurface),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: models.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, index) {
                                final file = models[index];
                                final isThisModelLoading = vm.isInitializingModel && vm.initializingModelPath == file.path;
                                final isThisSpecificModelActive = vm.activeModelName == p.basename(file.path);

                                return Column(
                                  children: [
                                    ListTile(
                                      leading: Icon(
                                        Icons.model_training, 
                                        color: isThisSpecificModelActive ? Colors.green : theme.iconTheme.color
                                      ),
                                      title: Text(
                                        p.basename(file.path),
                                        style: TextStyle(
                                          color: isThisSpecificModelActive ? Colors.green : theme.colorScheme.onSurface,
                                          fontWeight: isThisSpecificModelActive ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: isThisModelLoading
                                                ? const SizedBox(
                                                    width: 20, 
                                                    height: 20, 
                                                    child: CircularProgressIndicator(strokeWidth: 2.5)
                                                  )
                                                : Icon(
                                                    Icons.play_arrow, 
                                                    color: (vm.isInitializingModel || isAnyModelActive) ? Colors.grey : Colors.blue
                                                  ),
                                            tooltip: local.translate('activate_model'),
                                            onPressed: (vm.isInitializingModel || isAnyModelActive)
                                                ? null 
                                                : () async {
                                                    await vm.initializeModel(file.path, supportVision: isVisionEnabled);
                                                    if (ctx.mounted) Navigator.pop(ctx);
                                                  },
                                          ),
                                          IconButton(
                                            icon: Icon(
                                              Icons.delete, 
                                              color: (vm.isInitializingModel || vm.isImporting || isThisSpecificModelActive) ? Colors.grey : Colors.red
                                            ),
                                            tooltip: local.translate('delete_model'),
                                            onPressed: (vm.isInitializingModel || vm.isImporting || isThisSpecificModelActive) 
                                                ? null 
                                                : () => vm.deleteModel(file),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (isThisModelLoading)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "جاري تهيئة النموذج في الذاكرة...",
                                              style: TextStyle(color: theme.colorScheme.primary, fontSize: 12),
                                            ),
                                            const SizedBox(height: 4),
                                            LinearProgressIndicator(
                                              borderRadius: BorderRadius.circular(10),
                                              minHeight: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _bubble(ChatMessage msg, bool isUser) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    final aiBubbleColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;
    final aiTextColor = theme.colorScheme.onSurface;

    return Column(
      crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: isUser ? theme.colorScheme.primary : aiBubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(22),
              topRight: const Radius.circular(22),
              bottomLeft: isUser ? const Radius.circular(22) : const Radius.circular(8),
              bottomRight: isUser ? const Radius.circular(8) : const Radius.circular(22),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.06),
                blurRadius: 6,
                spreadRadius: 1,
                offset: const Offset(0, 2),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (msg.imagePath != null && msg.imagePath!.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: msg.content.isNotEmpty ? 10.0 : 0.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(msg.imagePath!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              if (msg.content.isNotEmpty)
                isUser
                    ? Text(
                        msg.content,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      )
                    : MarkdownBody(
                        data: msg.content,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: aiTextColor, fontSize: 16),
                          code: TextStyle(
                            backgroundColor: isDark ? Colors.black54 : Colors.grey.shade300,
                            color: isDark ? Colors.greenAccent : Colors.black87,
                            fontSize: 14,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: isDark ? Colors.black87 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          blockquoteDecoration: BoxDecoration(
                            border: Border(left: BorderSide(color: theme.colorScheme.secondary, width: 4)),
                          ),
                          listBullet: TextStyle(color: aiTextColor, fontSize: 16),
                        ),
                      ),
            ],
          ),
        ),
        
        // شريط الإجراءات أسفل الرسالة (يحتوي على تفاصيل السرعة وأيقونة النسخ)
        Padding(
          padding: EdgeInsets.only(
            left: isUser ? 0 : 16,
            right: isUser ? 16 : 0,
            bottom: 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isUser && msg.latencyMs > 0) ...[
                Text(
                  "${msg.latencyMs.toInt()} ms • ${msg.accelerator}",
                  style: TextStyle(
                    fontSize: 11, 
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade700, 
                    fontStyle: FontStyle.italic
                  ),
                ),
                const SizedBox(width: 10),
              ],
              // زر أيقونة النسخ التفاعلي
              GestureDetector(
                onTap: () {
                  if (msg.content.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: msg.content));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isUser ? "تم نسخ سؤالك بنجاح" : "تم نسخ رد الـ AI بنجاح"),
                        duration: const Duration(milliseconds: 900),
                        behavior: SnackBarBehavior.floating,
                        width: 220,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    );
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.copy_rounded,
                    size: 15,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final viewModel = context.watch<ChatViewModel>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    final String? activeModelName = viewModel.activeModelName;
    final bool canPickImage = viewModel.isModelLoaded && viewModel.activeModelSupportsVision && !viewModel.isLoading;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
        title: Row(
          children: [
            Icon(Icons.sensors, color: theme.colorScheme.secondary, size: 28),
            const SizedBox(width: 8),
            Text(
              local.translate('ai_edge_chat'),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: local.translate('models'),
            icon: Icon(Icons.folder_special, color: theme.iconTheme.color),
            onPressed: () => _showAvailableModels(context, viewModel),
          ),
          if (viewModel.isModelLoaded)
            IconButton(
              tooltip: local.translate('unload_model'),
              icon: const Icon(Icons.power_settings_new, color: Colors.orange),
              onPressed: () async {
                await viewModel.unloadModel();
              },
            ),
          if (viewModel.isLoading)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              tooltip: local.translate('stop_response'),
              onPressed: () => viewModel.stopGeneration(),
            ),
        ],
        elevation: 1,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (activeModelName != null)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                color: isDark ? theme.colorScheme.primaryContainer : Colors.blue.shade50,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.model_training, size: 19, color: theme.colorScheme.secondary),
                      const SizedBox(width: 6),
                      Text(
                        activeModelName,
                        style: TextStyle(
                          fontWeight: FontWeight.w500, 
                          color: theme.colorScheme.onSurface
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: viewModel.messages.length,
                itemBuilder: (context, index) {
                  final msg = viewModel.messages[index];
                  final isUser = msg.side == MessageSide.user;
                  return _bubble(msg, isUser);
                },
              ),
            ),
            if (viewModel.isLoading) const LinearProgressIndicator(minHeight: 3),
            
            if (viewModel.selectedImage != null)
              Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        viewModel.selectedImage!,
                        height: 100,
                        width: 100,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => viewModel.setImage(null), 
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
              child: Row(
                children: [
                  Tooltip(
                    message: !viewModel.isModelLoaded
                        ? "يرجى تشغيل نموذج أولاً"
                        : !viewModel.activeModelSupportsVision
                            ? "النموذج الحالي مخصص للنصوص ولا يدعم الصور"
                            : "إرفاق صورة",
                    child: IconButton(
                      icon: Icon(
                        Icons.image, 
                        color: canPickImage ? theme.iconTheme.color : Colors.grey.shade400,
                      ),
                      onPressed: canPickImage ? () => _pickImage(viewModel) : null,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !viewModel.isLoading && viewModel.isModelLoaded,
                      maxLines: null,
                      minLines: 1,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 15),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 18),
                        hintText: viewModel.isModelLoaded 
                            ? local.translate('send_message_hint') 
                            : "يرجى تشغيل نموذج من القائمة بالاستمرار",
                        hintStyle: TextStyle(color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        filled: true,
                        fillColor: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide.none),
                        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (val) async {
                        if ((val.trim().isNotEmpty || viewModel.selectedImage != null) && viewModel.isModelLoaded) {
                          await viewModel.sendMessage(val);
                          _controller.clear();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 7),
                  Tooltip(
                    message: viewModel.isLoading
                        ? local.translate('wait_for_response')
                        : local.translate('send'),
                    child: CircleAvatar(
                      radius: 23,
                      backgroundColor: (viewModel.isLoading || !viewModel.isModelLoaded)
                          ? Colors.grey[400] 
                          : theme.colorScheme.primary,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: (viewModel.isLoading || !viewModel.isModelLoaded)
                            ? null
                            : () async {
                                if (_controller.text.trim().isNotEmpty || viewModel.selectedImage != null) {
                                  await viewModel.sendMessage(_controller.text);
                                  _controller.clear();
                                }
                              },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}