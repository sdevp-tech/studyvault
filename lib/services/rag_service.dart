import 'package:hive/hive.dart';
import '../models/asset_model.dart';

/// A single retrieved passage of study material used to ground the local LLM.
class RagChunk {
  final String assetId;
  final String fileName;
  final String text;
  final double score;

  RagChunk({
    required this.assetId,
    required this.fileName,
    required this.text,
    required this.score,
  });
}

/// On-device Retrieval-Augmented Generation over the user's own lecture text.
///
/// Fully offline and private: it reuses the `extractedText` that
/// [IndexerService] already stores on each [AssetModel] (PDFs, notes, OCR),
/// performs lightweight keyword retrieval, and returns a compact context block
/// that the local LiteRT model answers from. Nothing leaves the device.
class RagService {
  final Box<AssetModel> assetBox;

  RagService(this.assetBox);

  static const int _chunkSize = 600; // characters per chunk
  static const int _chunkOverlap = 80;

  /// Returns every asset under the given subject (including all its lectures)
  /// that actually has extracted text to search.
  List<AssetModel> _sourcesForSubject(
      String field, String year, String subject) {
    return assetBox.values
        .where((a) =>
            a.field == field &&
            a.year == year &&
            a.subject == subject &&
            (a.extractedText != null && a.extractedText!.trim().isNotEmpty))
        .toList();
  }

  /// `true` when there is at least one indexed source to answer from.
  bool hasIndexedContent(String field, String year, String subject) {
    return _sourcesForSubject(field, year, subject).isNotEmpty;
  }

  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
        .where((w) => w.length > 1)
        .toList();
  }

  List<RagChunk> _splitIntoChunks(AssetModel asset) {
    final text = asset.extractedText ?? '';
    final chunks = <RagChunk>[];
    if (text.isEmpty) return chunks;

    int start = 0;
    while (start < text.length) {
      final end =
          (start + _chunkSize < text.length) ? start + _chunkSize : text.length;
      final slice = text.substring(start, end).trim();
      if (slice.isNotEmpty) {
        chunks.add(RagChunk(
          assetId: asset.id,
          fileName: asset.fileName,
          text: slice,
          score: 0,
        ));
      }
      if (end >= text.length) break;
      start = end - _chunkOverlap;
    }
    return chunks;
  }

  /// Retrieves the top-[topK] most relevant chunks for [query].
  List<RagChunk> retrieve(
    String field,
    String year,
    String subject,
    String query, {
    int topK = 4,
  }) {
    final queryTokens = _tokenize(query).toSet();
    if (queryTokens.isEmpty) return [];

    final scored = <RagChunk>[];
    for (final asset in _sourcesForSubject(field, year, subject)) {
      for (final chunk in _splitIntoChunks(asset)) {
        final chunkTokens = _tokenize(chunk.text);
        if (chunkTokens.isEmpty) continue;

        int hits = 0;
        for (final t in chunkTokens) {
          if (queryTokens.contains(t)) hits++;
        }
        if (hits == 0) continue;

        // Normalised term-frequency score with a small length penalty.
        final score = hits / (1 + (chunkTokens.length / 100.0));
        scored.add(RagChunk(
          assetId: chunk.assetId,
          fileName: chunk.fileName,
          text: chunk.text,
          score: score,
        ));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(topK).toList();
  }

  /// Builds a compact, bounded context block for the LLM, or `null` when no
  /// relevant passage was found.
  String? buildContext(
    String field,
    String year,
    String subject,
    String query, {
    int topK = 4,
    int maxChars = 3000,
  }) {
    final chunks = retrieve(field, year, subject, query, topK: topK);
    if (chunks.isEmpty) return null;

    final buffer = StringBuffer();
    for (final chunk in chunks) {
      final entry = '• (${chunk.fileName})\n${chunk.text}\n\n';
      if (buffer.length + entry.length > maxChars) break;
      buffer.write(entry);
    }

    final result = buffer.toString().trim();
    return result.isEmpty ? null : result;
  }
}
