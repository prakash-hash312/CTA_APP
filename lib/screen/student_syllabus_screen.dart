import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_services.dart';

class _Topic {
  final int id;
  final String title;
  final List<_Lesson> lessons;

  const _Topic({required this.id, required this.title, this.lessons = const []});

  _Topic copyWith({List<_Lesson>? lessons}) {
    return _Topic(id: id, title: title, lessons: lessons ?? this.lessons);
  }
}

class _Lesson {
  final int id;
  final String title;
  final String contentType;
  final String html;
  final String rendered;
  final String? primaryUrl;
  final String? altUrl;
  final bool needsFetch;

  const _Lesson({
    required this.id,
    required this.title,
    this.contentType = 'content',
    this.html = '',
    this.rendered = '',
    this.primaryUrl,
    this.altUrl,
    this.needsFetch = false,
  });

  _Lesson copyWith({
    String? contentType,
    String? html,
    String? rendered,
    String? primaryUrl,
    String? altUrl,
    bool? needsFetch,
  }) {
    return _Lesson(
      id: id,
      title: title,
      contentType: contentType ?? this.contentType,
      html: html ?? this.html,
      rendered: rendered ?? this.rendered,
      primaryUrl: primaryUrl ?? this.primaryUrl,
      altUrl: altUrl ?? this.altUrl,
      needsFetch: needsFetch ?? this.needsFetch,
    );
  }
}

class StudentSyllabusScreen extends StatefulWidget {
  const StudentSyllabusScreen({super.key});

  @override
  State<StudentSyllabusScreen> createState() => _StudentSyllabusScreenState();
}

class _StudentSyllabusScreenState extends State<StudentSyllabusScreen> {
  bool _loading = true;
  String? _error;

  String _gradeTitle = 'Grade 5 - Student';
  int _mainId = 1013;
  List<_Topic> _topics = [];
  int? _selectedTopicId;
  int? _selectedLessonId;
  final Set<int> _expandedTopics = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Resolve the actual student ID from user session instead of using hardcoded value
      final resolvedStudId = await apiService.ensureCurrentStudentId();
      final gradeRows = await apiService.fetchSyllabusGradeInfo(studId: resolvedStudId ?? apiService.currentStudentId ?? 28410);
      debugPrint('📚 GradeInfo Response: $gradeRows');
      if (gradeRows.isNotEmpty) {
        final g = _pickGrade5(gradeRows) ?? gradeRows.first;
        debugPrint('📚 Selected Grade Row: $g');
        _mainId = int.tryParse('${g['MainTopicID'] ?? g['main_topic_id'] ?? 1013}') ?? 1013;
        _gradeTitle = (g['Title'] ?? g['title'] ?? 'Grade 5 - Student').toString();
        debugPrint('📚 MainId: $_mainId, GradeTitle: $_gradeTitle');
      }

      final topicRows = await apiService.fetchSyllabusTopicInfo(mainId: _mainId);
      debugPrint('📚 TopicInfo Response: $topicRows');
      final topics = <_Topic>[];

      for (final t in topicRows) {
        final topicId = int.tryParse('${t['SubTopicID'] ?? t['sub_topic_id'] ?? t['ID'] ?? t['id'] ?? 0}') ?? 0;
        final topicTitle = (t['Title'] ?? t['title'] ?? 'Untitled').toString();
        debugPrint('📚 Processing Topic: ID=$topicId, Title=$topicTitle');

        // 1) Try direct content list under this topic_id
        final directContent = await apiService.fetchSyllabusContent(subtopicId: topicId);
        debugPrint('📚 Direct Content for topic $topicId: ${directContent.length} items');
        final mappedDirect = directContent.map((e) => _mapContentRow(e)).toList();

        List<_Lesson> lessons;

        if (mappedDirect.isNotEmpty) {
          lessons = mappedDirect;
        } else {
          // 2) Fallback to SubTopicInfo list; each subtopic can be fetched on select.
          final subRows = await apiService.fetchSyllabusSubTopicInfo(topicId: topicId);
          debugPrint('📚 SubTopicInfo for topic $topicId: ${subRows.length} items');
          lessons = subRows.map((s) {
            final sid = int.tryParse('${s['SubSubTopicID'] ?? s['sub_sub_topic_id'] ?? s['ID'] ?? s['id'] ?? 0}') ?? 0;
            final stitle = (s['Title'] ?? s['title'] ?? 'Untitled').toString();
            return _Lesson(
              id: sid,
              title: stitle,
              needsFetch: true,
            );
          }).toList();
        }

        topics.add(_Topic(id: topicId, title: topicTitle, lessons: lessons));
      }

      if (!mounted) return;

      int? selTopic;
      int? selLesson;
      if (topics.isNotEmpty && topics.first.lessons.isNotEmpty) {
        selTopic = topics.first.id;
        selLesson = topics.first.lessons.first.id;
      }

      setState(() {
        _topics = topics;
        _selectedTopicId = selTopic;
        _selectedLessonId = selLesson;
        if (selTopic != null) _expandedTopics.add(selTopic);
        _loading = false;
      });

      if (selTopic != null && selLesson != null) {
        await _ensureLessonLoaded(selTopic, selLesson);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? _pickGrade5(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      final g = (row['grade_name'] ?? '').toString().toLowerCase();
      final t = (row['Title'] ?? '').toString().toLowerCase();
      final d = (row['Description'] ?? '').toString().toLowerCase();
      if (g.contains('grade 5') || t.contains('grade 5') || d.contains('grade 5')) {
        return row;
      }
    }
    return null;
  }

  _Lesson _mapContentRow(Map<String, dynamic> row) {
    final id = int.tryParse('${row['SubSubTopicID'] ?? row['sub_sub_topic_id'] ?? row['ID'] ?? row['id'] ?? 0}') ?? 0;
    final title = (row['Title'] ?? row['title'] ?? 'Untitled').toString();
    final type = (row['ContentType'] ?? row['content_type'] ?? 'content').toString().toLowerCase();
    final html = (row['ContentHtml'] ?? row['content_html'] ?? '').toString();
    final rendered = (row['RenderedContent'] ?? row['rendered_content'] ?? '').toString();
    final iframe = (row['IframeUrl'] ?? row['iframe_url'] ?? '').toString();
    final fileName = (row['FileName'] ?? row['file_name'] ?? '').toString();

    debugPrint('📄 Mapping Content: ID=$id, Title=$title, Type=$type');

    String? primary;
    String? alt;

    if (_isHttp(iframe)) primary = iframe;
    if (primary == null && _isHttp(rendered)) primary = rendered;

    var effectiveFile = fileName.trim();
    if (effectiveFile.isEmpty && rendered.contains('/')) {
      effectiveFile = rendered.split('/').last.trim();
    }

    if (primary == null && effectiveFile.isNotEmpty && !effectiveFile.toLowerCase().startsWith('d:')) {
      primary = 'https://www.ivpsemi.in/CTA_Mob/HomeworkFiles/$effectiveFile';
      alt = 'https://www.ivpsemi.in/HomeworkFiles/$effectiveFile';
    }

    return _Lesson(
      id: id,
      title: title,
      contentType: type,
      html: html,
      rendered: rendered,
      primaryUrl: primary,
      altUrl: alt,
      needsFetch: false,
    );
  }

  Future<void> _ensureLessonLoaded(int topicId, int lessonId) async {
    final tIndex = _topics.indexWhere((t) => t.id == topicId);
    if (tIndex < 0) return;
    final lIndex = _topics[tIndex].lessons.indexWhere((l) => l.id == lessonId);
    if (lIndex < 0) return;

    final lesson = _topics[tIndex].lessons[lIndex];
    if (!lesson.needsFetch) return;

    final rows = await apiService.fetchSyllabusContent(subtopicId: lesson.id);
    if (rows.isEmpty) return;

    final mapped = _mapContentRow(rows.first).copyWith(needsFetch: false);
    if (!mounted) return;

    setState(() {
      final updatedLessons = List<_Lesson>.from(_topics[tIndex].lessons);
      updatedLessons[lIndex] = mapped;
      final updatedTopic = _topics[tIndex].copyWith(lessons: updatedLessons);
      final updatedTopics = List<_Topic>.from(_topics);
      updatedTopics[tIndex] = updatedTopic;
      _topics = updatedTopics;
    });
  }

  String _plain(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isHttp(String value) {
    final v = value.trim().toLowerCase();
    return v.startsWith('http://') || v.startsWith('https://');
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  _Lesson? get _selectedLesson {
    if (_selectedTopicId == null || _selectedLessonId == null) return null;
    final topic = _topics.where((t) => t.id == _selectedTopicId).cast<_Topic?>().firstWhere((e) => e != null, orElse: () => null);
    if (topic == null) return null;
    return topic.lessons.where((l) => l.id == _selectedLessonId).cast<_Lesson?>().firstWhere((e) => e != null, orElse: () => null);
  }

  Widget _buildLeftPane() {
    return Container(
      color: const Color(0xFFF6F7FA),
      child: ListView(
        children: _topics.map((topic) {
          final isExpanded = _expandedTopics.contains(topic.id);
          return ExpansionTile(
            initiallyExpanded: isExpanded,
            onExpansionChanged: (v) {
              setState(() {
                if (v) {
                  _expandedTopics.add(topic.id);
                } else {
                  _expandedTopics.remove(topic.id);
                }
              });
            },
            title: Text(topic.title, style: const TextStyle(fontWeight: FontWeight.w600)),
            children: topic.lessons.map((lesson) {
              final selected = _selectedTopicId == topic.id && _selectedLessonId == lesson.id;
              return ListTile(
                dense: true,
                selected: selected,
                title: Text(lesson.title, style: TextStyle(fontSize: 13, color: selected ? Colors.black : Colors.black87)),
                onTap: () async {
                  setState(() {
                    _selectedTopicId = topic.id;
                    _selectedLessonId = lesson.id;
                  });
                  await _ensureLessonLoaded(topic.id, lesson.id);
                },
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRightPane() {
    final lesson = _selectedLesson;
    if (lesson == null) {
      return const Center(child: Text('Select a lesson from the left panel.'));
    }

    final bodyText = lesson.html.trim().isNotEmpty
        ? _plain(lesson.html)
        : (!_isHttp(lesson.rendered) ? lesson.rendered.trim() : '');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(lesson.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1F3B7A))),
              const SizedBox(height: 8),
              Text('Type: ${lesson.contentType} | Lesson ID: ${lesson.id}', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              if (bodyText.isNotEmpty)
                SelectableText(bodyText, style: const TextStyle(fontSize: 15, height: 1.5)),
              if (lesson.contentType == 'image' && lesson.primaryUrl != null) ...[
                const SizedBox(height: 12),
                Image.network(lesson.primaryUrl!, errorBuilder: (_, __, ___) => const Text('Image preview unavailable')),
              ],
              if (lesson.primaryUrl != null || lesson.altUrl != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (lesson.primaryUrl != null)
                      ElevatedButton.icon(
                        onPressed: () => _open(lesson.primaryUrl!),
                        icon: const Icon(Icons.open_in_new),
                        label: Text(lesson.contentType == 'iframe' ? 'Open Video' : 'Open Link'),
                      ),
                    if (lesson.altUrl != null)
                      OutlinedButton.icon(
                        onPressed: () => _open(lesson.altUrl!),
                        icon: const Icon(Icons.link),
                        label: const Text('Open Alt Link'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Syllabus'),
        backgroundColor: const Color(0xFF2D4F8F),
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 900;
                    if (isWide) {
                      return Row(
                        children: [
                          SizedBox(
                            width: 290,
                            child: _buildLeftPane(),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildRightPane()),
                        ],
                      );
                    }

                    return Column(
                      children: [
                        SizedBox(height: constraints.maxHeight * 0.42, child: _buildLeftPane()),
                        const Divider(height: 1),
                        Expanded(child: _buildRightPane()),
                      ],
                    );
                  },
                ),
      bottomNavigationBar: Container(
        color: const Color(0xFFF2F4F8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          'APIs: GradeInfo(stud_id=${apiService.currentStudentId ?? 'dynamic'}) | TopicInfo(main_id=$_mainId) | SubTopicInfo(topic_id from selected topic) | Content(Subtopic_id from selected lesson/topic)',
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ),
    );
  }
}
