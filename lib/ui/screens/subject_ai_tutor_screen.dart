import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:flutter_markdown_community/flutter_markdown.dart';

import '../../models/asset_model.dart';
import '../../models/chat_message.dart';
import '../../services/rag_service.dart';
import '../../viewmodels/chat_viewmodel.dart';
import '../l10n/app_localizations.dart';

/// "Chat With Your Lectures" — fully on-device Retrieval-Augmented Generation.
///
/// Retrieves the most relevant passages from the subject's already-extracted
/// text (via [RagService]) and injects them as grounding context into the
/// shared local-LLM [ChatViewModel]. Nothing leaves the device.
class SubjectAiTutorScreen extends StatefulWidget {
  final String field;
  final String year;
  final String subject;

  const SubjectAiTutorScreen({
    super.key,
    required this.field,
    required this.year,
    required this.subject,
  });

  @override
  State<SubjectAiTutorScreen> createState() => _SubjectAiTutorScreenState();
}

class _SubjectAiTutorScreenState extends State<SubjectAiTutorScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final RagService _rag;
  bool _hasSources = false;

  @override
  void initState() {
    super.initState();
    final assetBox = Hive.box<AssetModel>('assets_box');
    _rag = RagService(assetBox);
    _hasSources =
        _rag.hasIndexedContent(widget.field, widget.year, widget.subject);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _send(ChatViewModel vm) async {
    final text = _controller.text.trim();
    if (text.isEmpty || vm.isLoading || !vm.isModelLoaded) return;

    _controller.clear();

    // Retrieve grounding context from the subject's own material.
    final context = _rag.buildContext(
      widget.field,
      widget.year,
      widget.subject,
      text,
    );

    await vm.sendMessage(text, contextInjection: context);
  }

  Widget _bubble(BuildContext context, ChatMessage msg) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isUser = msg.side == MessageSide.user;
    final bubbleColor = isUser
        ? theme.colorScheme.primary
        : (isDark ? Colors.grey.shade800 : Colors.grey.shade200);

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(18),
          ),
          child: isUser
              ? Text(msg.content,
                  style: const TextStyle(color: Colors.white, fontSize: 16))
              : MarkdownBody(
                  data: msg.content.isEmpty ? '…' : msg.content,
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                        color: theme.colorScheme.onSurface, fontSize: 16),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _imageOfMessage(ChatMessage msg) {
    if (msg.imagePath == null || msg.imagePath!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(msg.imagePath!),
          height: 120,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    final vm = context.watch<ChatViewModel>();
    final theme = Theme.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Tutor', style: TextStyle(fontSize: 18)),
            Text(
              widget.subject,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ),
        actions: [
          if (vm.isLoading)
            IconButton(
              icon: const Icon(Icons.stop_circle, color: Colors.red),
              onPressed: vm.stopGeneration,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_hasSources)
              Container(
                width: double.infinity,
                color: Colors.orange.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(10),
                child: Text(
                  'لا يوجد محتوى نصي مفهرس لهذه المادة بعد. أضف ملفات PDF أو ملاحظات ليتمكن المساعد من الإجابة بالاعتماد عليها.',
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            if (!vm.isModelLoaded)
              Container(
                width: double.infinity,
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                padding: const EdgeInsets.all(10),
                child: Text(
                  'يرجى تشغيل نموذج ذكاء اصطناعي محلي أولاً من شاشة "الدردشة الذكية".',
                  style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: vm.messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'اطرح سؤالاً عن محاضرات هذه المادة وسيجيب المساعد بالاعتماد على ملفاتك المحفوظة — دون اتصال بالإنترنت.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: vm.messages.length,
                      itemBuilder: (context, index) {
                        final msg = vm.messages[index];
                        return Column(
                          crossAxisAlignment: msg.side == MessageSide.user
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            _imageOfMessage(msg),
                            _bubble(context, msg),
                          ],
                        );
                      },
                    ),
            ),
            if (vm.isLoading) const LinearProgressIndicator(minHeight: 3),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !vm.isLoading && vm.isModelLoaded,
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        hintText: local.translate('send_message_hint'),
                        filled: true,
                        fillColor: theme.brightness == Brightness.dark
                            ? theme.colorScheme.surfaceContainerHighest
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(23),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(vm),
                    ),
                  ),
                  const SizedBox(width: 7),
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: (vm.isLoading || !vm.isModelLoaded)
                        ? Colors.grey[400]
                        : theme.colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: (vm.isLoading || !vm.isModelLoaded)
                          ? null
                          : () => _send(vm),
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
