// storage_service.dart - FULL UPDATED VERSION
// Now cleans BOTH internal temp + external cache (fixes 1.8 GB leftover files)
// Fixed: Use getExternalCacheDirectories() instead of getExternalCacheDirectory()

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';

import '../models/asset_model.dart';

/// ─────────────────────────────────────────────────────────────
/// كلاس لإدارة الإلغاء (Cancel Token)
/// ─────────────────────────────────────────────────────────────
class CancelToken {
  bool _cancelled = false;

  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

class CancelException implements Exception {
  final String message;
  CancelException(this.message);

  @override
  String toString() => message;
}

/// ─────────────────────────────────────────────────────────────
/// StorageService - النسخة الكاملة والمُحسّنة
/// ─────────────────────────────────────────────────────────────
class StorageService {
  static const List<String> _typeFolders = [
    'videos',
    'pdfs',
    'audios',
    'photos',
    'notes',
    'other'
  ];
  static const String _thumbDirName = '.thumbnails';

  // ────── مجلد التطبيق الأساسي ──────
  Future<Directory> _appDocDir() async =>
      await getApplicationDocumentsDirectory();

  /// يضمن وجود مجلد StudyVault
  Future<Directory> ensureStudyVault() async {
    final base = await _appDocDir();
    final vault = Directory(p.join(base.path, 'StudyVault'));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    return vault;
  }

  // ────── إنشاء مجلدات ──────
  Future<Directory> createSubjectFolder(
      String field, String year, String subject) async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, field, year, subject));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> createLectureFolder(
      String field, String year, String subject, String lecture) async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, field, year, subject, lecture));
    if (!await dir.exists()) await dir.create(recursive: true);

    for (final folder in _typeFolders) {
      final sub = Directory(p.join(dir.path, folder));
      if (!await sub.exists()) await sub.create(recursive: true);
    }
    return dir;
  }

  // ────── نسخ الملف مع تقدم وإلغاء (محسّن للملفات الكبيرة) ──────
  Future<File> importFileWithProgress({
    required File sourceFile,
    required String destDirPath,
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final destDir = Directory(destDirPath);
    if (!await destDir.exists()) await destDir.create(recursive: true);

    // توليد اسم فريد
    String fileName = p.basename(sourceFile.path);
    File destFile = File(p.join(destDirPath, fileName));
    int counter = 1;
    while (await destFile.exists()) {
      final base = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      fileName = '${base}_$counter$ext';
      destFile = File(p.join(destDirPath, fileName));
      counter++;
    }

    final sourceLength = await sourceFile.length();
    if (sourceLength == 0) throw Exception('الملف فارغ');

    final rafSource = await sourceFile.open(mode: FileMode.read);
    final rafDest = await destFile.open(mode: FileMode.writeOnly);

    int totalRead = 0;
    const chunkSize = 512 * 1024; // 512 KB → مثالي للملفات الكبيرة
    int lastUpdateBytes = 0;
    final updateThreshold = (sourceLength * 0.005).toInt(); // تحديث كل 0.5%

    try {
      while (totalRead < sourceLength) {
        if (cancelToken?.isCancelled == true) {
          throw CancelException('تم إلغاء العملية من قبل المستخدم');
        }

        final bytes = await rafSource.read(chunkSize);
        if (bytes.isEmpty) break;

        await rafDest.writeFrom(bytes);
        totalRead += bytes.length;

        // Throttled progress
        if (onProgress != null &&
            (totalRead - lastUpdateBytes >= updateThreshold || totalRead >= sourceLength)) {
          final progress = totalRead / sourceLength;
          onProgress(progress);
          lastUpdateBytes = totalRead;

          // إعطاء الـ UI thread فرصة للتنفس
          if (totalRead % (chunkSize * 8) == 0) {
            await Future.delayed(Duration.zero);
          }
        }
      }

      await rafDest.flush();
      return destFile;
    } catch (e) {
      if (await destFile.exists()) await destFile.delete();
      rethrow;
    } finally {
      await rafSource.close();
      await rafDest.close();
    }
  }

  /// الدالة القديمة للتوافق
  Future<File> importFile(File source, String destDirPath) =>
      importFileWithProgress(
        sourceFile: source,
        destDirPath: destDirPath,
      );

  // ────── تحديد نوع الملف ──────
  String getFileType(String fileName) {
    final ext = p.extension(fileName).toLowerCase().replaceFirst('.', '');
    if (['mp4', 'mov', 'mkv', 'webm', 'avi'].contains(ext)) return 'video';
    if (['pdf'].contains(ext)) return 'pdf';
    if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(ext)) return 'audio';
    if (['jpg', 'jpeg', 'png', 'gif', 'heic', 'webp'].contains(ext)) {
      return 'photo';
    }
    if (['txt', 'md'].contains(ext)) return 'note';
    return 'other';
  }

  // ────── قوائم المجلدات ──────
  bool _isVisibleDir(Directory dir) {
    return !p.basename(dir.path).startsWith('.');
  }

  Future<List<String>> listFields() async {
    final vault = await ensureStudyVault();
    final list = <String>[];
    await for (final e in vault.list(followLinks: false)) {
      if (e is Directory && _isVisibleDir(e)) list.add(p.basename(e.path));
    }
    return list;
  }

  Future<List<String>> listYears(String field) async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, field));
    final list = <String>[];
    if (!await dir.exists()) return list;
    await for (final e in dir.list(followLinks: false)) {
      if (e is Directory && _isVisibleDir(e)) list.add(p.basename(e.path));
    }
    return list;
  }

  Future<List<String>> listSubjects(String field, String year) async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, field, year));
    final list = <String>[];
    if (!await dir.exists()) return list;
    await for (final e in dir.list(followLinks: false)) {
      if (e is Directory && _isVisibleDir(e)) list.add(p.basename(e.path));
    }
    return list;
  }

  Future<List<String>> listLectures(
      String field, String year, String subject) async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, field, year, subject));
    final list = <String>[];
    if (!await dir.exists()) return list;

    await for (final e in dir.list(followLinks: false)) {
      if (e is Directory) {
        final name = p.basename(e.path);
        if (_isVisibleDir(e) && !_typeFolders.contains(name)) {
          list.add(name);
        }
      }
    }
    return list;
  }

  // ────── تنظيف الكاش المؤقت (الدالة المُحسّنة الجديدة) ──────
  Future<void> clearTemporaryCache() async {
    try {
      // 1. Internal temporary directory
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await _deleteAllFilesInDirectory(tempDir);
      }

      // 2. External cache directories (مهم جداً لملفات image_picker و file_picker الكبيرة)
      if (Platform.isAndroid) {
        final externalCaches = await getExternalCacheDirectories();
        if (externalCaches != null) {
          for (final cacheDir in externalCaches) {
            if (await cacheDir.exists()) {
              await _deleteAllFilesInDirectory(cacheDir);
            }
          }
        }
      }

      print('🧹 تم تنظيف الكاش الداخلي والخارجي بنجاح');
    } catch (e) {
      print('خطأ في clearTemporaryCache: $e');
    }
  }

  // Helper لتنظيف أي مجلد
  Future<void> _deleteAllFilesInDirectory(Directory dir) async {
    try {
      final entities = await dir.list(recursive: false).toList();
      for (final entity in entities) {
        if (entity is File) {
          await entity.delete();
        } else if (entity is Directory) {
          await entity.delete(recursive: true);
        }
      }
    } catch (e) {
      print('Error cleaning ${dir.path}: $e');
    }
  }

  // ────── تنظيف الكاش غير المستخدم ──────
  Future<void> cleanUnusedCache() async {
    // تنظيف الصور المصغرة غير المستخدمة
    final vault = await ensureStudyVault();
    final thumbDir = Directory(p.join(vault.path, _thumbDirName));
    if (await thumbDir.exists()) {
      final assetBox = Hive.box<AssetModel>('assets_box');
      final usedThumbs = assetBox.values
          .map((a) => a.resolvedThumbnailPath)
          .where((p) => p != null)
          .cast<String>()
          .toSet();

      await for (final file in thumbDir.list()) {
        if (file is File && !usedThumbs.contains(file.path)) {
          await file.delete();
        }
      }
    }

    // تنظيف الملفات المؤقتة القديمة (أكثر من 7 أيام)
    final tempDir = await getTemporaryDirectory();
    final now = DateTime.now();
    await for (final file in tempDir.list()) {
      if (file is File) {
        final stat = await file.stat();
        if (now.difference(stat.modified).inDays > 7) {
          await file.delete();
        }
      }
    }
  }

  Future<void> clearAllCache() async {
    final vault = await ensureStudyVault();
    final thumbDir = Directory(p.join(vault.path, _thumbDirName));
    if (await thumbDir.exists()) {
      await thumbDir.delete(recursive: true);
      await thumbDir.create();
    }

    final tempDir = await getTemporaryDirectory();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
      await tempDir.create();
    }
  }

  // ────── تنظيف تلقائي حسب الحجم ──────
  Future<void> autoCleanIfNeeded() async {
    try {
      final vault = await ensureStudyVault();
      int totalSize = 0;

      await for (final entity in vault.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      if (totalSize > 700 * 1024 * 1024) {
        await cleanUnusedCache();
        await clearTemporaryCache();
        print('🧹 تم التنظيف التلقائي للكاش (الحجم تجاوز 700 ميجا)');
      }
    } catch (e) {
      print('خطأ في autoCleanIfNeeded: $e');
    }
  }

  // ────── توليد Thumbnail ──────
  Future<String?> generateThumbnailForAsset(AssetModel asset) async {
    try {
      final baseThumbDir = await getThumbnailDirPath();
      final sourcePath = asset.resolvedFilePath;
      final ext = p.extension(sourcePath).toLowerCase();

      if (['.jpg', '.jpeg', '.png', '.gif', '.heic', '.webp'].contains(ext)) {
        final bytes = await File(sourcePath).readAsBytes();
        final image = img.decodeImage(bytes);
        if (image == null) return null;

        final thumb = img.copyResize(image, width: 300);
        final outPath = p.join(baseThumbDir, '${asset.id}_thumb.jpg');
        final outFile = File(outPath);
        await outFile.writeAsBytes(img.encodeJpg(thumb, quality: 80));
        return outPath;
      } else if (['.mp4', '.mov', '.mkv', '.webm'].contains(ext)) {
        return await VideoThumbnail.thumbnailFile(
          video: sourcePath,
          thumbnailPath: baseThumbDir,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 300,
          quality: 75,
        );
      }
      return null;
    } catch (e) {
      print('generateThumbnail error: $e');
      return null;
    }
  }

  Future<String> getThumbnailDirPath() async {
    final vault = await ensureStudyVault();
    final dir = Directory(p.join(vault.path, _thumbDirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  // ────── دوال التقاط والاختيار ──────
  Future<File?> capturePhoto() async =>
      await _pickFromImagePicker(ImageSource.camera, false);

  Future<File?> captureVideo() async =>
      await _pickFromImagePicker(ImageSource.camera, true);

  Future<File?> pickImage() async =>
      await _pickFromImagePicker(ImageSource.gallery, false);

  Future<File?> pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result?.files.isNotEmpty == true) {
        return File(result!.files.first.path!);
      }
    } catch (e) {
      print('pickAudio error: $e');
    }
    return null;
  }

  Future<File?> _pickFromImagePicker(ImageSource source, bool isVideo) async {
    try {
      final picker = ImagePicker();
      final picked = isVideo
          ? await picker.pickVideo(source: source)
          : await picker.pickImage(source: source);
      return picked != null ? File(picked.path) : null;
    } catch (e) {
      print('ImagePicker error: $e');
      return null;
    }
  }

  // ────── حفظ ملاحظة نصية ──────
  Future<File> saveTextNote(
      String text, String fileName, String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File(p.join(dir.path, '$fileName.txt'));
    await file.writeAsString(text);
    return file;
  }

  // ────── إعادة تسمية ──────
  Future<void> renameField(String oldName, String newName) async {
    if (oldName == newName) return;
    final vault = await ensureStudyVault();
    final oldDir = Directory(p.join(vault.path, oldName));
    final newDir = Directory(p.join(vault.path, newName));
    if (await newDir.exists()) throw Exception('الاسم موجود مسبقاً');
    await oldDir.rename(newDir.path);
  }

  Future<void> renameYear(
      String field, String oldYear, String newYear) async {
    if (oldYear == newYear) return;
    final vault = await ensureStudyVault();
    final oldDir = Directory(p.join(vault.path, field, oldYear));
    final newDir = Directory(p.join(vault.path, field, newYear));
    if (await newDir.exists()) throw Exception('الاسم موجود مسبقاً');
    await oldDir.rename(newDir.path);
  }

  Future<void> renameSubject(String field, String year, String oldSubject,
      String newSubject) async {
    if (oldSubject == newSubject) return;
    final vault = await ensureStudyVault();
    final oldDir =
        Directory(p.join(vault.path, field, year, oldSubject));
    final newDir =
        Directory(p.join(vault.path, field, year, newSubject));
    if (await newDir.exists()) throw Exception('الاسم موجود مسبقاً');
    await oldDir.rename(newDir.path);
  }

  Future<void> renameLecture(String field, String year, String subject,
      String oldLecture, String newLecture) async {
    if (oldLecture == newLecture) return;
    final vault = await ensureStudyVault();
    final oldDir = Directory(
        p.join(vault.path, field, year, subject, oldLecture));
    final newDir = Directory(
        p.join(vault.path, field, year, subject, newLecture));
    if (await newDir.exists()) throw Exception('الاسم موجود مسبقاً');
    await oldDir.rename(newDir.path);
  }

  Future<File> renameAssetFile(String oldPath, String newFileName) async {
    final oldFile = File(oldPath);
    if (!await oldFile.exists()) throw Exception('الملف غير موجود');

    final dir = p.dirname(oldPath);
    final ext = p.extension(oldPath);
    final newName =
        newFileName.endsWith(ext) ? newFileName : '$newFileName$ext';
    final newPath = p.join(dir, newName);

    if (await File(newPath).exists()) {
      throw Exception('ملف بنفس الاسم موجود');
    }
    return await oldFile.rename(newPath);
  }

  Future<void> updateNoteContent(String filePath, String newContent) async {
    final file = File(filePath);
    if (!await file.exists()) throw Exception('الملف غير موجود');
    await file.writeAsString(newContent);
  }

  // ────── تنظيف الكاش الخاص بأصل معين ──────
  Future<void> clearCacheForAsset(AssetModel asset) async {
    final resolvedThumb = asset.resolvedThumbnailPath;
    if (resolvedThumb != null) {
      final thumb = File(resolvedThumb);
      if (await thumb.exists()) await thumb.delete();
    }

    final tempDir = await getTemporaryDirectory();
    final baseName = p.basenameWithoutExtension(asset.fileName);
    await for (final file in tempDir.list()) {
      if (file is File && file.path.contains(baseName)) {
        await file.delete();
      }
    }
  }

  /// تنظيف كامل (للإعدادات)
  Future<void> clearAllCacheAndData() async {
    await clearAllCache();
    final assetBox = Hive.box<AssetModel>('assets_box');
    await assetBox.clear();
  }
}