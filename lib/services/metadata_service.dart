import 'dart:io';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';
import '../models/asset_model.dart';
import 'annotation_service.dart';
import 'path_resolver.dart';
import 'spaced_repetition_service.dart';
import 'storage_service.dart';

class MetadataService {
  final Box<AssetModel> box;
  final StorageService storage;

  MetadataService(this.box, this.storage);

  Future<AssetModel> addAsset({
    required String field,
    required String year,
    required String subject,
    String? lecture,
    required String fileName,
    required String filePath,
    required String type,
    List<String>? tags,
    String? notes,
    String? extractedText,
    String? thumbnailPath,
  }) async {
    final id = Uuid().v4();
    final asset = AssetModel(
      id: id,
      field: field,
      year: year,
      subject: subject,
      lecture: lecture,
      fileName: fileName,
      // Persist storage-stable (relative) paths, not absolute ones.
      filePath: PathResolver.toStorable(filePath),
      type: type,
      tags: tags ?? [],
      createdAt: DateTime.now(),
      notes: notes,
      extractedText: extractedText,
      thumbnailPath:
          thumbnailPath == null ? null : PathResolver.toStorable(thumbnailPath),
    );
    await box.put(id, asset);
    return asset;
  }

  List<AssetModel> getAssetsForSubject(String field, String year, String subject) {
    return box.values
        .where((a) => a.field == field && a.year == year && a.subject == subject && (a.lecture == null || a.lecture!.isEmpty))
        .cast<AssetModel>()
        .toList();
  }

  List<AssetModel> getAssetsForLecture(String field, String year, String subject, String lecture) {
    return box.values
        .where((a) => a.field == field && a.year == year && a.subject == subject && (a.lecture ?? '') == lecture)
        .cast<AssetModel>()
        .toList();
  }

  List<AssetModel> searchAssets({
    required String field,
    required String year,
    required String subject,
    String? lecture,
    String? query,
    List<String>? tags,
    String? type,
  }) {
    final q = query?.trim().toLowerCase() ?? '';
    return box.values.where((a) {
      if (a.field != field || a.year != year || a.subject != subject) return false;
      if (lecture != null && (a.lecture ?? '') != lecture) return false;
      final matchesQuery = q.isEmpty
          ? true
          : (a.fileName.toLowerCase().contains(q) ||
          (a.notes ?? '').toLowerCase().contains(q) ||
          (a.extractedText ?? '').toLowerCase().contains(q));
      final matchesType = type == null ? true : a.type == type;
      final matchesTags = (tags == null || tags.isEmpty)
          ? true
          : tags.every((t) => a.tags.map((e) => e.toLowerCase()).contains(t.toLowerCase()));
      return matchesQuery && matchesType && matchesTags;
    }).cast<AssetModel>().toList();
  }

  Future<void> updateTags(String assetId, List<String> newTags) async {
    final asset = box.get(assetId);
    if (asset == null) return;
    asset.tags = newTags;
    await asset.save();
  }

  Future<void> updateNotes(String assetId, String? notes) async {
    final asset = box.get(assetId);
    if (asset == null) return;
    asset.notes = notes;
    await asset.save();
  }

  Future<void> updateThumbnail(String assetId, String? thumbnailPath) async {
    final asset = box.get(assetId);
    if (asset == null) return;
    asset.thumbnailPath =
        thumbnailPath == null ? null : PathResolver.toStorable(thumbnailPath);
    await asset.save();
  }

  Future<void> updateExtractedText(String assetId, String? text) async {
    final asset = box.get(assetId);
    if (asset == null) return;
    asset.extractedText = text;
    await asset.save();
  }

  Future<void> deleteAsset(AssetModel asset) async {
    try {
      final f = File(asset.resolvedFilePath);
      if (await f.exists()) await f.delete();
      await storage.clearCacheForAsset(asset);

      final annotationBox = Hive.box<Annotation>('annotations_box');
      final annotationService = AnnotationService(annotationBox);
      await annotationService.deleteAnnotationsForAsset(asset.id);

      final cardsBox = Hive.box<CardModel>('cards_box');
      final cardService = SpacedRepetitionService(cardsBox);
      await cardService.deleteCardsForAsset(asset.id);

      await box.delete(asset.id);
      print("✅ تم حذف الملف ومتعلقاته بنجاح");
    } catch (e) {
      print("❌ خطأ أثناء حذف الملف: $e");
    }
  }

  /// تحديث جميع الأصول (AssetModel) بعد إعادة تسمية مجال/سنة/مادة/محاضرة
  Future<void> updateAssetsAfterRename({
    required String oldField,
    required String oldYear,
    String? oldSubject,
    String? oldLecture,
    required String newField,
    required String newYear,
    String? newSubject,
    String? newLecture,
  }) async {
    final assetBox = Hive.box<AssetModel>('assets_box');
    final assetsToUpdate = assetBox.values.where((a) {
      if (a.field != oldField || a.year != oldYear) return false;
      if (oldSubject != null && a.subject != oldSubject) return false;
      if (oldLecture != null && (a.lecture ?? '') != oldLecture) return false;
      return true;
    }).toList();

    for (final asset in assetsToUpdate) {
      asset.field = newField;
      asset.year = newYear;
      if (newSubject != null) asset.subject = newSubject;
      if (newLecture != null) asset.lecture = newLecture;

      // تحديث المسار
      final oldDirSegments = <String>[oldField, oldYear];
      if (oldSubject != null) oldDirSegments.add(oldSubject);
      if (oldLecture != null) oldDirSegments.add(oldLecture);
      final oldDir = oldDirSegments.join('/');

      final newDirSegments = <String>[newField, newYear];
      if (newSubject != null) newDirSegments.add(newSubject);
      if (newLecture != null) newDirSegments.add(newLecture);
      final newDir = newDirSegments.join('/');

      if (asset.filePath.contains(oldDir)) {
        asset.filePath = asset.filePath.replaceFirst(oldDir, newDir);
      }

      await asset.save();
    }
  }
}