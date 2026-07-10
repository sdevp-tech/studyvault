import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../services/ocr_service.dart';

class TextExtractionService {
  final OcrService ocrService = OcrService();

  Future<ExtractedTextResult> extractTextFromFile({
    required String filePath,
    required String fileType,
  }) async {
    try {
      if (fileType == 'pdf') {
        return await _extractTextFromPdf(filePath);
      } else if (['photo', 'image'].contains(fileType)) {
        return await _extractTextFromImage(filePath);
      } else if (fileType == 'note') {
        return await _extractTextFromNote(filePath);
      } else if (fileType == 'video') {
        // يمكن استخراج النص من التعليقات/الترجمات إذا وجدت
        return ExtractedTextResult(fullText: '');
      }
      
      return ExtractedTextResult(fullText: '');
    } catch (e) {
      print('Text extraction error: $e');
      return ExtractedTextResult(fullText: '');
    }
  }

  Future<ExtractedTextResult> _extractTextFromPdf(String pdfPath) async {
    try {
      final bytes = await File(pdfPath).readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final List<PdfPage> pages = [];
      StringBuffer fullText = StringBuffer();

      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
        if (pageText.isNotEmpty) {
          fullText.writeln(pageText);
          
          pages.add(PdfPage(
            pageNumber: i + 1,
            content: pageText,
            paragraphs: _splitIntoParagraphs(pageText),
            sentences: _splitIntoSentences(pageText),
          ));
        }
      }

      document.dispose();
      
      return ExtractedTextResult(
        fullText: fullText.toString(),
        paragraphs: _splitIntoParagraphs(fullText.toString()),
        sentences: _splitIntoSentences(fullText.toString()),
        pages: pages,
      );
    } catch (e) {
      print('PDF extraction error: $e');
      return ExtractedTextResult(fullText: '');
    }
  }

  Future<ExtractedTextResult> _extractTextFromImage(String imagePath) async {
    final text = await ocrService.extractTextFromImageFile(imagePath);
    if (text != null) {
      return ExtractedTextResult(
        fullText: text,
        paragraphs: _splitIntoParagraphs(text),
        sentences: _splitIntoSentences(text),
      );
    }
    return ExtractedTextResult(fullText: '');
  }

  Future<ExtractedTextResult> _extractTextFromNote(String filePath) async {
    final file = File(filePath);
    final text = await file.readAsString();
    return ExtractedTextResult(
      fullText: text,
      paragraphs: _splitIntoParagraphs(text),
      sentences: _splitIntoSentences(text),
    );
  }

  List<String> _splitIntoParagraphs(String text) {
    // تقسيم الذكي للفقرات - يدعم العربية والإنجليزية
    final paragraphs = text.split(RegExp(r'\n\s*\n'));
    return paragraphs
        .where((p) => p.trim().isNotEmpty && p.trim().length > 10)
        .map((p) => p.trim())
        .toList();
  }

  List<String> _splitIntoSentences(String text) {
    // تقسيم الجمل مع دعم علامات الترقيم العربية والإنجليزية
    final sentences = text.split(RegExp(r'(?<=[.!?؟۔])[\s\n]+'));
    return sentences
        .where((s) => s.trim().isNotEmpty && s.trim().length > 5)
        .map((s) => s.trim())
        .toList();
  }

  List<String> extractKeywords(String text, {int limit = 15}) {
  // إزالة الكلمات الشائعة (stop words)
  final stopWords = {
    'و', 'في', 'من', 'على', 'أن', 'إلى', 'هو', 'هي', 'كان', 'يكون',
    'the', 'and', 'of', 'to', 'a', 'in', 'is', 'it', 'you', 'that'
  };
  
  final words = text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u0600-\u06FF]+'))
      .where((word) => 
          word.length > 2 && 
          !stopWords.contains(word) &&
          !RegExp(r'^\d+$').hasMatch(word))
      .toList();
  
  final freq = <String, int>{};
  for (final word in words) {
    freq[word] = (freq[word] ?? 0) + 1;
  }
  
  // Fixed: Properly sort and extract keys
  final sortedEntries = freq.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  
  return sortedEntries
      .take(limit)
      .map((e) => e.key)
      .toList();
}
}

class ExtractedTextResult {
  final String fullText;
  final List<String> paragraphs;
  final List<String> sentences;
  final List<PdfPage> pages;
  
  ExtractedTextResult({
    required this.fullText,
    this.paragraphs = const [],
    this.sentences = const [],
    this.pages = const [],
  });
  
  bool get hasContent => fullText.trim().isNotEmpty;
  bool get hasPages => pages.isNotEmpty;
  int get wordCount => fullText.split(RegExp(r'\s+')).length;
}

class PdfPage {
  final int pageNumber;
  final String content;
  final List<String> paragraphs;
  final List<String> sentences;
  
  PdfPage({
    required this.pageNumber,
    required this.content,
    required this.paragraphs,
    required this.sentences,
  });
  
  int get wordCount => content.split(RegExp(r'\s+')).length;
}