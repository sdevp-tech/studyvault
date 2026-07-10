import 'package:flutter/material.dart';

import '../../services/storage_service.dart';
import '../../models/settings_model.dart';
import '../l10n/app_localizations.dart';

class LecturesQuickAccessModal extends StatefulWidget {
  final StorageService storage;
  final AppSettings? settings;
  final List<String> fields;
  final Function(String, String, String) onSelectLecture;

  const LecturesQuickAccessModal({
    Key? key,
    required this.storage,
    required this.settings,
    required this.fields,
    required this.onSelectLecture,
  }) : super(key: key);

  @override
  _LecturesQuickAccessModalState createState() => _LecturesQuickAccessModalState();
}

class _LecturesQuickAccessModalState extends State<LecturesQuickAccessModal> {
  Map<String, List<String>> _fieldYears = {};
  Map<String, Map<String, List<String>>> _fieldYearSubjects = {};
  String? _selectedField;
  String? _selectedYear;
  String? _selectedSubject;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.fields.isNotEmpty) {
      _selectedField = widget.fields.first;
      _loadFieldYears(_selectedField!);
    }
  }

  Future<void> _loadFieldYears(String field) async {
    setState(() => _isLoading = true);
    try {
      final years = await widget.storage.listYears(field);
      setState(() {
        _fieldYears[field] = years;
        if (years.isNotEmpty) {
          _selectedYear = years.first;
          _loadYearSubjects(field, _selectedYear!);
        }
      });
    } catch (e) {
      print('Error loading years: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadYearSubjects(String field, String year) async {
    setState(() => _isLoading = true);
    try {
      final subjects = await widget.storage.listSubjects(field, year);
      setState(() {
        if (!_fieldYearSubjects.containsKey(field)) {
          _fieldYearSubjects[field] = {};
        }
        _fieldYearSubjects[field]![year] = subjects;
        if (subjects.isNotEmpty) {
          _selectedSubject = subjects.first;
        }
      });
    } catch (e) {
      print('Error loading subjects: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildFieldCard(String field, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedField = field;
          _selectedYear = null;
          _selectedSubject = null;
        });
        _loadFieldYears(field);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withAlpha(25) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder,
              color: isSelected ? Colors.blue : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                field,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.blue : Colors.black,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildYearChip(String year, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedYear = year;
          _selectedSubject = null;
        });
        _loadYearSubjects(_selectedField!, year);
      },
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.orange.withAlpha(25) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 16,
              color: isSelected ? Colors.orange : Colors.grey[600],
            ),
            const SizedBox(width: 6),
            Text(
              year,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.orange : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubjectCard(String subject, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSubject = subject;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.green.withAlpha(25) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.green : Colors.transparent,
            width: isSelected ? 2 : 0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.menu_book,
              color: isSelected ? Colors.green : Colors.grey[600],
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                subject,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? Colors.green : Colors.black,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedPath() {
    final local = AppLocalizations.of(context);
    if (_selectedField == null || _selectedYear == null || _selectedSubject == null) {
      return Container();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withAlpha(13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withAlpha(13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            local.translate('selected_path'),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.purple[700],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.folder, color: Colors.blue, size: 16),
              const SizedBox(width: 4),
              Text(
                _selectedField!,
                style: const TextStyle(color: Colors.blue),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
              const SizedBox(width: 8),
              const Icon(Icons.calendar_today, color: Colors.orange, size: 16),
              const SizedBox(width: 4),
              Text(
                _selectedYear!,
                style: const TextStyle(color: Colors.orange),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey),
              const SizedBox(width: 8),
              const Icon(Icons.menu_book, color: Colors.green, size: 16),
              const SizedBox(width: 4),
              Text(
                _selectedSubject!,
                style: const TextStyle(color: Colors.green),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.menu_book, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.settings?.lecturesTitle ?? local.translate('lectures'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        local.translate('select_field_year_subject'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSelectedPath(),
                        Text(
                          '${widget.settings?.fieldsTitle ?? local.translate('fields')}:',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          flex: 1,
                          child: ListView.builder(
                            itemCount: widget.fields.length,
                            itemBuilder: (context, index) {
                              final field = widget.fields[index];
                              return _buildFieldCard(
                                field,
                                field == _selectedField,
                              );
                            },
                          ),
                        ),
                        if (_selectedField != null &&
                            _fieldYears[_selectedField] != null &&
                            _fieldYears[_selectedField]!.isNotEmpty)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Text(
                                '${widget.settings?.yearsTitle ?? local.translate('years')}:',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 60,
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: _fieldYears[_selectedField]!
                                      .map((year) => _buildYearChip(
                                            year,
                                            year == _selectedYear,
                                          ))
                                      .toList(),
                                ),
                              ),
                            ],
                          ),
                        if (_selectedYear != null &&
                            _fieldYearSubjects[_selectedField] != null &&
                            _fieldYearSubjects[_selectedField]![_selectedYear] != null)
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 16),
                                Text(
                                  '${widget.settings?.subjectsTitle ?? local.translate('subjects')}:',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: _fieldYearSubjects[_selectedField]![_selectedYear]!.length,
                                    itemBuilder: (context, index) {
                                      final subject = _fieldYearSubjects[_selectedField]![_selectedYear]![index];
                                      return _buildSubjectCard(
                                        subject,
                                        subject == _selectedSubject,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_selectedField != null &&
                            _selectedYear != null &&
                            _selectedSubject != null)
                        ? () {
                            widget.onSelectLecture(
                              _selectedField!,
                              _selectedYear!,
                              _selectedSubject!,
                            );
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.menu_book, color: Colors.white),
                    label: Text(
                      local.translate('open_lectures_of').replaceFirst(
                          '{subject}',
                          _selectedSubject ?? widget.settings?.subjectsTitle ?? local.translate('subject')),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}