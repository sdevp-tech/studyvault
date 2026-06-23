import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/llm_settings.dart';
import '../l10n/app_localizations.dart';

class LlmSettingsScreen extends StatefulWidget {
  const LlmSettingsScreen({super.key});

  @override
  State<LlmSettingsScreen> createState() => _LlmSettingsScreenState();
}

class _LlmSettingsScreenState extends State<LlmSettingsScreen> {
  late final Box<LlmSettings> _box;
  late LlmSettings _settings;

  @override
  void initState() {
    super.initState();
    _box = Hive.box<LlmSettings>('llm_settings_box');
    _settings = _box.get(0) ?? LlmSettings();
  }

  void _save() {
    _box.put(0, _settings);
    final local = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(local.translate('saved_successfully'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(local.translate('ai_settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- اختيار المسرّع ---
          ListTile(
            title: Text(local.translate('backend_label')),
            subtitle: DropdownButton<String>(
              value: _settings.backend,
              items: [
                DropdownMenuItem(value: 'cpu', child: Text(local.translate('cpu_option'))),
                DropdownMenuItem(value: 'gpu', child: Text(local.translate('gpu_option'))),
                DropdownMenuItem(value: 'npu', child: Text(local.translate('npu_option'))),
              ],
              onChanged: (val) {
                setState(() {
                  _settings.backend = val!;
                  _save();
                });
              },
            ),
          ),
          const Divider(height: 32),
          // --- توجيه النظام ---
          SwitchListTile(
            title: Text(local.translate('use_system_prompt')),
            value: _settings.useSystemPrompt,
            onChanged: (val) {
              setState(() {
                _settings.useSystemPrompt = val;
                _save();
              });
            },
          ),
          if (_settings.useSystemPrompt)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextFormField(
                initialValue: _settings.systemPrompt,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: local.translate('system_prompt_label'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (val) {
                  _settings.systemPrompt = val;
                  _save();
                },
              ),
            ),
          const Divider(height: 32),
          // --- درجة الحرارة ---
          ListTile(
            title: Text(local.translate('temperature_label')),
            subtitle: Slider(
              value: _settings.temperature,
              min: 0.1,
              max: 1.5,
              divisions: 20,
              onChanged: (val) {
                setState(() {
                  _settings.temperature = val;
                  _save();
                });
              },
            ),
            trailing: Text(_settings.temperature.toStringAsFixed(2)),
          ),
          // --- Top-K ---
          ListTile(
            title: Text(local.translate('top_k_label')),
            subtitle: Slider(
              value: _settings.topK.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              onChanged: (val) {
                setState(() {
                  _settings.topK = val.toInt();
                  _save();
                });
              },
            ),
            trailing: Text(_settings.topK.toString()),
          ),
          // --- Max Tokens ---
          ListTile(
            title: Text(local.translate('max_tokens_label')),
            subtitle: Slider(
              value: _settings.maxTokens.toDouble(),
              min: 64,
              max: 2048,
              divisions: 100,
              onChanged: (val) {
                setState(() {
                  _settings.maxTokens = val.toInt();
                  _save();
                });
              },
            ),
            trailing: Text(_settings.maxTokens.toString()),
          ),
          const SizedBox(height: 20),
          // --- زر إعادة الضبط ---
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _settings = LlmSettings();
                _save();
              });
            },
            icon: const Icon(Icons.refresh),
            label: Text(local.translate('reset_defaults')),
          ),
        ],
      ),
    );
  }
}