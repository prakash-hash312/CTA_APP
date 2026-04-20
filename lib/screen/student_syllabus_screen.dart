// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_services.dart';

// ══════════════════════════════════════════════════════════════════════════════
//  MODELS
// ══════════════════════════════════════════════════════════════════════════════

class _Topic {
  final int id;
  final String title;
  final List<_Lesson> lessons;
  const _Topic({required this.id, required this.title, this.lessons = const []});
  _Topic copyWith({List<_Lesson>? lessons}) =>
      _Topic(id: id, title: title, lessons: lessons ?? this.lessons);
}

enum _Kind { text, image, video, pdf, file, link, unknown }

class _Lesson {
  final int id;        // SubSubTopicID – sidebar identity
  final int contentId; // SubTopicID    – sent to Content API as Subtopic_id
  final String title;
  final _Kind kind;
  final String bodyText;
  final String rawHtml;
  final String? mediaUrl;
  final String? altUrl;
  final bool needsFetch;

  const _Lesson({
    required this.id,
    int? contentId,
    required this.title,
    this.kind     = _Kind.unknown,
    this.bodyText = '',
    this.rawHtml  = '',
    this.mediaUrl,
    this.altUrl,
    this.needsFetch = false,
  }) : contentId = contentId ?? id;

  _Lesson copyWith({
    _Kind? kind, String? bodyText, String? rawHtml,
    String? mediaUrl, String? altUrl, bool? needsFetch,
  }) =>
      _Lesson(
        id: id, contentId: contentId, title: title,
        kind:      kind      ?? this.kind,
        bodyText:  bodyText  ?? this.bodyText,
        rawHtml:   rawHtml   ?? this.rawHtml,
        mediaUrl:  mediaUrl  ?? this.mediaUrl,
        altUrl:    altUrl    ?? this.altUrl,
        needsFetch: needsFetch ?? this.needsFetch,
      );

  bool get hasMedia => mediaUrl != null || altUrl != null;
  bool get hasBody  => bodyText.trim().isNotEmpty;
}

class _HtmlView extends StatefulWidget {
  final String html;
  final Future<void> Function(String) onOpen;

  const _HtmlView({required this.html, required this.onOpen});

  @override
  State<_HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<_HtmlView> {
  double _height = 300;
  InAppWebViewController? _controller;

  String get _document => '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<style>
html,body{margin:0;padding:0;background:transparent;overflow-x:hidden;width:100%}
body{color:#1E293B;padding:10px 12px 14px;box-sizing:border-box;-webkit-text-size-adjust:100%}
*,*::before,*::after{box-sizing:border-box}
img,video,iframe,canvas{max-width:100%!important;height:auto!important}
table{width:100%!important;max-width:100%!important;border-collapse:collapse!important}
td,th{white-space:normal!important;word-break:break-word!important;vertical-align:top;padding:4px 6px}
p,li,h1,h2,h3,h4,h5,h6,span,div{word-break:break-word;overflow-wrap:anywhere}
ul,ol{padding-left:20px!important}
a{color:#1E429F;word-break:break-all}
</style>
<script>
function cleanup(){
  document.querySelectorAll('a,button').forEach((el)=>{
    const txt=(el.innerText||el.textContent||'').trim().toLowerCase();
    if(txt==='open content'||txt==='alt link'){el.remove();}
  });
  document.querySelectorAll('*').forEach((node)=>{node.style.maxWidth='100%';});
  document.querySelectorAll('table').forEach((table)=>{
    table.removeAttribute('width');
    table.style.width='100%';
  });
}
document.addEventListener('DOMContentLoaded', cleanup);
window.addEventListener('load', cleanup);
</script>
</head>
<body>${widget.html}</body>
</html>''';

  Future<void> _syncHeight(InAppWebViewController controller) async {
    final result = await controller.evaluateJavascript(
      source:
          'Math.max(document.body.scrollHeight,document.documentElement.scrollHeight).toString()',
    );
    final parsed = double.tryParse('$result');
    if (parsed != null && parsed > 0 && mounted) {
      setState(() => _height = parsed + 24);
    }
  }

  @override
  void didUpdateWidget(covariant _HtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html) {
      _height = 300;
      _controller?.loadData(
        data: _document,
        baseUrl: WebUri('https://www.ivpsemi.in/CTA_Mob/'),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height,
      child: InAppWebView(
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          disableVerticalScroll: true,
          disableHorizontalScroll: true,
          javaScriptEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
          supportZoom: false,
        ),
        initialData: InAppWebViewInitialData(
          data: _document,
          baseUrl: WebUri('https://www.ivpsemi.in/CTA_Mob/'),
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onLoadStop: (controller, _) async {
          await _syncHeight(controller);
          await Future.delayed(const Duration(milliseconds: 300));
          await _syncHeight(controller);
        },
        shouldOverrideUrlLoading: (_, action) async {
          final url = action.request.url?.toString() ?? '';
          if (url.startsWith('http://') || url.startsWith('https://')) {
            await widget.onOpen(url);
            return NavigationActionPolicy.CANCEL;
          }
          return NavigationActionPolicy.ALLOW;
        },
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class StudentSyllabusScreen extends StatefulWidget {
  const StudentSyllabusScreen({super.key});
  @override
  State<StudentSyllabusScreen> createState() => _StudentSyllabusScreenState();
}

class _StudentSyllabusScreenState extends State<StudentSyllabusScreen>
    with SingleTickerProviderStateMixin {

  // ── state ──────────────────────────────────────────────────────────────────
  bool    _loading = true;
  String? _error;
  String  _gradeTitle = 'My Syllabus';
  int     _mainId  = 0;
  List<_Topic> _topics  = [];
  int? _selectedTopicId;
  int? _selectedLessonId;
  final Set<int> _expandedTopics = {};
  bool _showContent = false; // mobile: toggle sidebar ↔ content

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  // ── palette ────────────────────────────────────────────────────────────────
  static const _navy   = Color(0xFF0D1F4C);
  static const _blue   = Color(0xFF1E429F);
  static const _sky    = Color(0xFF3B82F6);
  static const _gold   = Color(0xFFF59E0B);
  static const _bg     = Color(0xFFF1F5FB);
  static const _border = Color(0xFFDAE0EE);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _load();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  KEY HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  int _int(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null) {
        final p = int.tryParse('$v');
        if (p != null && p > 0) return p;
      }
    }
    // fuzzy scan
    for (final e in m.entries) {
      for (final k in keys) {
        if (e.key.toLowerCase().contains(k.toLowerCase())) {
          final p = int.tryParse('${e.value}');
          if (p != null && p > 0) return p;
        }
      }
    }
    return 0;
  }

  String _str(Map<String, dynamic> m, List<String> keys,
      {String fallback = ''}) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty) return '$v'.trim();
    }
    return fallback;
  }

  bool _isImage(String url) {
    final u = url.toLowerCase();
    return u.contains('.jpg') || u.contains('.jpeg') || u.contains('.png') ||
           u.contains('.gif') || u.contains('.webp') || u.contains('.bmp');
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LOAD
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _load() async {
    setState(() {
      _loading = true; _error = null;
      _topics = []; _selectedTopicId = null;
      _selectedLessonId = null; _expandedTopics.clear();
      _showContent = false;
    });

    try {
      // 1 ── student id
      final studId = await apiService.ensureCurrentStudentId();
      if (studId == null) {
        throw Exception('User session not found. Please login again.');
      }
      debugPrint('👤 Syllabus loading for Student ID: $studId');

      // 2 ── GradeInfo → mainId
      final gradeRows = await apiService.fetchSyllabusGradeInfo(studId: studId);
      if (gradeRows.isNotEmpty) {
        debugPrint('📚 GradeInfo keys=${gradeRows.first.keys.toList()}');
        debugPrint('📚 GradeInfo[0]=${gradeRows.first}');
        final g = gradeRows.first;
        _mainId = _int(g, [
          'MainTopicID','main_topic_id','MainID','main_id',
          'GradeID','grade_id','ID','id',
        ]);
        _gradeTitle = _str(g, [
          'Title','title','GradeName','grade_name','Name','name',
        ], fallback: 'My Syllabus');
        debugPrint('📚 mainId=$_mainId  title=$_gradeTitle');
      }
      if (_mainId == 0) {
        throw Exception(
          'Cannot find MainTopicID.\nKeys: ${gradeRows.isNotEmpty ? gradeRows.first.keys.toList() : []}',
        );
      }

      // 3 ── TopicInfo
      final topicRows = await apiService.fetchSyllabusTopicInfo(mainId: _mainId);
      debugPrint('📚 TopicInfo rows=${topicRows.length}');
      if (topicRows.isNotEmpty) {
        debugPrint('📚 TopicInfo keys=${topicRows.first.keys.toList()}');
      }

      final topics = <_Topic>[];
      for (final t in topicRows) {
        int topicId = _int(t, [
          'SubTopicID','sub_topic_id','TopicID','topic_id','ID','id',
        ]);
        if (topicId == 0) continue;
        final topicTitle = _str(t, ['Title','title','Name','name'],
            fallback: 'Topic $topicId');
        debugPrint('📚 Topic id=$topicId "$topicTitle"');

        // 4 ── SubTopicInfo
        List<_Lesson> lessons = [];
        try {
          final subRows = await apiService
              .fetchSyllabusSubTopicInfo(topicId: topicId);
          debugPrint('  Sub rows=${subRows.length} for topicId=$topicId');
          if (subRows.isNotEmpty) {
            debugPrint('  Sub keys=${subRows.first.keys.toList()}');
          }
          for (final s in subRows) {
            int sid = _int(s, [
              'SubSubTopicID','sub_sub_topic_id',
              'SubTopicID','sub_topic_id','ID','id',
            ]);
            if (sid == 0) continue;
            final stitle = _str(s, ['Title','title','Name','name'],
                fallback: 'Lesson $sid');
            lessons.add(_Lesson(
              // Use the original SubSubTopicID returned by the API when
              // requesting lesson content so topic/subtopic/content stay aligned.
              id: sid, contentId: sid,
              title: stitle, needsFetch: true,
            ));
          }
        } catch (e) { debugPrint('  ⚠️ SubTopicInfo: $e'); }

        // fallback: content directly
        if (lessons.isEmpty) {
          try {
            final direct = await apiService
                .fetchSyllabusContent(subtopicId: topicId);
            if (direct.isNotEmpty) {
              lessons = direct.map((r) => _mapRow(r, topicId)).toList();
            }
          } catch (_) {}
        }

        topics.add(_Topic(id: topicId, title: topicTitle, lessons: lessons));
      }

      if (!mounted) return;

      int? selTopic, selLesson;
      for (final tp in topics) {
        if (tp.lessons.isNotEmpty) {
          selTopic  = tp.id;
          selLesson = tp.lessons.first.id;
          break;
        }
      }

      setState(() {
        _topics = topics;
        _selectedTopicId  = selTopic;
        _selectedLessonId = selLesson;
        if (selTopic != null) _expandedTopics.add(selTopic);
        _loading = false;
      });
      _fadeCtrl.forward(from: 0);

      if (selTopic != null && selLesson != null) {
        await _loadLesson(selTopic, selLesson);
      }
    } catch (e, st) {
      debugPrint('❌ _load: $e\n$st');
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  MAP CONTENT ROW
  // ══════════════════════════════════════════════════════════════════════════

  _Lesson _mapRow(Map<String, dynamic> row, int parentId,
      {int? displayId, String? displayTitle}) {
    debugPrint('📄 Content keys: ${row.keys.toList()}');
    debugPrint('📄 Content row : $row');

    final id = displayId ?? _int(row, [
      'SubSubTopicID','sub_sub_topic_id',
      'SubTopicID','sub_topic_id',
      'ContentID','content_id','ID','id',
    ]);
    final title = displayTitle ??
        _str(row, ['Title','title','Name','name'], fallback: 'Lesson');

    final typeRaw = _str(row, [
      'ContentType','content_type','Type','type',
    ], fallback: 'content').toLowerCase().trim();
    final kind = _kindFromType(typeRaw);

    final iframe    = _str(row, ['IframeUrl','iframe_url','VideoUrl','video_url']);
    final rendered  = _str(row, ['RenderedContent','rendered_content','Rendered','rendered']);
    final fileN     = _str(row, ['FileName','file_name','File','file','FilePath','file_path']);
    final directUrl = _str(row, ['Url','url','Link','link','Path','path']);

    final rawHtml  = _str(row, [
      'ContentHtml','content_html','Html','html',
      'Content','content','Body','body','Description','description',
      if (!_http(rendered)) 'RenderedContent',
    ]);
    final bodyText = _stripHtml(rawHtml);

    String? primary, alt;

    if (_http(iframe))        primary = iframe.trim();
    else if (_http(directUrl))primary = directUrl.trim();
    else if (_http(rendered)) primary = rendered.trim();
    else if (fileN.isNotEmpty &&
             !fileN.toLowerCase().startsWith('d:') &&
             !fileN.toLowerCase().startsWith('c:')) {
      final clean = fileN.contains('/') ? fileN.split('/').last : fileN;
      final encoded = Uri.encodeComponent(clean.trim());
      primary = 'https://www.ivpsemi.in/CTA_Mob/HomeworkFiles/$encoded';
      alt     = 'https://www.ivpsemi.in/HomeworkFiles/$encoded';
    } else if (rendered.isNotEmpty &&
               !rendered.toLowerCase().startsWith('d:') &&
               rendered.contains('/')) {
      final frag = rendered.split('/').last;
      if (frag.isNotEmpty) {
        final encoded = Uri.encodeComponent(frag.trim());
        primary = 'https://www.ivpsemi.in/CTA_Mob/HomeworkFiles/$encoded';
        alt     = 'https://www.ivpsemi.in/HomeworkFiles/$encoded';
      }
    }

    _Kind resolvedKind = kind;
    if ((resolvedKind == _Kind.unknown || resolvedKind == _Kind.text) &&
        primary != null) {
      resolvedKind = _kindFromUrl(primary);
    }

    debugPrint('📄 → id=$id kind=$resolvedKind primary=$primary alt=$alt');

    return _Lesson(
      id: id, contentId: parentId, title: title,
      kind: resolvedKind, bodyText: bodyText, rawHtml: rawHtml,
      mediaUrl: primary, altUrl: alt, needsFetch: false,
    );
  }

  _Kind _kindFromType(String t) {
    if (t.contains('video') || t.contains('iframe')) return _Kind.video;
    if (t.contains('image') || t.contains('img'))    return _Kind.image;
    if (t.contains('pdf'))                           return _Kind.pdf;
    if (t.contains('file') || t.contains('doc'))     return _Kind.file;
    if (t.contains('link') || t.contains('url'))     return _Kind.link;
    if (t.contains('text') || t.contains('html') || t.contains('content'))
                                                     return _Kind.text;
    return _Kind.unknown;
  }

  _Kind _kindFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('youtube') || u.contains('vimeo') ||
        u.endsWith('.mp4') || u.endsWith('.webm'))   return _Kind.video;
    if (u.endsWith('.jpg')  || u.endsWith('.jpeg') ||
        u.endsWith('.png')  || u.endsWith('.gif') ||
        u.endsWith('.webp') || u.endsWith('.bmp'))   return _Kind.image;
    if (u.endsWith('.pdf'))                          return _Kind.pdf;
    if (u.endsWith('.doc')  || u.endsWith('.docx') ||
        u.endsWith('.ppt')  || u.endsWith('.pptx') ||
        u.endsWith('.xls')  || u.endsWith('.xlsx'))  return _Kind.file;
    return _Kind.link;
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  LAZY LOAD LESSON CONTENT
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadLesson(int topicId, int lessonId) async {
    final ti = _topics.indexWhere((t) => t.id == topicId);
    if (ti < 0) return;
    final li = _topics[ti].lessons.indexWhere((l) => l.id == lessonId);
    if (li < 0) return;
    final lesson = _topics[ti].lessons[li];
    if (!lesson.needsFetch) return;

    _Lesson updated;
    try {
      debugPrint('📥 loadLesson id=$lessonId contentId=${lesson.contentId}');
      final rows = await apiService
          .fetchSyllabusContent(subtopicId: lesson.id);
      debugPrint('📥 rows=${rows.length}');

      if (rows.isNotEmpty) {
        // Find the specific content row matching the selected lesson ID (SubSubTopicID)
        final match = rows.firstWhere(
          (r) => _int(r, ['SubSubTopicID', 'sub_sub_topic_id', 'ContentID', 'id']) == lessonId,
          orElse: () => rows.first,
        );
        updated = _mapRow(match, lesson.contentId,
            displayId: lesson.id, displayTitle: lesson.title);
      } else {
        updated = lesson.copyWith(needsFetch: false);
      }
    } catch (e) {
      debugPrint('⚠️ loadLesson error: $e');
      updated = lesson.copyWith(needsFetch: false);
    }

    if (!mounted) return;
    _fadeCtrl.forward(from: 0);
    setState(() {
      final ls = List<_Lesson>.from(_topics[ti].lessons)..[li] = updated;
      final ts = List<_Topic>.from(_topics)
        ..[ti] = _topics[ti].copyWith(lessons: ls);
      _topics = ts;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  bool _http(String v) {
    final s = v.trim().toLowerCase();
    return s.startsWith('http://') || s.startsWith('https://');
  }

  String _stripHtml(String h) => h
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<').replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"').replaceAll(RegExp(r'\s+'), ' ').trim();

  Future<void> _open(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    debugPrint('🔗 Opening: $url');
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(uri,
          mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('❌ launchUrl: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cannot open: $url'),
          backgroundColor: Colors.red.shade700,
          action: SnackBarAction(
            label: 'Copy',
            textColor: Colors.white,
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          ),
        ));
      }
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  _Lesson? get _current {
    if (_selectedTopicId == null || _selectedLessonId == null) return null;
    try {
      return _topics.firstWhere((t) => t.id == _selectedTopicId)
          .lessons.firstWhere((l) => l.id == _selectedLessonId);
    } catch (_) { return null; }
  }

  List<({int topicId, _Lesson lesson})> get _flatLessons {
    final out = <({int topicId, _Lesson lesson})>[];
    for (final topic in _topics) {
      for (final lesson in topic.lessons) {
        out.add((topicId: topic.id, lesson: lesson));
      }
    }
    return out;
  }

  int get _currentFlatIndex {
    if (_selectedTopicId == null || _selectedLessonId == null) return -1;
    return _flatLessons.indexWhere(
      (item) =>
          item.topicId == _selectedTopicId &&
          item.lesson.id == _selectedLessonId,
    );
  }

  ({int topicId, _Lesson lesson})? get _prevItem {
    final index = _currentFlatIndex;
    if (index <= 0) return null;
    return _flatLessons[index - 1];
  }

  ({int topicId, _Lesson lesson})? get _nextItem {
    final index = _currentFlatIndex;
    if (index < 0 || index >= _flatLessons.length - 1) return null;
    return _flatLessons[index + 1];
  }

  Future<void> _selectLesson(int topicId, int lessonId) async {
    setState(() {
      _selectedTopicId = topicId;
      _selectedLessonId = lessonId;
      _showContent = true;
      _expandedTopics.add(topicId);
    });
    await _loadLesson(topicId, lessonId);
  }

  // ── kind metadata ──────────────────────────────────────────────────────────
  static const _kindMeta = {
    _Kind.video:   ('VIDEO',   Color(0xFFDC2626), Icons.play_circle_filled_rounded),
    _Kind.image:   ('IMAGE',   Color(0xFF059669), Icons.image_rounded),
    _Kind.pdf:     ('PDF',     Color(0xFFEA580C), Icons.picture_as_pdf_rounded),
    _Kind.file:    ('FILE',    Color(0xFF7C3AED), Icons.insert_drive_file_rounded),
    _Kind.text:    ('TEXT',    Color(0xFF1E429F), Icons.article_rounded),
    _Kind.link:    ('LINK',    Color(0xFF0284C7), Icons.link_rounded),
    _Kind.unknown: ('CONTENT', Color(0xFF475569), Icons.auto_stories_rounded),
  };

  (String, Color, IconData) _meta(_Kind k) =>
      _kindMeta[k] ?? ('CONTENT', const Color(0xFF475569), Icons.auto_stories_rounded);

  // ══════════════════════════════════════════════════════════════════════════
  //  LEFT PANE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildSidebar() {
    if (_topics.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.menu_book_outlined, size: 48,
              color: _blue.withOpacity(.2)),
          const SizedBox(height: 12),
          const Text('No topics found',
              style: TextStyle(color: Colors.black45, fontSize: 14)),
        ]),
      );
    }

    return Container(
      color: const Color(0xFFF8FAFF),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
        itemCount: _topics.length,
        itemBuilder: (_, i) {
          final topic = _topics[i];
          final exp   = _expandedTopics.contains(topic.id);
          return _buildTopicTile(topic, i, exp);
        },
      ),
    );
  }

  Widget _buildTopicTile(_Topic topic, int idx, bool expanded) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.03),
              blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          onExpansionChanged: (v) => setState(() {
            v ? _expandedTopics.add(topic.id)
              : _expandedTopics.remove(topic.id);
          }),
          tilePadding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          leading: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_blue, _sky],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text('${idx + 1}',
                  style: const TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ),
          title: Text(topic.title,
              style: const TextStyle(fontSize: 13.5,
                  fontWeight: FontWeight.w700, color: _navy)),
          subtitle: Text('${topic.lessons.length} lessons',
              style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(.35))),
          iconColor: _blue,
          collapsedIconColor: Colors.black38,
          children: [
            const Divider(height: 1, indent: 12, endIndent: 12),
            const SizedBox(height: 4),
            if (topic.lessons.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Text('No lessons available',
                    style: TextStyle(fontSize: 12, color: Colors.black38)),
              )
            else
              ...topic.lessons.map((l) => _buildLessonTile(topic, l)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildLessonTile(_Topic topic, _Lesson lesson) {
    final sel = _selectedTopicId == topic.id && _selectedLessonId == lesson.id;
    final (_, color, icon) = _meta(lesson.kind);

    return GestureDetector(
      onTap: () => _selectLesson(topic.id, lesson.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.fromLTRB(8, 2, 8, 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? _blue.withOpacity(.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: sel ? _blue.withOpacity(.3) : Colors.transparent),
        ),
        child: Row(children: [
          Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              color: sel ? color : color.withOpacity(.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14,
                color: sel ? Colors.white : color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(lesson.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                  color: sel ? _blue : const Color(0xFF374151),
                )),
          ),
          if (sel)
            const Icon(Icons.chevron_right_rounded, size: 16, color: _sky),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  RIGHT PANE
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildContentPane() {
    final lesson = _current;

    // ── empty selection ────────────────────────────────────────────────────
    if (lesson == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [
                _blue.withOpacity(.12), _blue.withOpacity(.03),
              ]),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_stories_rounded,
                size: 48, color: _blue),
          ),
          const SizedBox(height: 20),
          const Text('Select a lesson',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                  color: _navy)),
          const SizedBox(height: 8),
          const Text('Choose a topic from the left panel',
              style: TextStyle(color: Colors.black45)),
        ]),
      );
    }

    // ── loading ────────────────────────────────────────────────────────────
    if (lesson.needsFetch) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 56, height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3, color: _blue,
              backgroundColor: _blue.withOpacity(.1),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Loading content…',
              style: TextStyle(color: Colors.black54, fontSize: 14)),
        ]),
      );
    }

    final prev = _prevItem;
    final next = _nextItem;

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        children: [
          Container(
            color: _navy,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: prev == null
                        ? null
                        : () => _selectLesson(prev.topicId, prev.lesson.id),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 15),
                    label: const Text(
                      'Previous',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          prev == null ? Colors.white38 : Colors.white,
                      side: BorderSide(
                        color: prev == null ? Colors.white24 : Colors.white60,
                        width: 1.2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: next == null
                        ? null
                        : () => _selectLesson(next.topicId, next.lesson.id),
                    icon: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                    label: const Text(
                      'Next',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          next == null ? const Color(0xFF334E7A) : _sky,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF334E7A),
                      disabledForegroundColor: Colors.white38,
                      elevation: next == null ? 0 : 2,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lesson.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (lesson.mediaUrl != null &&
                      _isImage(lesson.mediaUrl!)) ...[
                    _buildImageCard(lesson.mediaUrl!),
                    const SizedBox(height: 16),
                  ] else if (lesson.mediaUrl != null &&
                      lesson.kind == _Kind.video) ...[
                    _buildVideoFrame(lesson.mediaUrl!),
                    const SizedBox(height: 16),
                  ],
                  if (lesson.rawHtml.trim().isNotEmpty) ...[
                    _buildHtmlView(lesson.rawHtml),
                    const SizedBox(height: 16),
                  ] else if (lesson.hasBody) ...[
                    _buildTextCard(lesson.bodyText),
                    const SizedBox(height: 16),
                  ],
                  if (!lesson.hasBody &&
                      lesson.rawHtml.trim().isEmpty &&
                      lesson.mediaUrl == null) ...[
                    _buildEmptyCard(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCard(String url) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(.07),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (ctx, child, prog) {
            if (prog == null) return child;
            final total = prog.expectedTotalBytes;
            final pct   = total != null
                ? prog.cumulativeBytesLoaded / total : null;
            return Container(
              height: 220,
              color: const Color(0xFFF0F5FF),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(
                      value: pct, color: _blue,
                      backgroundColor: _blue.withOpacity(.1)),
                  const SizedBox(height: 12),
                  const Text('Loading image…',
                      style: TextStyle(color: Colors.black38, fontSize: 12)),
                ]),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            height: 150,
            color: const Color(0xFFF8FAFF),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.broken_image_outlined,
                  size: 36, color: Colors.black26),
              const SizedBox(height: 8),
              const Text('Image could not load',
                  style: TextStyle(color: Colors.black45)),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _open(url),
                icon: const Icon(Icons.open_in_browser_rounded, size: 14),
                label: const Text('Open in browser', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: _blue),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildTextCard(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: SelectableText(text,
          style: const TextStyle(fontSize: 15, height: 1.75, color: Color(0xFF1E293B))),
    );
  }

  Widget _buildHtmlView(String html) {
    return _HtmlView(html: html, onOpen: _open);
  }

  Widget _buildVideoFrame(String url) {
    final embedUrl = url.contains('watch?v=') ? url.replaceFirst('watch?v=', 'embed/') : url;
    return Container(
      height: 220,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: ClipRRect(borderRadius: BorderRadius.circular(14),
        child: InAppWebView(initialUrlRequest: URLRequest(url: WebUri(embedUrl)))),
    );
  }

  Widget _buildActions(_Lesson l, String tag, Color color, IconData icon) {
    final btnLabel = l.kind == _Kind.video ? 'Watch Video'
        : l.kind == _Kind.image ? 'View Image'
        : l.kind == _Kind.pdf   ? 'Open PDF'
        : l.kind == _Kind.file  ? 'Open File'
        : 'Open Content';

    return Wrap(spacing: 10, runSpacing: 10, children: [
      if (l.mediaUrl != null)
        ElevatedButton.icon(
          onPressed: () => _open(l.mediaUrl!),
          icon: Icon(icon, size: 18),
          label: Text(btnLabel,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            elevation: 3,
            shadowColor: color.withOpacity(.4),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      if (l.altUrl != null)
        OutlinedButton.icon(
          onPressed: () => _open(l.altUrl!),
          icon: const Icon(Icons.link_rounded, size: 16),
          label: const Text('Alt Link',
              style: TextStyle(fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(
            foregroundColor: _blue,
            side: const BorderSide(color: _blue, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
    ]);
  }

  Widget _buildUrlChip(String label, String url) {
    return InkWell(
      onTap: () => _open(url),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _blue.withOpacity(.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.link_rounded, size: 14, color: _blue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: Colors.black.withOpacity(.4), letterSpacing: .5)),
              const SizedBox(height: 2),
              Text(url, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: _sky)),
            ]),
          ),
          const SizedBox(width: 4),
          // copy
          IconButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              _snack('Copied!');
            },
            icon: const Icon(Icons.copy_rounded, size: 15, color: Colors.black38),
            tooltip: 'Copy URL',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          // open
          IconButton(
            onPressed: () => _open(url),
            icon: const Icon(Icons.open_in_new_rounded, size: 15, color: _blue),
            tooltip: 'Open',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      ),
    );
  }

  Widget _buildEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5FF), shape: BoxShape.circle,
          ),
          child: const Icon(Icons.inbox_outlined, size: 36, color: Colors.black26),
        ),
        const SizedBox(height: 14),
        const Text('No content yet',
            style: TextStyle(fontWeight: FontWeight.w700,
                fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 6),
        const Text('This lesson doesn\'t have any material assigned.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black38)),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  APP BAR
  // ══════════════════════════════════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar(bool isMobile) {
    final showBack = isMobile && _showContent;
    return AppBar(
      elevation: 0,
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => setState(() => _showContent = false),
              tooltip: 'Back to topics',
            )
          : null,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          showBack ? (_current?.title ?? _gradeTitle) : _gradeTitle,
          style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 16, letterSpacing: .2),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        if (!_loading && _error == null && !showBack)
          Text(
            '${_topics.length} topics  •  ID ${apiService.currentStudentId ?? "–"}',
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
      ]),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _load, tooltip: 'Refresh',
        ),
      ],
      bottom: _loading
          ? PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: LinearProgressIndicator(
                backgroundColor: _navy, color: _gold, minHeight: 3),
            )
          : null,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      final isMobile = box.maxWidth < 800;

      return Scaffold(
        backgroundColor: _bg,
        appBar: _buildAppBar(isMobile),
        body: _loading
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 60, height: 60,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: _blue,
                        backgroundColor: _blue.withOpacity(.1)),
                  ),
                  const SizedBox(height: 20),
                  const Text('Loading your syllabus…',
                      style: TextStyle(color: Colors.black54, fontSize: 15)),
                ]),
              )
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                              color: Color(0xFFFEF2F2),
                              shape: BoxShape.circle),
                          child: const Icon(Icons.error_outline_rounded,
                              color: Color(0xFFDC2626), size: 48),
                        ),
                        const SizedBox(height: 18),
                        const Text('Something went wrong',
                            style: TextStyle(fontWeight: FontWeight.w800,
                                fontSize: 18, color: _navy)),
                        const SizedBox(height: 8),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Color(0xFFDC2626), fontSize: 13)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ]),
                    ),
                  )
                : isMobile
                    // ── MOBILE ──────────────────────────────────────────────
                    ? (_showContent
                        ? _buildContentPane()
                        : _buildSidebar())
                    // ── TABLET / DESKTOP ─────────────────────────────────────
                    : Row(children: [
                        SizedBox(width: 320, child: _buildSidebar()),
                        Container(width: 1, color: _border),
                        Expanded(child: _buildContentPane()),
                      ]),
      );
    });
  }
}
