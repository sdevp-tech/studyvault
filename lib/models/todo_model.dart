import 'package:hive/hive.dart';

part 'todo_model.g.dart';

@HiveType(typeId: 14)
enum Priority {
  @HiveField(0)
  low,
  @HiveField(1)
  medium,
  @HiveField(2)
  high,
  @HiveField(3)
  urgent
}

@HiveType(typeId: 15)
class TodoItem extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String? description;

  @HiveField(3)
  bool isCompleted;

  @HiveField(4)
  Priority priority;

  @HiveField(5)
  DateTime? dueDate;

  @HiveField(6)
  DateTime createdAt;

  @HiveField(7)
  DateTime? completedAt;

  @HiveField(8)
  bool hasReminder;

  TodoItem({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    this.priority = Priority.medium,
    this.dueDate,
    required this.createdAt,
    this.completedAt,
    this.hasReminder = false,
  });

  // ==================== JSON Methods ====================
  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      isCompleted: json['isCompleted'] ?? false,
      priority: Priority.values[json['priority']],
      dueDate: json['dueDate'] != null ? DateTime.parse(json['dueDate']) : null,
      createdAt: DateTime.parse(json['createdAt']),
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt']) : null,
      hasReminder: json['hasReminder'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'isCompleted': isCompleted,
      'priority': priority.index,
      'dueDate': dueDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'hasReminder': hasReminder,
    };
  }
}