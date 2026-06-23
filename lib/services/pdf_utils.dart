import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';

// دالة top-level لاستخدامها مع compute
Future<String?> extractTextFromPdfCompute(String pdfPath) async {
  return await extractTextFromPdf(pdfPath);
}

// دالة top-level أخرى
Future<String?> extractLimitedPdfCompute(String pdfPath) async {
  return await _extractPdfWithPageLimit(pdfPath, 100);
}

// دالة top-level للصفحات القليلة الأولى
Future<String?> extractFirstFewPagesCompute(String pdfPath) async {
  return await _extractPdfWithPageLimit(pdfPath, 10);
}

// الدوال الأساسية
const int MAX_EXTRACTED_PAGES = 100;

Future<String?> extractTextFromPdf(String pdfPath) async {
  try {
    final bytes = await File(pdfPath).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final StringBuffer buffer = StringBuffer();

    final int totalPages = document.pages.count;
    final int pagesToExtract = totalPages > MAX_EXTRACTED_PAGES 
        ? MAX_EXTRACTED_PAGES 
        : totalPages;

    print('استخراج النص من $pagesToExtract صفحة من أصل $totalPages');

    // معالجة الصفحات في أجزاء مع فواصل زمنية
    const int chunkSize = 5;
    
    for (int startPage = 0; startPage < pagesToExtract; startPage += chunkSize) {
      final int endPage = startPage + chunkSize - 1 < pagesToExtract 
          ? startPage + chunkSize - 1 
          : pagesToExtract - 1;
      
      try {
        final String chunkText = extractor.extractText(
          startPageIndex: startPage, 
          endPageIndex: endPage
        );
        
        if (chunkText.isNotEmpty) {
          buffer.writeln(chunkText);
          
          // إضافة رقم الصفحة للرجوع إليها
          if (startPage == endPage) {
            buffer.writeln('\n[صفحة ${startPage + 1}]\n');
          } else {
            buffer.writeln('\n[صفحات ${startPage + 1}-${endPage + 1}]\n');
          }
        }
      } catch (e) {
        print('خطأ في استخراج الصفحات $startPage-$endPage: $e');
        continue;
      }
      
      // إعطاء فرصة للواجهة للتحديث
      await Future.delayed(const Duration(milliseconds: 50));
    }

    document.dispose();
    final result = buffer.toString().trim();
    
    if (result.isEmpty) {
      return null;
    }
    
    // إضافة ملاحظة إذا تم اقتصار الاستخراج
    if (totalPages > MAX_EXTRACTED_PAGES) {
      final limitedResult = StringBuffer(result);
      limitedResult.writeln('\n\n--- ملاحظة: تم استخراج النص من أول $MAX_EXTRACTED_PAGES صفحة فقط ---');
      limitedResult.writeln('--- إجمالي صفحات الملف: $totalPages ---');
      return limitedResult.toString();
    }
    
    return result;
  } catch (e) {
    print('خطأ في استخراج النص من PDF: $e');
    return null;
  }
}

// دالة مساعدة للاستخراج المحدود
Future<String?> _extractPdfWithPageLimit(String pdfPath, int maxPages) async {
  try {
    final bytes = await File(pdfPath).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final StringBuffer buffer = StringBuffer();

    final int totalPages = document.pages.count;
    final int pagesToExtract = totalPages > maxPages ? maxPages : totalPages;

    for (int i = 0; i < pagesToExtract; i++) {
      final String pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
      if (pageText.isNotEmpty) {
        buffer.writeln('\n[صفحة ${i + 1}]');
        buffer.writeln(pageText);
      }
      
      // إضافة فاصل زمني كل 10 صفحات
      if (i % 10 == 0 && i > 0) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }

    document.dispose();
    final result = buffer.toString().trim();
    
    if (result.isEmpty) return null;
    
    // إضافة ملاحظة عن الاقتصار
    if (totalPages > maxPages) {
      return '$result\n\n[ملاحظة: تم استخراج النص من أول $maxPages صفحة فقط من أصل $totalPages]';
    }
    
    return result;
  } catch (e) {
    print('خطأ في _extractPdfWithPageLimit: $e');
    return null;
  }
}

// دالة للحصول على معلومات PDF
Future<PdfFileInfo> getPdfInfo(String pdfPath) async {
  try {
    final bytes = await File(pdfPath).readAsBytes();
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final int pageCount = document.pages.count;
    final fileSize = await File(pdfPath).length();
    
    document.dispose();
    
    return PdfFileInfo(
      pageCount: pageCount,
      fileSize: fileSize,
      isLargeFile: pageCount > MAX_EXTRACTED_PAGES,
      fileName: p.basename(pdfPath),
    );
  } catch (e) {
    print('خطأ في الحصول على معلومات PDF: $e');
    return PdfFileInfo(
      pageCount: 0,
      fileSize: 0,
      isLargeFile: false,
      fileName: p.basename(pdfPath),
      error: e.toString(),
    );
  }
}

class PdfFileInfo {
  final int pageCount;
  final int fileSize;
  final bool isLargeFile;
  final String fileName;
  final String? error;
  
  PdfFileInfo({
    required this.pageCount,
    required this.fileSize,
    required this.isLargeFile,
    required this.fileName,
    this.error,
  });
  
  String get fileSizeFormatted {
    if (fileSize < 1024) return '$fileSize بايت';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} ك.بايت';
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} م.بايت';
  }
}
