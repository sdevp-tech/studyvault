class SummarizerService {
  List<String> summarize(String text, {int maxSentences = 3}) {
    final sentences = _splitSentences(text);
    if (sentences.length <= maxSentences) return sentences;
    final freq = <String, int>{};
    final words = text.toLowerCase().split(RegExp(r'[^a-z0-9\u0600-\u06FF]+')).where((w) => w.length > 2);
    for (final w in words) freq[w] = (freq[w] ?? 0) + 1;
    final scores = <int, double>{};
    for (int i = 0; i < sentences.length; i++) {
      final s = sentences[i].toLowerCase();
      final ws = s.split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'));
      double sc = 0;
      for (final w in ws) {
        sc += (freq[w] ?? 0);
      }
      scores[i] = sc;
    }
    final sorted = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(maxSentences).map((e) => sentences[e.key]).toList();
    return top;
  }

  List<String> _splitSentences(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?؟])\s+'));
    return parts.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }
}
