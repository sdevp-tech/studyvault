import 'package:hive/hive.dart';

part 'asset_model.g.dart';

@HiveType(typeId: 0)
class AssetModel extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String field;

  @HiveField(2)
  String year;

  @HiveField(3)
  String subject;

  @HiveField(4)
  String? lecture;

  @HiveField(5)
  String fileName;

  @HiveField(6)
  String filePath;

  @HiveField(7)
  String type;

  @HiveField(8)
  List<String> tags;

  @HiveField(9)
  DateTime createdAt;

  @HiveField(10)
  String? notes;

  @HiveField(11)
  String? extractedText;

  @HiveField(12)
  String? thumbnailPath;

  AssetModel({
    required this.id,
    required this.field,
    required this.year,
    required this.subject,
    this.lecture,
    required this.fileName,
    required this.filePath,
    required this.type,
    required this.tags,
    required this.createdAt,
    this.notes,
    this.extractedText,
    this.thumbnailPath,
  });

  // ==================== JSON Methods ====================
  factory AssetModel.fromJson(Map<String, dynamic> json) {
    return AssetModel(
      id: json['id'],
      field: json['field'],
      year: json['year'],
      subject: json['subject'],
      lecture: json['lecture'],
      fileName: json['fileName'],
      filePath: json['filePath'],
      type: json['type'],
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: DateTime.parse(json['createdAt']),
      notes: json['notes'],
      extractedText: json['extractedText'],
      thumbnailPath: json['thumbnailPath'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'field': field,
      'year': year,
      'subject': subject,
      'lecture': lecture,
      'fileName': fileName,
      'filePath': filePath,
      'type': type,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'notes': notes,
      'extractedText': extractedText,
      'thumbnailPath': thumbnailPath,
    };
  }
}