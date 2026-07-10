import '../models/asset_model.dart';
import 'metadata_service.dart';

class InvertedIndexService {
  final MetadataService metadata;
  final Map<String, Set<String>> _index = {};

  InvertedIndexService(this.metadata);

  void indexAsset(AssetModel asset) {
    final text = '${asset.fileName} ${asset.extractedText ?? ''} ${(asset.notes ?? '')} ${asset.tags.join(' ')}'.toLowerCase();
    final tokens = _tokenize(text);
    for (final t in tokens) {
      _index.putIfAbsent(t, () => <String>{}).add(asset.id);
    }
  }

  void removeAsset(AssetModel asset) {
    for (final entry in _index.entries) {
      entry.value.remove(asset.id);
    }
  }

  Set<String> search(String query) {
    final tokens = _tokenize(query.toLowerCase());
    if (tokens.isEmpty) return {};
    Set<String>? result;
    for (final t in tokens) {
      final ids = _index[t] ?? {};
      if (result == null) result = Set<String>.from(ids);
      else result = result.intersection(ids);
      if (result.isEmpty) break;
    }
    return result ?? {};
  }

  List<String> _tokenize(String text) {
    final words = text.split(RegExp(r'[^a-z0-9\u0600-\u06FF]+')).where((s) => s.length > 1).toList();
    return words;
  }
}
