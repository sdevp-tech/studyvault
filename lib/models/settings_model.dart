import 'package:hive/hive.dart';

part 'settings_model.g.dart';

@HiveType(typeId: 6)
class AppSettings extends HiveObject {
  @HiveField(0)
  String fieldsTitle;

  @HiveField(1)
  String yearsTitle;

  @HiveField(2)
  String subjectsTitle;

  @HiveField(3)
  String lecturesTitle;

  @HiveField(4)
  String assignmentsTitle;

  @HiveField(5)
  String examsTitle;

  @HiveField(6)
  String todoTitle;

  @HiveField(7)
  bool isDarkMode;

  @HiveField(8)
  String language;

  // أضفنا هذا المتغير الذي كان مفقوداً
  @HiveField(9)
  bool isFirstTime;

  AppSettings({
    this.fieldsTitle = 'التخصصات',
    this.yearsTitle = 'السنوات',
    this.subjectsTitle = 'المواد',
    this.lecturesTitle = 'المحاضرات',
    this.assignmentsTitle = 'التكاليف',
    this.examsTitle = 'الاختبارات',
    this.todoTitle = 'قائمة المهام',
    this.isDarkMode = false,
    this.language = 'العربية',
    this.isFirstTime = true, // افتراضياً يكون true حتى ينهي المستخدم شاشة الترحيب
  });
}
