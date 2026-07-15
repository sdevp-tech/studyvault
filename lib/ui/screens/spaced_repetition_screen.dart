// spaced_repetition_screen.dart - كود كامل مع دعم الترجمة
// تم تعديله: إزالة FloatingActionButton وإضافة زر إضافة في AppBar
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:study_vault/models/asset_model.dart';
import 'package:study_vault/services/spaced_repetition_service.dart';
import 'package:study_vault/ui/widgets/empty_state.dart';
import '../asset_viewer.dart';
import '../l10n/app_localizations.dart';

class SpacedRepetitionScreen extends StatefulWidget {
  const SpacedRepetitionScreen({super.key});

  @override
  State<SpacedRepetitionScreen> createState() => _SpacedRepetitionScreenState();
}

class _SpacedRepetitionScreenState extends State<SpacedRepetitionScreen>
    with SingleTickerProviderStateMixin {
  late SpacedRepetitionService cardService;
  late Box<AssetModel> assetBox;

  List<CardModel> dueCards = [];
  List<CardModel> upcomingCards = [];
  Map<String, dynamic> stats = {};

  int _currentCardIndex = 0;
  bool _showAnswer = false;
  bool _isReviewing = false;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final cardBox = Hive.box<CardModel>('cards_box');
    cardService = SpacedRepetitionService(cardBox);
    assetBox = Hive.box<AssetModel>('assets_box');

    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      dueCards = cardService.getDueCards();
      upcomingCards = cardService.getUpcomingCards();
      stats = cardService.getStatistics();
      _currentCardIndex = 0;
      _showAnswer = false;
      _isReviewing = false;
    });
  }

  // ====================== تصدير البطاقات ======================
  Future<void> _exportCards() async {
    final local = AppLocalizations.of(context);
    if (cardService.box.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('no_cards_to_export'))),
      );
      return;
    }

    try {
      final cards = cardService.box.values.toList();
      final jsonList = cards.map((card) => {
            'id': card.id,
            'assetId': card.assetId,
            'snippet': card.snippet,
            'nextReview': card.nextReview.toIso8601String(),
            'intervalDays': card.intervalDays,
            'ease': card.ease,
          }).toList();

      final jsonString = jsonEncode(jsonList);

      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'study_vault_cards_${DateTime.now().millisecondsSinceEpoch}.json';
      final file = File('${directory.path}/$fileName');

      await file.writeAsString(jsonString);

      await Share.shareXFiles([XFile(file.path)],
          text: '${local.translate('spaced_repetition_cards')} - StudyVault');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('export_success').replaceFirst('{count}', cards.length.toString()))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${local.translate('export_failed')}: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ====================== استيراد البطاقات ======================
  Future<void> _importCards() async {
    final local = AppLocalizations.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final List<dynamic> importedList = jsonDecode(content);

      int importedCount = 0;

      for (var item in importedList) {
        final card = CardModel(
          id: item['id'] ?? '${DateTime.now().millisecondsSinceEpoch}_$importedCount',
          assetId: item['assetId'] ?? 'imported',
          snippet: item['snippet'] ?? '',
          nextReview: DateTime.tryParse(item['nextReview'] ?? '') ?? DateTime.now().add(const Duration(days: 1)),
          intervalDays: item['intervalDays'] ?? 1,
          ease: item['ease'] ?? 3,
        );

        await cardService.box.put(card.id, card);
        importedCount++;
      }

      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('import_success').replaceFirst('{count}', importedCount.toString()))),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${local.translate('import_failed')}: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ====================== مراجعة البطاقة ======================
  Future<void> _reviewCard(int quality) async {
    final local = AppLocalizations.of(context);
    if (dueCards.isEmpty) return;

    final card = dueCards[_currentCardIndex];
    await cardService.updateCardAfterReview(card, quality);

    if (_currentCardIndex >= dueCards.length - 1) {
      setState(() {
        _isReviewing = false;
        _showAnswer = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('review_complete'))),
      );
      await _loadData();
    } else {
      setState(() {
        _currentCardIndex++;
        _showAnswer = false;
      });
    }
  }

  // ====================== حذف بطاقة واحدة ======================
  Future<void> _deleteCard(CardModel card) async {
    final local = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('delete_card')),
        content: Text(local.translate('confirm_delete_card')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(local.translate('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(local.translate('delete'))),
        ],
      ),
    );

    if (confirm == true) {
      await cardService.deleteCard(card.id);
      await _loadData();
    }
  }

  // ====================== حذف جميع البطاقات ======================
  Future<void> _deleteAllCards() async {
    final local = AppLocalizations.of(context);
    if (cardService.box.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('delete_all_cards')),
        content: Text(local.translate('confirm_delete_all_cards')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(local.translate('delete_all')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await cardService.box.clear();
      await _loadData();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(local.translate('all_cards_deleted')), backgroundColor: Colors.green),
      );
    }
  }

  // ====================== عرض تفاصيل البطاقة ======================
  void _showCardDetail(CardModel card) {
    final local = AppLocalizations.of(context);
    final asset = assetBox.get(card.assetId);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('card_details')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (asset != null) ...[
                ListTile(
                  leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                  title: Text(local.translate('source_file')),
                  subtitle: Text(asset.fileName, style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const Divider(),
              ],
              Text(local.translate('text'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  card.snippet,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              Text(local.translate('review_stats'), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                      label: Text('${local.translate('ease')}: ${card.ease}'),
                      backgroundColor: _getEaseColor(card.ease).withAlpha(30)),
                  Chip(label: Text('${card.intervalDays} ${local.translate('days')}')),
                  Chip(
                      label: Text(
                          '${local.translate('date')}: ${DateFormat.yMd('ar').format(card.nextReview)}')),
                  Chip(
                      label: Text(
                          '${local.translate('time')}: ${DateFormat.jm('ar').format(card.nextReview)}')),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: Text(local.translate('close'))),
          if (asset != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => AssetViewer(asset: asset)));
              },
              child: Text(local.translate('go_to_file')),
            ),
        ],
      ),
    );
  }

  // ====================== تعديل بطاقة ======================
  Future<void> _editCard(CardModel card) async {
    final local = AppLocalizations.of(context);
    final textController = TextEditingController(text: card.snippet);
    final easeController = TextEditingController(text: card.ease.toString());

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('edit_card')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 5,
                decoration: InputDecoration(
                    labelText: local.translate('card_text'), border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: easeController,
                decoration: InputDecoration(
                    labelText: local.translate('ease_level_1_5'), border: const OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(local.translate('ease_description'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () {
              final ease = int.tryParse(easeController.text) ?? card.ease;
              if (textController.text.isNotEmpty && ease >= 1 && ease <= 5) {
                Navigator.pop(context, {'text': textController.text, 'ease': ease});
              }
            },
            child: Text(local.translate('save')),
          ),
        ],
      ),
    );

    if (result != null) {
      card.snippet = result['text'];
      card.ease = result['ease'];
      await card.save();
      await _loadData();
    }
  }

  // ====================== إضافة بطاقة يدوية ======================
  Future<void> _showAddCardDialog() async {
    final local = AppLocalizations.of(context);
    final textController = TextEditingController();
    final easeController = TextEditingController(text: '3');

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(local.translate('add_card')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: local.translate('card_text'),
                  hintText: local.translate('enter_text_to_review'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: easeController,
                decoration: InputDecoration(
                    labelText: local.translate('initial_ease'), border: const OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(local.translate('ease_description'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(local.translate('cancel'))),
          ElevatedButton(
            onPressed: () {
              final ease = int.tryParse(easeController.text) ?? 3;
              if (textController.text.isNotEmpty && ease >= 1 && ease <= 5) {
                Navigator.pop(context, {'text': textController.text, 'ease': ease});
              }
            },
            child: Text(local.translate('add')),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await cardService.createCard(
          assetId: 'manual_${DateTime.now().millisecondsSinceEpoch}',
          snippet: result['text'],
        );

        await _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(local.translate('card_added'))),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${local.translate('error')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ====================== واجهة المراجعة ======================
  Widget _buildReviewCard() {
    final local = AppLocalizations.of(context);
    if (dueCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 20),
            Text('🎉 ${local.translate('great')}!',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(local.translate('no_cards_to_review'),
                style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => setState(() => _isReviewing = false),
              icon: const Icon(Icons.arrow_back),
              label: Text(local.translate('back')),
            ),
          ],
        ),
      );
    }

    final card = dueCards[_currentCardIndex];
    final asset = assetBox.get(card.assetId);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blueGrey[50],
          child: Row(
            children: [
              const Icon(Icons.timer, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${local.translate('card')} ${_currentCardIndex + 1} ${local.translate('of')} ${dueCards.length}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        '${local.translate('ease')}: ${card.ease} • ${local.translate('interval')}: ${card.intervalDays} ${local.translate('days')}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              if (asset != null)
                IconButton(
                  icon: const Icon(Icons.open_in_new, size: 18),
                  onPressed: () =>
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AssetViewer(asset: asset))),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(card.snippet,
                  style: const TextStyle(fontSize: 20, height: 1.6), textAlign: TextAlign.center),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration:
              BoxDecoration(color: Colors.grey[50], border: Border(top: BorderSide(color: Colors.grey[300]!))),
          child: Column(
            children: [
              if (!_showAnswer) ...[
                ElevatedButton.icon(
                  onPressed: () => setState(() => _showAnswer = true),
                  icon: const Icon(Icons.visibility),
                  label: Text(local.translate('show_answer_rate_ease')),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    if (_currentCardIndex < dueCards.length - 1) {
                      setState(() => _currentCardIndex++);
                    } else {
                      setState(() => _isReviewing = false);
                    }
                  },
                  child: Text(local.translate('skip')),
                ),
              ] else ...[
                Text(local.translate('how_easy_was_it'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildReviewButton(
                        quality: 1,
                        label: local.translate('forgot'),
                        icon: Icons.sentiment_very_dissatisfied,
                        color: Colors.red),
                    _buildReviewButton(
                        quality: 2,
                        label: local.translate('hard'),
                        icon: Icons.sentiment_dissatisfied,
                        color: Colors.orange),
                    _buildReviewButton(
                        quality: 3,
                        label: local.translate('good'),
                        icon: Icons.sentiment_neutral,
                        color: Colors.blue),
                    _buildReviewButton(
                        quality: 4,
                        label: local.translate('easy'),
                        icon: Icons.sentiment_satisfied,
                        color: Colors.green),
                    _buildReviewButton(
                        quality: 5,
                        label: local.translate('very_easy'),
                        icon: Icons.sentiment_very_satisfied,
                        color: Colors.teal),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewButton(
      {required int quality, required String label, required IconData icon, required Color color}) {
    return ElevatedButton.icon(
      onPressed: () => _reviewCard(quality),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(backgroundColor: color.withAlpha(30), foregroundColor: color),
    );
  }

  // ====================== قوائم البطاقات ======================
  Widget _buildDueCardsList() {
    final local = AppLocalizations.of(context);
    if (dueCards.isEmpty) {
      return Center(
        child: EmptyState(
          title: local.translate('no_cards_ready'),
          message: local.translate('all_cards_updated'),
          icon: Icons.check_circle_outline,
        ),
      );
    }

    return ListView(
      children: [
        _buildStatsCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${local.translate('ready_for_review')} (${dueCards.length})',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isReviewing = true),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(local.translate('start_review')),
              ),
            ],
          ),
        ),
        ...dueCards.map((card) => _buildCardItem(card, isDue: true)),
      ],
    );
  }

  Widget _buildAllCardsList() {
    final local = AppLocalizations.of(context);
    final hasAnyCards = dueCards.isNotEmpty || upcomingCards.isNotEmpty;

    if (!hasAnyCards) {
      return Center(
        child: EmptyState(
          title: local.translate('no_cards_yet'),
          message: local.translate('tap_plus_to_add_card'),
          icon: Icons.note_add,
        ),
      );
    }

    return ListView(
      children: [
        _buildStatsCard(),
        if (dueCards.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('${local.translate('ready_for_review')} (${dueCards.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...dueCards.map((card) => _buildCardItem(card, isDue: true)),
        ],
        if (upcomingCards.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(16, dueCards.isEmpty ? 16 : 24, 16, 8),
            child: Text('${local.translate('upcoming_reviews')} (${upcomingCards.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...upcomingCards.map((card) => _buildCardItem(card, isDue: false)),
        ],
      ],
    );
  }

  Widget _buildCardItem(CardModel card, {bool isDue = true}) {
    final local = AppLocalizations.of(context);
    final asset = assetBox.get(card.assetId);
    final assetName = asset?.fileName ?? local.translate('unknown_file');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDue ? Colors.orange.withAlpha(100) : Colors.blue.withAlpha(100)),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDue ? Colors.orange.withAlpha(30) : Colors.blue.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(isDue ? Icons.timer : Icons.calendar_today,
              color: isDue ? Colors.orange : Colors.blue),
        ),
        title: Text(card.shortSnippet,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(assetName, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            Row(
              children: [
                Chip(
                    label: Text('${local.translate('ease')}: ${card.ease}'),
                    backgroundColor: _getEaseColor(card.ease).withAlpha(30)),
                const SizedBox(width: 4),
                Chip(
                    label: Text('${card.intervalDays} ${local.translate('days')}'),
                    backgroundColor: Colors.grey[100]),
              ],
            ),
            const SizedBox(height: 2),
            Text(
                '${local.translate('review')}: ${DateFormat.yMd('ar').add_jm().format(card.nextReview)}',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          itemBuilder: (context) => [
            PopupMenuItem(
                value: 'view',
                child: Row(children: [
                  const Icon(Icons.visibility, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Text(local.translate('view'))
                ])),
            if (isDue)
              PopupMenuItem(
                  value: 'review',
                  child: Row(children: [
                    const Icon(Icons.check, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text(local.translate('review'))
                  ])),
            PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  const Icon(Icons.edit, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(local.translate('edit'))
                ])),
            PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  const Icon(Icons.delete, color: Colors.red, size: 18),
                  const SizedBox(width: 8),
                  Text(local.translate('delete'))
                ])),
          ],
          onSelected: (value) async {
            switch (value) {
              case 'view':
                _showCardDetail(card);
                break;
              case 'review':
                await cardService.updateCardAfterReview(card, 4);
                await _loadData();
                break;
              case 'edit':
                await _editCard(card);
                break;
              case 'delete':
                await _deleteCard(card);
                break;
            }
          },
        ),
        onTap: () => _showCardDetail(card),
        onLongPress: () => _editCard(card),
      ),
    );
  }

  Color _getEaseColor(int ease) {
    switch (ease) {
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.blue;
      case 4:
        return Colors.green;
      case 5:
        return Colors.teal;
      default:
        return Colors.grey;
    }
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
            Text('📊 ${local.translate('review_stats')}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatCircle(
                    value: stats['total']?.toString() ?? '0',
                    label: local.translate('all_cards'),
                    color: Colors.blue,
                    icon: Icons.library_books),
                _buildStatCircle(
                    value: stats['due']?.toString() ?? '0',
                    label: local.translate('ready_now'),
                    color: Colors.orange,
                    icon: Icons.timer),
                _buildStatCircle(
                    value: stats['upcoming']?.toString() ?? '0',
                    label: local.translate('upcoming'),
                    color: Colors.green,
                    icon: Icons.calendar_today),
              ],
            ),
            if (stats['averageEase'] != null && (stats['averageEase'] as double) > 0) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (stats['averageEase'] as double) / 5,
                backgroundColor: Colors.grey[200],
                color: _getEaseColor((stats['averageEase'] as double).round()),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(local.translate('average_ease'), style: const TextStyle(fontSize: 12)),
                  Text('${(stats['averageEase'] as double).toStringAsFixed(1)}/5',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getEaseColor((stats['averageEase'] as double).round()))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCircle(
      {required String value, required String label, required Color color, required IconData icon}) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
              color: color.withAlpha(30), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10), textAlign: TextAlign.center),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    if (_isReviewing) {
      return Scaffold(
        appBar: AppBar(
          title: Text(local.translate('reviewing')),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _isReviewing = false),
          ),
        ),
        body: _buildReviewCard(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(local.translate('spaced_repetition')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: const Icon(Icons.timer), text: local.translate('review_now')),
            Tab(icon: const Icon(Icons.library_books), text: local.translate('all_cards')),
          ],
        ),
        actions: [
          // ✅ زر إضافة البطاقة الجديد في شريط التطبيقات بدلاً من FAB
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: local.translate('add_card'),
            onPressed: () => _showAddCardDialog(),
          ),
          PopupMenuButton<String>(
            itemBuilder: (context) => [
              PopupMenuItem(value: 'export', child: Text(local.translate('export_cards'))),
              PopupMenuItem(value: 'import', child: Text(local.translate('import_cards'))),
              PopupMenuItem(value: 'clear_all', child: Text(local.translate('delete_all_cards'))),
            ],
            onSelected: (value) async {
              switch (value) {
                case 'export':
                  await _exportCards();
                  break;
                case 'import':
                  await _importCards();
                  break;
                case 'clear_all':
                  await _deleteAllCards();
                  break;
              }
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDueCardsList(),
          _buildAllCardsList(),
        ],
      ),
      // ✅ تم إزالة floatingActionButton بالكامل
    );
  }
}