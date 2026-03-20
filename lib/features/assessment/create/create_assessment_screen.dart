import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../teacher_essentials/data/teacher_essentials_service.dart';
import '../../teacher_essentials/models/assessment_template.dart';
import '../../../core/api/api_client.dart';
import '../../classroom/providers/course_outcomes_provider.dart';

class CreateAssessmentScreen extends ConsumerStatefulWidget {
  final String classroomId;
  const CreateAssessmentScreen({super.key, required this.classroomId});

  @override
  ConsumerState<CreateAssessmentScreen> createState() =>
      _CreateAssessmentScreenState();
}

class _CreateAssessmentScreenState
    extends ConsumerState<CreateAssessmentScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _timeLimitController = TextEditingController(text: '60');
  String _type = 'exam';
  AssessmentTemplate? _selectedTemplate;
  bool _isSaving = false;
  List<TemplateQuestion> _editableQuestions = [];
  final Map<int, int?> _selectedCourseOutcomes = {};
  int? _selectedOverallCourseOutcome;

  void _applyTemplate(
    AssessmentTemplate template, {
    bool isFromDropdown = false,
  }) {
    setState(() {
      if (isFromDropdown) {
        _selectedTemplate = template;
      } else {
        _selectedTemplate = null;
      }
      _titleController.text = template.title;
      _descriptionController.text = template.description;
      _type = template.type;
      _timeLimitController.text = template.timeLimitMinutes.toString();
      _editableQuestions = List<TemplateQuestion>.from(template.questions);
      _selectedCourseOutcomes.clear();

      // Auto-assign course outcome per question based on AI suggestion
      final currentOutcomes = ref.read(courseOutcomesProvider(int.parse(widget.classroomId))).value;
      if (currentOutcomes != null && currentOutcomes.isNotEmpty) {
        for (int i = 0; i < template.questions.length; i++) {
          final suggestion = template.questions[i].suggestedCourseOutcome;
          if (suggestion != null && suggestion.isNotEmpty) {
            try {
              final matched = currentOutcomes.firstWhere(
                (o) =>
                    o.code.toLowerCase().contains(suggestion.toLowerCase()) ||
                    o.description.toLowerCase().contains(suggestion.toLowerCase()),
              );
              _selectedCourseOutcomes[i] = matched.id;
            } catch (_) {
              // No match found for this question, leave blank
            }
          }
        }
      }
    });
  }

  bool _isUploading = false;

  Future<void> _uploadMcqFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'pdf', 'doc', 'docx'],
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    setState(() => _isUploading = true);

    try {
      final dio = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'type': _type,
        'time_limit_minutes': int.tryParse(_timeLimitController.text) ?? 60,
      });

      final response = await dio.post(
        '/assessment-templates/upload-mcq',
        data: formData,
      );

      final template = AssessmentTemplate.fromJson(
        response.data as Map<String, dynamic>,
      );
      _applyTemplate(template);
    } on DioException catch (e) {
      if (!mounted) return;
      String msg = 'Failed to parse MCQ file';
      if (e.response != null && e.response?.data is Map) {
        final data = e.response?.data as Map;
        if (data.containsKey('message')) {
          msg = data['message'].toString();
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to parse MCQ file: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a title'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_editableQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add at least one question (or upload a valid MCQ file)',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final dio = ref.read(apiClientProvider);
      final questions = _editableQuestions.asMap().entries.map(
        (entry) {
          final qIndex = entry.key;
          final q = entry.value;
          return {
            'body': q.body,
            'type': q.type,
            'points': q.points,
            'course_outcome_id': _selectedCourseOutcomes[qIndex],
            'options': q.options
                .map((o) => {'body': o.body, 'is_correct': o.isCorrect})
                .toList(),
          };
        },
      ).toList();

      await dio.post(
        '/classrooms/${widget.classroomId}/assessments',
        data: {
          'title': _titleController.text,
          'description': _descriptionController.text,
          'type': _type,
          'time_limit_minutes': int.tryParse(_timeLimitController.text) ?? 60,
          'is_published': true,
          'course_outcome_id': _selectedOverallCourseOutcome,
          'questions': questions,
        },
      );

      if (mounted) {
        ref.invalidate(assessmentsProvider(int.parse(widget.classroomId)));
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assessment created successfully')),
        );
      }
    } on DioException catch (e) {
      if (mounted) {
        String msg = 'Failed to create assessment';
        if (e.response != null && e.response?.data is Map) {
          final data = e.response?.data as Map;
          if (data.containsKey('errors')) {
            final errors = data['errors'] as Map;
            msg = errors.values.first.first.toString();
          } else if (data.containsKey('message')) {
            msg = data['message'].toString();
          }
        }
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create assessment: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(assessmentTemplatesProvider);
    final outcomesAsync = ref.watch(courseOutcomesProvider(int.parse(widget.classroomId)));

    final theme = ThemeData.light().copyWith(
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1967D2),
        surface: Colors.white,
        onSurface: Color(0xFF3C4043),
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF3C4043),
        elevation: 1,
        shadowColor: Colors.black12,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF1F3F4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1967D2), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: Color(0xFF5F6368)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF1967D2)),
      ),
      dividerColor: const Color(0xFFE8EAED),
    );

    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Create Assessment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.pop(),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _save(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2), // Google Blue
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                child: _isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Assign', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              templatesAsync.when(
                data: (templates) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Start from',
                      style: TextStyle(
                        color: Color(0xFF1967D2),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<AssessmentTemplate>(
                            value: _selectedTemplate,
                            hint: const Text('Built-in template'),
                            isExpanded: true,
                            items: templates
                                .map(
                                  (t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t.title),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) _applyTemplate(val, isFromDropdown: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _isUploading ? null : _uploadMcqFile,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1967D2),
                            side: const BorderSide(color: Color(0xFFD2E3FC)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          ),
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.upload_file),
                          label: Text(_isUploading ? 'Analyzing...' : 'Upload MCQ file'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                  ],
                ),
                loading: () => const LinearProgressIndicator(),
                error: (e, s) => Text('Error loading templates: $e'),
              ),
              AppTextField(
                controller: _titleController,
                label: 'Assessment Title',
                hint: 'e.g. Midterm Physics',
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _descriptionController,
                label: 'Description (Optional)',
                hint: 'Enter instructions or details',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'exam', child: Text('Exam')),
                  DropdownMenuItem(value: 'quiz', child: Text('Quiz')),
                  DropdownMenuItem(value: 'activity', child: Text('Activity')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _type = val);
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _timeLimitController,
                label: 'Time Limit (Minutes)',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              outcomesAsync.when(
                data: (outcomes) {
                  if (outcomes.isEmpty) return const SizedBox.shrink();
                  return DropdownButtonFormField<int>(
                    value: _selectedOverallCourseOutcome,
                    decoration: const InputDecoration(labelText: 'Overall Course Outcome (Optional)'),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text('None')),
                      ...outcomes.map((co) => DropdownMenuItem(
                        value: co.id,
                        child: Text(co.code),
                      )),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedOverallCourseOutcome = val);
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const Text('Failed to load outcomes'),
              ),
              if (_editableQuestions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Questions (${_editableQuestions.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF3C4043),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.shade300,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: List.generate(_editableQuestions.length, (index) {
                      final q = _editableQuestions[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              initialValue: q.body,
                              decoration: InputDecoration(
                                labelText: 'Question ${index + 1}',
                              ),
                              onChanged: (val) {
                                setState(() {
                                  _editableQuestions[index] = q.copyWith(
                                    body: val,
                                  );
                                });
                              },
                            ),
                            const SizedBox(height: 16),
                            outcomesAsync.when(
                              data: (outcomes) {
                                if (outcomes.isEmpty) return const SizedBox.shrink();
                                return DropdownButtonFormField<int>(
                                  value: _selectedCourseOutcomes[index],
                                  decoration: InputDecoration(
                                    labelText: 'Course Outcome',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                  ),
                                  items: [
                                    const DropdownMenuItem<int>(value: null, child: Text('None')),
                                    ...outcomes.map((co) => DropdownMenuItem(
                                      value: co.id,
                                      child: Text(co.code),
                                    )),
                                  ],
                                  onChanged: (val) {
                                    setState(() => _selectedCourseOutcomes[index] = val);
                                  },
                                );
                              },
                              loading: () => const LinearProgressIndicator(),
                              error: (_, __) => const Text('Failed to load outcomes'),
                            ),
                            const SizedBox(height: 16),
                            Column(
                              children: List.generate(q.options.length, (i) {
                                final opt = q.options[i];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Row(
                                    children: [
                                      Radio<int>(
                                        value: i,
                                        groupValue: q.options.indexWhere(
                                          (o) => o.isCorrect,
                                        ),
                                        onChanged: (val) {
                                          if (val == null) return;
                                          setState(() {
                                            final updatedOptions = q.options
                                                .asMap()
                                                .entries
                                                .map((e) {
                                                  return e.key == val
                                                      ? e.value.copyWith(
                                                          isCorrect: true,
                                                        )
                                                      : e.value.copyWith(
                                                          isCorrect: false,
                                                        );
                                                })
                                                .toList();
                                            _editableQuestions[index] = q.copyWith(
                                              options: updatedOptions,
                                            );
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: opt.body,
                                          decoration: const InputDecoration(
                                            labelText: 'Option',
                                          ),
                                          onChanged: (val) {
                                            setState(() {
                                              final updated = q.options.toList(
                                                growable: true,
                                              );
                                              updated[i] = opt.copyWith(body: val);
                                              _editableQuestions[index] = q
                                                  .copyWith(options: updated);
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                            if (index < _editableQuestions.length - 1)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Divider(),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}
