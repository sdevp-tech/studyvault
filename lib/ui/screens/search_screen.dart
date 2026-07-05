import 'dart:io';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../models/asset_model.dart';
import '../../services/metadata_service.dart';
import '../../services/inverted_index_service.dart';
import '../../services/storage_service.dart';
import '../asset_viewer.dart';
import 'main_screen.dart';
import '../l10n/app_localizations.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({Key? key}) : super(key: key);

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final MetadataService metadata;
  late final InvertedIndexService indexer;
  final StorageService storage = StorageService();
  String query = '';
  List<AssetModel> results = [];
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final box = Hive.box<AssetModel>('assets_box');
    metadata = MetadataService(box, storage);
    indexer = InvertedIndexService(metadata);

    for (final asset in metadata.box.values) {
      indexer.indexAsset(asset);
    }

    setState(() => _isInitializing = false);
  }

    void _search(String q) {
    setState(() {
      query = q;
      if (q.isEmpty) {
        results = [];
      } else {
        // 1. جلب النتائج من الفهرس (للبحث في الكلمات الكاملة والمحتوى)
        final ids = indexer.search(q);
        
        // 2. تحويل نص البحث إلى حروف صغيرة لضمان دقة البحث بغض النظر عن حالة الأحرف
        final lowerQuery = q.toLowerCase();

        results = metadata.box.values.where((a) {
          // الشرط الأول: هل الملف موجود في نتائج الفهرس؟
          if (ids.contains(a.id)) return true;

          // الشرط الثاني (الحل لمشكلتك): هل جزء من اسم الملف يحتوي على نص البحث؟
          if (a.fileName.toLowerCase().contains(lowerQuery)) return true;

          // الشرط الثالث (اختياري ولكنه مفيد): البحث الجزئي داخل الملاحظات أو النص المستخرج 
          // تحسباً لعدم عثور الفهرس على أجزاء الكلمات
          if (a.notes != null && a.notes!.toLowerCase().contains(lowerQuery)) return true;
          if (a.extractedText != null && a.extractedText!.toLowerCase().contains(lowerQuery)) return true;

          return false;
        }).toList();
      }
    });
  }


  Widget _highlightText(String text, String query) {
    if (query.isEmpty) return Text(text);
    final lower = text.toLowerCase();
    final qLower = query.toLowerCase();
    final start = lower.indexOf(qLower);
    if (start < 0) return Text(text);

    final end = start + query.length;
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: text.substring(0, start), style: const TextStyle(color: Colors.black)),
          TextSpan(text: text.substring(start, end), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          TextSpan(text: text.substring(end), style: const TextStyle(color: Colors.black)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: Text(local.translate('search'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(local.translate('search')),
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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: local.translate('search_hint'),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: query.isEmpty
                        ? Text(local.translate('type_to_search'))
                        : Text(local.translate('no_results_found'))
                  )
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final a = results[i];
                      final snippet = (a.notes?.isNotEmpty == true ? a.notes! : (a.extractedText ?? ''))
                          .split('\n')
                          .firstWhere(
                            (s) => s.toLowerCase().contains(query.toLowerCase()),
                            orElse: () => a.fileName,
                          );

                      return ListTile(
                        leading: a.thumbnailPath != null
                            ? Image.file(File(a.thumbnailPath!), width: 56, height: 56, fit: BoxFit.cover)
                            : const Icon(Icons.insert_drive_file),
                        title: _highlightText(a.fileName, query),
                        subtitle: _highlightText(snippet, query),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => AssetViewer(asset: a)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}