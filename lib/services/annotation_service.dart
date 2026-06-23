import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

part 'annotation_service.g.dart';

@HiveType(typeId: 17)
class Annotation extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String assetId;

  @HiveField(2)
  String page;

  @HiveField(3)
  String text;

  @HiveField(4)
  double x;

  @HiveField(5)
  double y;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  String? color;

  @HiveField(8)
  String? type;

  Annotation({
    required this.id,
    required this.assetId,
    this.page = '',
    required this.text,
    this.x = 0,
    this.y = 0,
    DateTime? createdAt,
    this.color = '#FFEB3B',
    this.type = 'text',
  }) : createdAt = createdAt ?? DateTime.now();

  // ==================== Getter المطلوب ====================
  String get shortText => text.length <= 30 
      ? text 
      : '${text.substring(0, 30)}...';

  // ==================== JSON Methods ====================
  factory Annotation.fromJson(Map<String, dynamic> json) {
    return Annotation(
      id: json['id'],
      assetId: json['assetId'],
      page: json['page'] ?? '',
      text: json['text'],
      x: (json['x'] ?? 0).toDouble(),
      y: (json['y'] ?? 0).toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
      color: json['color'],
      type: json['type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'assetId': assetId,
      'page': page,
      'text': text,
      'x': x,
      'y': y,
      'createdAt': createdAt.toIso8601String(),
      'color': color,
      'type': type,
    };
  }
}

class AnnotationService {
  final Box<Annotation> box;
  AnnotationService(this.box);

  Future<Annotation> addAnnotation({
    required String assetId,
    String page = '',
    required String text,
    double x = 0,
    double y = 0,
    String? color,
    String? type,
  }) async {
    final id = const Uuid().v4();
    final annotation = Annotation(
      id: id,
      assetId: assetId,
      page: page,
      text: text,
      x: x,
      y: y,
      color: color,
      type: type,
    );
    
    await box.put(id, annotation);
    return annotation;
  }

  Future<void> updateAnnotation(Annotation annotation) async {
    await annotation.save();
  }

  Future<void> deleteAnnotation(String id) async {
    await box.delete(id);
  }

  Future<void> deleteAnnotationsForAsset(String assetId) async {
    final annotations = box.values.where((a) => a.assetId == assetId).toList();
    for (final annotation in annotations) {
      await box.delete(annotation.id);
    }
  }

  List<Annotation> getForAsset(String assetId) {
    return box.values
        .where((a) => a.assetId == assetId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<Annotation> searchInAnnotations(String query) {
    final lowerQuery = query.toLowerCase();
    return box.values
        .where((a) => a.text.toLowerCase().contains(lowerQuery))
        .toList();
  }

  Map<String, int> getStatistics() {
    final all = box.values.toList();
    return {
      'total': all.length,
      'text': all.where((a) => a.type == 'text').length,
      'highlight': all.where((a) => a.type == 'highlight').length,
      'question': all.where((a) => a.type == 'question').length,
    };
  }
}