import 'package:hive/hive.dart';

part 'llm_settings.g.dart';

@HiveType(typeId: 20)
class LlmSettings {
  @HiveField(0) String systemPrompt;
  @HiveField(1) double temperature;
  @HiveField(2) int topK;
  @HiveField(3) int maxTokens;
  @HiveField(4) bool useSystemPrompt;
  @HiveField(5) String backend;
  @HiveField(6) String modelPath;

  LlmSettings({
    this.systemPrompt = "أنت مساعد ذكي تجيب باللغة العربية فقط وبشكل مختصر ومفيد.",
    this.temperature = 0.6,
    this.topK = 30,
    this.maxTokens = 256,
    this.useSystemPrompt = true,
    this.backend = "gpu",
    this.modelPath = "",
  });
}