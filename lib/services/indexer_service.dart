import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import 'thumbnail_util.dart';
import 'pdf_utils.dart';
import 'storage_service.dart';
import 'metadata_service.dart';
import '../models/asset_model.dart';

class IndexerService {
  final StorageService storage;
  final MetadataService metadata;
  
  static const int MAX_PDF_PAGES_FOR_INDEXING = 100;

  IndexerService(this.storage, this.metadata);

  Future<void> indexFile(AssetModel asset) async {
    try {
      final vault = await storage.ensureStudyVault();
      final baseThumbDir = p.join(vault.path, '.thumbnails');
      final thumbDir = Directory(baseThumbDir);
      if (!await thumbDir.exists()) await thumbDir.create(recursive: true);

      String? thumb;
      
      // توليد صورة مصغرة للملفات المرئية
      if (asset.type == 'photo') {
        thumb = await ThumbnailUtil.generateImageThumbnail(asset.filePath, baseThumbDir);
      } else if (asset.type == 'video') {
        thumb = await ThumbnailUtil.generateVideoThumbnail(asset.filePath, baseThumbDir);
      } 
      // استخراج النص من ملفات PDF مع الحد من الصفحات
      else if (asset.type == 'pdf') {
        await _indexPdfWithLimit(asset);
      }

      // تحديث مسار الصورة المصغرة إذا وجدت
      if (thumb != null && await File(thumb).exists()) {
        await metadata.updateThumbnail(asset.id, thumb);
      }
    } catch (e) {
      print('خطأ في فهرسة الملف ${asset.fileName}: $e');
    }
  }

  Future<void> _indexPdfWithLimit(AssetModel asset) async {
    try {
      // الحصول على معلومات الملف أولاً
      final pdfInfo = await getPdfInfo(asset.filePath);
      
      print('فهرسة PDF: ${pdfInfo.fileName}');
      print('عدد الصفحات: ${pdfInfo.pageCount}');
      print('حجم الملف: ${pdfInfo.fileSizeFormatted}');
      
      String? extractedText;
      
      // إذا كان الملف كبيراً جداً (أكثر من 100 صفحة)، استخدم استخراج محدود
      if (pdfInfo.isLargeFile) {
        print('ملف كبير - سيتم استخراج النص من أول $MAX_PDF_PAGES_FOR_INDEXING صفحة فقط');
        
        // استخراج النص في isolate منفصل لمنع تجميد UI
        extractedText = await compute(extractLimitedPdfCompute, asset.filePath);
      } else {
        // للملفات الصغيرة، استخدم الاستخراج العادي
        extractedText = await compute(extractTextFromPdfCompute, asset.filePath);
      }
      
      if (extractedText != null && extractedText.isNotEmpty) {
        await metadata.updateExtractedText(asset.id, extractedText);
        print('تم استخراج نص من ${pdfInfo.fileName} بنجاح');
      }
    } catch (e) {
      print('خطأ في فهرسة PDF ${asset.fileName}: $e');
      
      // محاولة الاستخراج من الصفحات الأولى فقط كنسخة احتياطية
      try {
        final extractedText = await compute(extractFirstFewPagesCompute, asset.filePath);
        if (extractedText != null && extractedText.isNotEmpty) {
          await metadata.updateExtractedText(asset.id, extractedText);
          print('تم استخراج نسخة مبسطة من ${asset.fileName}');
        }
      } catch (fallbackError) {
        print('فشل النسخة الاحتياطية أيضاً: $fallbackError');
      }
    }
  }

  Future<void> indexAllForSubject(String field, String year, String subject) async {
    final assets = metadata.getAssetsForSubject(field, year, subject);
    for (final a in assets) {
      await indexFile(a);
    }
  }
}
