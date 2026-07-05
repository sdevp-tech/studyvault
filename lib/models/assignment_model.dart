import 'package:hive/hive.dart';

part 'assignment_model.g.dart';

@HiveType(typeId: 11)
enum AssignmentType {
  @HiveField(0)
  assignment,
  @HiveField(1)
  exam,
  @HiveField(2)
  reminder
}

@HiveType(typeId: 12)
enum AssignmentStatus {
  @HiveField(0)
  pending,
  @HiveField(1)
  inProgress,
  @HiveField(2)
  completed,
  @HiveField(3)
  overdue
}

@HiveType(typeId: 13)
class Assignment extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String? description;

  @HiveField(3)
  AssignmentType type;

  @HiveField(4)
  AssignmentStatus status;

  @HiveField(5)
  DateTime dueDate;

  @HiveField(6)
  DateTime? completedDate;

  @HiveField(7)
  String? field;

  @HiveField(8)
  String? year;

  @HiveField(9)
  String? subject;

  @HiveField(10)
  String? lecture;

  @HiveField(11)
  String? assetId;

  @HiveField(12)
  bool hasReminder;

  @HiveField(13)
  DateTime createdAt;

  Assignment({
    required this.id,
    required this.title,
    this.description,
    required this.type,
    this.status = AssignmentStatus.pending,
    required this.dueDate,
    this.completedDate,
    this.field,
    this.year,
    this.subject,
    this.lecture,
    this.assetId,
    this.hasReminder = false,
    required this.createdAt,
  });

  // ==================== JSON Methods ====================
  factory Assignment.fromJson(Map<String, dynamic> json) {
    return Assignment(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      type: AssignmentType.values[json['type']],
      status: AssignmentStatus.values[json['status']],
      dueDate: DateTime.parse(json['dueDate']),
      completedDate: json['completedDate'] != null ? DateTime.parse(json['completedDate']) : null,
      field: json['field'],
      year: json['year'],
      subject: json['subject'],
      lecture: json['lecture'],
      assetId: json['assetId'],
      hasReminder: json['hasReminder'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'type': type.index,
      'status': status.index,
      'dueDate': dueDate.toIso8601String(),
      'completedDate': completedDate?.toIso8601String(),
      'field': field,
      'year': year,
      'subject': subject,
      'lecture': lecture,
      'assetId': assetId,
      'hasReminder': hasReminder,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}