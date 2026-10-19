import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'student_theme.dart';
import 'toeic_api.dart';

String _error(Object error) => error.toString().replaceFirst('Exception: ', '');

DateTime? _dateValue(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String _date(dynamic value, {bool weekday = false}) {
  final date = _dateValue(value);
  if (date == null) return 'Chưa công bố';
  String two(int number) => number.toString().padLeft(2, '0');
  final weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  final prefix = weekday ? '${weekdays[date.weekday - 1]}, ' : '';
  return '$prefix${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

String _shift(dynamic value) => switch (value) {
  'Morning' => 'Ca sáng',
  'Afternoon' => 'Ca chiều',
  'Evening' => 'Ca tối',
  'Other' => 'Ca khác',
  _ => 'Chưa phân loại',
};

Map<String, dynamic> _asMap(dynamic value) =>
    Map<String, dynamic>.from(value as Map);

final _embeddedImagePattern = RegExp(
  r'\[\[TOEIC_IMAGE:(data:image/(?:png|jpeg|gif|webp);base64,[A-Za-z0-9+/=]+)\]\]',
);

class StudentRichContent extends StatelessWidget {
  const StudentRichContent({
    required this.content,
    this.style,
    this.selectable = true,
    super.key,
  });

  final String content;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final children = <Widget>[];
      Widget textWidget(String value) => selectable
          ? SelectableText(value, style: style)
          : Text(value, style: style);
      var offset = 0;
      for (final match in _embeddedImagePattern.allMatches(content)) {
        if (match.start > offset) {
          children.add(textWidget(content.substring(offset, match.start)));
        }
        final dataUri = match.group(1)!;
        final comma = dataUri.indexOf(',');
        final bytes = base64Decode(dataUri.substring(comma + 1));
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Image.memory(
              bytes,
              width: maxWidth,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Text(
                'Không thể hiển thị ảnh trong đề.',
                style: TextStyle(color: StudentColors.red, fontSize: 12),
              ),
            ),
          ),
        );
        offset = match.end;
      }
      if (offset < content.length || children.isEmpty) {
        children.add(textWidget(content.substring(offset)));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    },
  );
}

class ToeicStudentApp extends StatelessWidget {
  const ToeicStudentApp({this.api, super.key});

  final ToeicApi? api;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TOEIC Campus',
    debugShowCheckedModeBanner: false,
    theme: studentTheme,
    builder: (context, child) =>
        StudentAppViewport(child: child ?? const SizedBox.shrink()),
    home: _LoginScreen(api: api),
  );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({this.api});

  final ToeicApi? api;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final ToeicApi _api;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _api = widget.api ?? ToeicApi();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    if (widget.api == null) _api.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _message = 'Nhập tên đăng nhập và mật khẩu.');
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _api.login(_username.text, _password.text);
      if (!mounted) return;
      _password.clear();
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => _StudentHome(api: _api)),
      );
      _api.logout();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 56),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: AutofillGroup(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandMark(),
                      const SizedBox(height: 28),
                      Text(
                        'Đăng nhập',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Dành cho sinh viên tham gia ôn luyện và thi TOEIC Reading',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: StudentColors.muted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_message != null) ...[
                        _InlineMessage(message: _message!, isError: true),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _username,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Tên đăng nhập / Mã sinh viên',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_busy) _login();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : _login,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: Text(_busy ? 'Đang đăng nhập' : 'Đăng nhập'),
                      ),
                      const SizedBox(height: 18),
                      StudentSurface(
                        padding: const EdgeInsets.all(14),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: StudentColors.secondary,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chính sách cấp tài khoản',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  SizedBox(height: 5),
                                  Text(
                                    'Tài khoản thi do giảng viên hoặc nhà trường cấp trước ca thi. Sinh viên không tự đăng ký tài khoản.',
                                    style: TextStyle(
                                      color: StudentColors.muted,
                                      height: 1.45,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Cần trợ giúp phòng máy hoặc cấp lại mật khẩu?',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: StudentColors.muted),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Liên hệ cán bộ coi thi hoặc Phòng Đào tạo',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: StudentColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: StudentColors.primaryBright,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.school_rounded, color: Colors.white, size: 32),
      ),
      const SizedBox(height: 9),
      const Text(
        'TOEIC CAMPUS',
        style: TextStyle(
          color: StudentColors.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          fontSize: 13,
        ),
      ),
    ],
  );
}

class _StudentHome extends StatefulWidget {
  const _StudentHome({required this.api});

  final ToeicApi api;

  @override
  State<_StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<_StudentHome> {
  List<dynamic> _sessions = [];
  List<Map<String, dynamic>> _results = [];
  int _tab = 0;
  int _filter = 0;
  bool _loadingSessions = true;
  bool _loadingResults = false;
  bool _resultsLoaded = false;
  String? _sessionsError;
  String? _resultsError;

  static const _filters = ['Tất cả', 'Đang làm', 'Chưa vào thi', 'Đã nộp'];

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loadingSessions = true;
      _sessionsError = null;
      _resultsLoaded = false;
    });
    try {
      final sessions = await widget.api.sessions();
      if (mounted) setState(() => _sessions = sessions);
    } catch (error) {
      if (mounted) setState(() => _sessionsError = _error(error));
    } finally {
      if (mounted) setState(() => _loadingSessions = false);
    }
  }

  Future<void> _loadResults() async {
    if (_loadingResults) return;
    setState(() {
      _loadingResults = true;
      _resultsError = null;
    });
    try {
      final sessions = await widget.api.sessions();
      final submitted = sessions
          .map(_asMap)
          .where(
            (session) =>
                session['attemptStatus'] == 'Submitted' &&
                session['attemptId'] != null,
          )
          .toList();
      final results = await Future.wait(
        submitted.map((session) async {
          final attempt = await widget.api.attempt(
            session['attemptId'].toString(),
          );
          return {'session': session, 'data': attempt};
        }),
      );
      if (mounted) {
        setState(() {
          _sessions = sessions;
          _results = results;
          _resultsLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _resultsError = _error(error));
    } finally {
      if (mounted) setState(() => _loadingResults = false);
    }
  }

  void _selectTab(int index) {
    setState(() => _tab = index);
    if (index == 2 && !_resultsLoaded) _loadResults();
  }

  Future<void> _openSession(Map<String, dynamic> session) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _SessionDetail(
          session: session,
          onOpen: () async {
            final attemptId = session['attemptId'];
            final data = attemptId == null
                ? await widget.api.start(session['id'] as int)
                : await widget.api.attempt(attemptId.toString());
            if (!mounted) return;
            await Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => _AttemptScreen(api: widget.api, data: data),
              ),
            );
            if (mounted) await _loadSessions();
          },
        ),
      ),
    );
    if (mounted) await _loadSessions();
  }

  List<Map<String, dynamic>> get _visibleSessions {
    final sessions = _sessions.map(_asMap).toList();
    return sessions.where((session) {
      final attemptStatus = session['attemptStatus'];
      return switch (_filter) {
        1 => attemptStatus == 'InProgress',
        2 => attemptStatus == null && session['status'] == 'Published',
        3 => attemptStatus == 'Submitted',
        _ => true,
      };
    }).toList();
  }

  String get _pageTitle => switch (_tab) {
    1 => 'Luyện tập',
    2 => 'Kết quả',
    3 => 'Tài khoản',
    _ => 'Lịch thi',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      toolbarHeight: 60,
      titleSpacing: 18,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: StudentColors.primaryBright,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TOEIC CAMPUS',
                style: TextStyle(
                  fontSize: 10,
                  color: StudentColors.muted,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                _pageTitle,
                style: const TextStyle(
                  fontSize: 16,
                  color: StudentColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (_tab == 0 || _tab == 2)
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _tab == 0
                ? (_loadingSessions ? null : _loadSessions)
                : (_loadingResults ? null : _loadResults),
            icon: const Icon(Icons.refresh),
          ),
        IconButton(
          tooltip: 'Tài khoản',
          onPressed: () => _selectTab(3),
          icon: const Icon(Icons.account_circle_outlined),
        ),
        const SizedBox(width: 6),
      ],
    ),
    body: IndexedStack(
      index: _tab,
      children: [
        _schedulePage(),
        _practicePage(),
        _resultsPage(),
        _accountPage(),
      ],
    ),
    bottomNavigationBar: StudentTabBar(
      selectedIndex: _tab,
      onSelected: _selectTab,
    ),
  );

  Widget _schedulePage() => RefreshIndicator(
    onRefresh: _loadSessions,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      children: [
        const Text(
          'Lịch thi của tôi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Mã hồ sơ ${widget.api.profile?['personId'] ?? 'đã xác thực'}',
          style: const TextStyle(color: StudentColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (_sessions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: StudentColors.greenSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_outlined,
                  color: StudentColors.green,
                  size: 20,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${_sessions.length} ca thi được phân công',
                    style: const TextStyle(
                      color: StudentColors.green,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < _filters.length; index++) ...[
                ChoiceChip(
                  label: Text(_filters[index]),
                  selected: _filter == index,
                  onSelected: (_) => setState(() => _filter = index),
                  showCheckmark: false,
                  selectedColor: StudentColors.primaryBright,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    color: _filter == index ? Colors.white : StudentColors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: _filter == index
                        ? StudentColors.primaryBright
                        : StudentColors.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                if (index != _filters.length - 1) const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loadingSessions) const LinearProgressIndicator(minHeight: 2),
        if (_sessionsError != null) ...[
          const SizedBox(height: 18),
          StudentStateMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Không tải được lịch thi',
            message: _sessionsError!,
            isError: true,
            actionLabel: 'Thử lại',
            onAction: _loadSessions,
          ),
        ] else if (!_loadingSessions && _sessions.isEmpty) ...[
          const SizedBox(height: 36),
          const StudentStateMessage(
            icon: Icons.event_busy_outlined,
            title: 'Chưa có ca thi được phân công',
            message: 'Khi giảng viên xếp lịch, ca thi sẽ xuất hiện tại đây.',
          ),
        ] else if (!_loadingSessions && _visibleSessions.isEmpty) ...[
          const SizedBox(height: 36),
          const StudentStateMessage(
            icon: Icons.filter_alt_off_outlined,
            title: 'Không có ca thi phù hợp',
            message: 'Thử một bộ lọc khác để xem các ca được phân công.',
          ),
        ] else ...[
          for (final session in _visibleSessions) ...[
            _SessionCard(session: session, onTap: () => _openSession(session)),
            const SizedBox(height: 12),
          ],
        ],
      ],
    ),
  );

  Widget _practicePage() => const _UnsupportedPage(
    icon: Icons.menu_book_outlined,
    title: 'Luyện tập chưa khả dụng',
    message: 'Backend hiện chưa cung cấp API đề luyện tập độc lập. Các bài thi được phân công vẫn có thể mở từ mục Lịch thi.',
  );

  Widget _resultsPage() {
    if (_loadingResults) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_resultsError != null) {
      return StudentStateMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Không tải được kết quả',
        message: _resultsError!,
        isError: true,
        actionLabel: 'Thử lại',
        onAction: _loadResults,
      );
    }
    if (!_resultsLoaded) {
      return StudentStateMessage(
        icon: Icons.bar_chart_outlined,
        title: 'Đang tải kết quả',
        message: 'Đang đối chiếu các bài đã nộp từ lịch thi của bạn.',
        actionLabel: 'Tải kết quả',
        onAction: _loadResults,
      );
    }
    if (_results.isEmpty) {
      final hasSessions = _sessions.isNotEmpty;
      return StudentStateMessage(
        icon: Icons.bar_chart_outlined,
        title: hasSessions ? 'Chưa có bài thi đã nộp' : 'Chưa có lịch sử thi',
        message: hasSessions
            ? 'Chưa có bài đã nộp trong các ca được phân công.'
            : 'API lịch thi hiện trả về danh sách rỗng.',
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Kết quả của tôi',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        const Text(
          'Điểm chỉ xuất hiện sau khi được giảng viên công bố.',
          style: TextStyle(color: StudentColors.muted, height: 1.4),
        ),
        const SizedBox(height: 16),
        for (final result in _results) ...[
          _ResultCard(
            session: result['session'] as Map<String, dynamic>,
            data: result['data'] as Map<String, dynamic>,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _accountPage() {
    final profile = widget.api.profile;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Tài khoản',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        StudentSurface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 26,
                backgroundColor: StudentColors.surfaceHigh,
                child: Icon(
                  Icons.person_outline,
                  color: StudentColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Thông tin từ hệ thống',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 14),
              _KeyValueRow(
                label: 'Mã hồ sơ',
                value: profile?['personId']?.toString() ?? 'Không có dữ liệu',
              ),
              const Divider(height: 20),
              _KeyValueRow(
                label: 'Quyền quản lý TOEIC',
                value: profile?['canManage'] == true ? 'Có' : 'Không',
              ),
              const SizedBox(height: 12),
              const Text(
                'Backend hiện không trả về họ tên, email hoặc thông tin lớp trong API hồ sơ.',
                style: TextStyle(
                  color: StudentColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: StudentColors.red,
            side: const BorderSide(color: StudentColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.onTap});

  final Map<String, dynamic> session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final attemptStatus = session['attemptStatus'];
    final cancelled = session['status'] == 'Cancelled';
    final closed = session['status'] != 'Published' && !cancelled;
    final status = attemptStatus == 'Submitted'
        ? ('Đã nộp', StudentColors.green, StudentColors.greenSoft)
        : attemptStatus == 'InProgress'
        ? ('Đang làm', StudentColors.secondary, StudentColors.surfaceHigh)
        : cancelled
        ? ('Đã hủy', StudentColors.red, StudentColors.redSoft)
        : closed
        ? ('Đã khóa', StudentColors.muted, StudentColors.surfaceLow)
        : ('Được phân công', StudentColors.amber, StudentColors.amberSoft);
    return StudentSurface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  session['name']?.toString() ?? 'Ca thi TOEIC',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              StudentStatusPill(
                label: status.$1,
                color: status.$2,
                background: status.$3,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            session['title']?.toString() ?? 'TOEIC Reading',
            style: const TextStyle(color: StudentColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 13),
          _SessionMeta(
            icon: Icons.calendar_today_outlined,
            label: _date(session['startsAt'], weekday: true),
          ),
          const SizedBox(height: 7),
          _SessionMeta(
            icon: Icons.schedule_outlined,
            label:
                '${_shift(session['shift'])} · ${session['durationMinutes'] ?? 75} phút',
          ),
          const SizedBox(height: 7),
          _SessionMeta(
            icon: Icons.lock_clock_outlined,
            label: 'Hạn vào thi ${_date(session['entryClosesAt'])}',
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onTap,
              icon: Icon(
                attemptStatus == 'Submitted'
                    ? Icons.assessment_outlined
                    : Icons.arrow_forward,
                size: 18,
              ),
              label: Text(
                attemptStatus == 'Submitted'
                    ? 'Xem kết quả'
                    : attemptStatus == 'InProgress'
                    ? 'Tiếp tục bài thi'
                    : 'Chi tiết ca thi',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: StudentColors.surfaceHigh,
                foregroundColor: StudentColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionMeta extends StatelessWidget {
  const _SessionMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: StudentColors.secondary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: StudentColors.ink, fontSize: 12),
        ),
      ),
    ],
  );
}

class _SessionDetail extends StatefulWidget {
  const _SessionDetail({required this.session, required this.onOpen});

  final Map<String, dynamic> session;
  final Future<void> Function() onOpen;

  @override
  State<_SessionDetail> createState() => _SessionDetailState();
}

class _SessionDetailState extends State<_SessionDetail> {
  bool _busy = false;
  String? _message;

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.onOpen();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final submitted = session['attemptStatus'] == 'Submitted';
    final cancelled = session['status'] == 'Cancelled';
    final canOpen = submitted || session['status'] == 'Published';
    final title = session['title']?.toString() ?? 'TOEIC Reading';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết ca thi'),
        leading: IconButton(
          tooltip: 'Quay lại',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: StudentColors.primaryBright,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StudentStatusPill(
                  label: submitted
                      ? 'Đã nộp bài'
                      : cancelled
                      ? 'Ca thi đã hủy'
                      : session['attemptStatus'] == 'InProgress'
                      ? 'Đang làm bài'
                      : 'Ca thi được phân công',
                  color: Colors.white,
                  background: const Color(0x33FFFFFF),
                  icon: submitted ? Icons.task_alt : Icons.event_available,
                ),
                const SizedBox(height: 14),
                Text(
                  session['name']?.toString() ?? 'Ca thi TOEIC',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFFE4EAFF), height: 1.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroTag(label: 'Mã ca ${session['id']}'),
                    _HeroTag(label: _shift(session['shift'])),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _SectionTitle(
            icon: Icons.calendar_month_outlined,
            title: 'Thông tin lịch trình',
          ),
          const SizedBox(height: 8),
          StudentSurface(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _DetailRow(
                  icon: Icons.event_outlined,
                  label: 'Ngày diễn ra',
                  value: _date(session['startsAt'], weekday: true),
                ),
                const Divider(height: 20),
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  label: 'Giờ bắt đầu',
                  value: _date(session['startsAt']),
                ),
                const Divider(height: 20),
                _DetailRow(
                  icon: Icons.lock_clock_outlined,
                  label: 'Hạn vào thi',
                  value: _date(session['entryClosesAt']),
                ),
                const Divider(height: 20),
                _DetailRow(
                  icon: Icons.timer_outlined,
                  label: 'Thời lượng',
                  value: '${session['durationMinutes'] ?? 75} phút',
                ),
                const Divider(height: 20),
                _DetailRow(
                  icon: Icons.event_busy_outlined,
                  label: 'Đóng ca',
                  value: _date(session['endsAt']),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: StudentColors.amberSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: StudentColors.amber),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Thời gian làm bài không vượt quá giờ đóng ca. Hệ thống kiểm tra điều kiện vào thi theo giờ máy chủ.',
                    style: TextStyle(height: 1.45, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle(
            icon: Icons.format_list_numbered,
            title: 'Cấu trúc bài thi Reading',
          ),
          const SizedBox(height: 8),
          const _PartRow(
            part: 'Part 5',
            name: 'Incomplete Sentences',
            count: '30 câu',
          ),
          const SizedBox(height: 8),
          const _PartRow(
            part: 'Part 6',
            name: 'Text Completion',
            count: '16 câu',
          ),
          const SizedBox(height: 8),
          const _PartRow(
            part: 'Part 7',
            name: 'Reading Comprehension',
            count: '54 câu',
          ),
          const SizedBox(height: 14),
          const _SectionTitle(
            icon: Icons.rule_outlined,
            title: 'Hướng dẫn làm bài',
          ),
          const SizedBox(height: 8),
          const StudentSurface(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RuleLine('Có thể thay đổi hoặc bỏ chọn đáp án trước khi nộp.'),
                _RuleLine('Được phép nộp sớm, kể cả khi chưa chọn câu nào.'),
                _RuleLine('Khi hết giờ, bài thi được tự động nộp và khóa sửa.'),
                _RuleLine('Sau khi nộp, không thể chỉnh sửa câu trả lời.'),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            _InlineMessage(message: _message!, isError: true),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: FilledButton.icon(
            onPressed: _busy || !canOpen ? null : _open,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    submitted ? Icons.assessment_outlined : Icons.arrow_forward,
                  ),
            label: Text(
              _busy
                  ? 'Đang kết nối'
                  : submitted
                  ? 'Xem kết quả'
                  : session['attemptStatus'] == 'InProgress'
                  ? 'Tiếp tục làm bài'
                  : cancelled
                  ? 'Ca thi đã hủy'
                  : 'Bắt đầu làm bài',
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroTag extends StatelessWidget {
  const _HeroTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0x22FFFFFF),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: StudentColors.primary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    ],
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: StudentColors.secondary),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: StudentColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ],
  );
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.name, required this.count});

  final String part;
  final String name;
  final String count;

  @override
  Widget build(BuildContext context) => StudentSurface(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: StudentColors.surfaceLow,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            part.replaceFirst('Part ', 'P'),
            style: const TextStyle(
              color: StudentColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ),
        Text(
          count,
          style: const TextStyle(
            color: StudentColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _RuleLine extends StatelessWidget {
  const _RuleLine(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_outline,
          size: 17,
          color: StudentColors.green,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(height: 1.4, fontSize: 12)),
        ),
      ],
    ),
  );
}

class _AttemptScreen extends StatefulWidget {
  const _AttemptScreen({required this.api, required this.data});

  final ToeicApi api;
  final Map<String, dynamic> data;

  @override
  State<_AttemptScreen> createState() => _AttemptScreenState();
}

class _AttemptScreenState extends State<_AttemptScreen>
    with WidgetsBindingObserver {
  late Map<String, dynamic> _attempt;
  List<Map<String, dynamic>> _questions = [];
  final _elapsed = Stopwatch();
  Duration _initialRemaining = Duration.zero;
  Timer? _timer;
  int _index = 0;
  bool _busy = false;
  bool _uncertain = false;
  String? _message;
  DateTime? _nextAutoRetry;

  String get _id => _attempt['id'].toString();
  bool get _inProgress =>
      _attempt['status'] == 'InProgress' &&
      _attempt['sessionStatus'] == 'Published';
  Duration get _remaining => _initialRemaining - _elapsed.elapsed;
  bool get _expired => _remaining <= Duration.zero;
  bool get _canAnswer => _inProgress && !_busy && !_uncertain && !_expired;
  int get _answered =>
      _questions.where((question) => question['choiceId'] != null).length;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply(widget.data);
    if (_inProgress) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_inProgress) return;
        setState(() {});
        if (_expired &&
            !_busy &&
            (_nextAutoRetry == null ||
                DateTime.now().isAfter(_nextAutoRetry!))) {
          _submit(automatic: true);
        }
      });
    }
  }

  void _apply(Map<String, dynamic> data) {
    _attempt = _asMap(data['attempt']);
    _questions = (data['questions'] as List).map(_asMap).toList();
    final deadline = DateTime.parse(_attempt['deadlineAt'].toString());
    final serverNow = DateTime.parse(_attempt['serverNow'].toString());
    _initialRemaining = deadline.difference(serverNow);
    _elapsed.reset();
    if (_inProgress) {
      _elapsed.start();
    } else {
      _timer?.cancel();
    }
    if (_index >= _questions.length) _index = 0;
    _uncertain = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await widget.api.attempt(_id);
      if (mounted) setState(() => _apply(data));
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({int? choice, bool? marked}) async {
    if (!_canAnswer) return;
    final question = _questions[_index];
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final response = await widget.api.save(_id, {
        'leaseId': _attempt['activeLeaseId'],
        'questionId': question['id'],
        'choiceId': marked == null ? choice : question['choiceId'],
        'markedForReview': marked ?? question['markedForReview'],
        'revision': (question['revision'] as int) + 1,
      });
      if (mounted) {
        setState(() {
          question['choiceId'] = response['choiceId'];
          question['markedForReview'] = response['markedForReview'];
          question['revision'] = response['revision'];
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _message =
              'Chưa xác nhận lưu: ${_error(error)}\nTải lại bài để đối chiếu với máy chủ trước khi chọn tiếp.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit({bool automatic = false}) async {
    if (_busy) return;
    if (!automatic) {
      if (_uncertain) return;
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.assignment_turned_in_outlined),
          title: const Text('Nộp bài thi?'),
          content: Text(
            'Đã trả lời $_answered/${_questions.length} câu. Còn ${_questions.length - _answered} câu bỏ trống. Bạn vẫn có thể nộp; sau đó không thể sửa bài.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Làm tiếp'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Nộp bài'),
            ),
          ],
        ),
      );
      if (accepted != true || !mounted || _busy || !_inProgress) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await widget.api.submit(_id);
      if (mounted) setState(() => _apply(data));
    } catch (error) {
      if (mounted) {
        setState(() => _message = 'Chưa xác nhận nộp bài: ${_error(error)}');
      }
      _nextAutoRetry = DateTime.now().add(const Duration(seconds: 10));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _clock {
    final seconds = _remaining.inSeconds.clamp(0, 99999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _showQuestionPicker() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudentColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Danh sách câu hỏi',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text('${_questions.length} câu'),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: _questions.length,
                  itemBuilder: (context, index) {
                    final question = _questions[index];
                    final answered = question['choiceId'] != null;
                    final marked = question['markedForReview'] == true;
                    final isCurrent = index == _index;
                    return OutlinedButton(
                      onPressed: () => Navigator.pop(context, index),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: isCurrent
                            ? StudentColors.primaryBright
                            : marked
                            ? StudentColors.amberSoft
                            : answered
                            ? StudentColors.greenSoft
                            : Colors.white,
                        foregroundColor: isCurrent
                            ? Colors.white
                            : StudentColors.ink,
                        side: BorderSide(
                          color: isCurrent
                              ? StudentColors.primaryBright
                              : StudentColors.border,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                      ),
                      child: Text('${index + 1}'),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _index = selected);
  }

  @override
  Widget build(BuildContext context) {
    final submitted = _attempt['status'] == 'Submitted';
    final total = _questions.length;
    final selectedQuestion = total == 0 ? null : _questions[_index];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 62,
        leading: IconButton(
          tooltip: 'Quay lại lịch thi',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _attempt['title']?.toString() ?? 'TOEIC Reading',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            Text(
              submitted ? 'Bài thi đã nộp' : 'Bài thi đang diễn ra',
              style: const TextStyle(fontSize: 11, color: StudentColors.muted),
            ),
          ],
        ),
        actions: [
          if (_inProgress) ...[
            StudentStatusPill(
              label: _clock,
              color: _remaining.inMinutes < 5
                  ? StudentColors.red
                  : StudentColors.primary,
              background: _remaining.inMinutes < 5
                  ? StudentColors.redSoft
                  : StudentColors.surfaceHigh,
              icon: Icons.timer_outlined,
            ),
            const SizedBox(width: 8),
          ],
          if (_inProgress)
            IconButton(
              tooltip: 'Danh sách câu',
              onPressed: _showQuestionPicker,
              icon: const Icon(Icons.grid_view_rounded),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: submitted
          ? _submittedBody()
          : !_inProgress
          ? const StudentStateMessage(
              icon: Icons.lock_outline,
              title: 'Bài thi đã bị khóa',
              message: 'Ca thi hoặc bài làm không còn cho phép chỉnh sửa.',
            )
          : total == 0
          ? const StudentStateMessage(
              icon: Icons.error_outline,
              title: 'Không tải được câu hỏi',
              message: 'API bài thi không trả về câu hỏi nào.',
            )
          : _workingBody(selectedQuestion!, total),
      bottomNavigationBar: submitted || !_inProgress || total == 0
          ? null
          : _attemptActions(total),
    );
  }

  Widget _workingBody(Map<String, dynamic> question, int total) => Column(
    children: [
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: ListView(
          key: const PageStorageKey('exam-question-content'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: StudentColors.primaryBright,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'PART ${question['partNo']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _partName(question['partNo']),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  '$_answered/$total',
                  style: const TextStyle(
                    color: StudentColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _answered / total,
                minHeight: 5,
                backgroundColor: StudentColors.surfaceHigh,
                color: StudentColors.secondary,
              ),
            ),
            const SizedBox(height: 13),
            StudentSurface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Câu ${question['originalNumber']} / 200',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    '${_index + 1}/$total',
                    style: const TextStyle(color: StudentColors.muted),
                  ),
                  const SizedBox(width: 9),
                  Icon(
                    question['markedForReview'] == true
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: question['markedForReview'] == true
                        ? StudentColors.amber
                        : StudentColors.muted,
                    size: 18,
                  ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              _InlineMessage(message: _message!, isError: true),
            ],
            const SizedBox(height: 13),
            StudentSurface(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if ((question['passages'] as List).isNotEmpty) ...[
                    for (final passage in question['passages'] as List) ...[
                      StudentRichContent(
                        content: passage.toString(),
                        style: const TextStyle(height: 1.65, fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                  StudentRichContent(
                    content: question['stem']?.toString() ?? '',
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final rawChoice in question['choices'] as List) ...[
              _ChoiceTile(
                choice: _asMap(rawChoice),
                selected: question['choiceId'] == _asMap(rawChoice)['choiceId'],
                enabled: _canAnswer,
                onTap: () =>
                    _save(choice: _asMap(rawChoice)['choiceId'] as int),
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                TextButton.icon(
                  onPressed: _canAnswer && question['choiceId'] != null
                      ? () => _save()
                      : null,
                  icon: const Icon(Icons.backspace_outlined, size: 17),
                  label: const Text('Bỏ chọn'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _canAnswer
                      ? () => _save(marked: question['markedForReview'] != true)
                      : null,
                  icon: Icon(
                    question['markedForReview'] == true
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 17,
                  ),
                  label: Text(
                    question['markedForReview'] == true
                        ? 'Đã đánh dấu'
                        : 'Đánh dấu',
                  ),
                ),
              ],
            ),
            Text(
              _busy
                  ? 'Đang lưu câu trả lời…'
                  : _uncertain
                  ? 'Chưa xác nhận lưu · cần tải lại'
                  : question['choiceId'] == null
                  ? 'Chưa chọn đáp án'
                  : 'Đã lưu trên máy chủ',
              textAlign: TextAlign.center,
              style: const TextStyle(color: StudentColors.muted, fontSize: 11),
            ),
            if (_expired) ...[
              const SizedBox(height: 12),
              const _InlineMessage(
                message: 'Đã hết giờ. Hệ thống đang xác nhận nộp bài với máy chủ; không thể đổi đáp án.',
                isError: true,
              ),
            ],
          ],
        ),
      ),
    ],
  );

  Widget _attemptActions(int total) => SafeArea(
    top: false,
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudentColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _index == 0 || _busy
                  ? null
                  : () => setState(() => _index--),
              icon: const Icon(Icons.chevron_left, size: 18),
              label: const Text('Trước'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _busy || _uncertain || _expired
                  ? null
                  : () => _submit(),
              icon: const Icon(Icons.assignment_turned_in_outlined, size: 17),
              label: const Text('Nộp bài'),
              style: OutlinedButton.styleFrom(
                foregroundColor: StudentColors.red,
                side: const BorderSide(color: Color(0xFFE8B4AF)),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: FilledButton.icon(
              onPressed: _index >= total - 1 || _busy
                  ? null
                  : () => setState(() => _index++),
              icon: const Icon(Icons.chevron_right, size: 18),
              label: const Text('Tiếp'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _submittedBody() {
    final correct = _attempt['correctCount'];
    final released = correct != null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 22),
        const Icon(Icons.task_alt, size: 64, color: StudentColors.green),
        const SizedBox(height: 12),
        const Text(
          'Bài thi đã được nộp',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          _attempt['title']?.toString() ?? 'TOEIC Reading',
          textAlign: TextAlign.center,
          style: const TextStyle(color: StudentColors.muted),
        ),
        const SizedBox(height: 24),
        if (!released)
          StudentSurface(
            child: Column(
              children: [
                const Icon(
                  Icons.hourglass_top_rounded,
                  color: StudentColors.secondary,
                  size: 32,
                ),
                const SizedBox(height: 9),
                const Text(
                  'Điểm chưa được công bố',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  'Thời gian dự kiến: ${_date(_attempt['scoreReleaseAt'])}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: StudentColors.muted),
                ),
              ],
            ),
          )
        else
          StudentSurface(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(
                  '$correct/100',
                  style: const TextStyle(
                    fontSize: 38,
                    color: StudentColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đúng: $correct  ·  Sai: ${_attempt['wrongCount']}  ·  Bỏ trống: ${_attempt['skippedCount']}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Số câu đúng Reading, chưa quy đổi sang thang điểm TOEIC.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: StudentColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        if (_message != null) ...[
          const SizedBox(height: 12),
          _InlineMessage(message: _message!, isError: true),
        ],
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Tải lại kết quả'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Về chi tiết ca thi'),
        ),
      ],
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.choice,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final Map<String, dynamic> choice;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? StudentColors.surfaceHigh : Colors.white,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? StudentColors.secondary : StudentColors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 29,
              height: 29,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? StudentColors.primaryBright
                    : StudentColors.surfaceLow,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                choice['displayLabel']?.toString() ?? '',
                style: TextStyle(
                  color: selected ? Colors.white : StudentColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: StudentRichContent(
                content: choice['content']?.toString() ?? '',
                style: const TextStyle(height: 1.4, fontSize: 14),
                selectable: false,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 19,
              color: selected
                  ? StudentColors.primaryBright
                  : StudentColors.border,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.session, required this.data});

  final Map<String, dynamic> session;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final attempt = _asMap(data['attempt']);
    final published = attempt['correctCount'] != null;
    return StudentSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session['name']?.toString() ?? 'Ca thi TOEIC',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            session['title']?.toString() ?? 'TOEIC Reading',
            style: const TextStyle(color: StudentColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (!published)
            const StudentStatusPill(
              label: 'Chưa công bố',
              color: StudentColors.amber,
              background: StudentColors.amberSoft,
              icon: Icons.hourglass_top,
            )
          else ...[
            Text(
              '${attempt['correctCount']}/100 câu đúng',
              style: const TextStyle(
                color: StudentColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Sai ${attempt['wrongCount']}  ·  Bỏ trống ${attempt['skippedCount']}',
              style: const TextStyle(color: StudentColors.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(color: StudentColors.muted, fontSize: 13),
        ),
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
    ],
  );
}

class _UnsupportedPage extends StatelessWidget {
  const _UnsupportedPage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: StudentStateMessage(icon: icon, title: title, message: message),
    ),
  );
}

class StudentStateMessage extends StatelessWidget {
  const StudentStateMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 42,
            color: isError ? StudentColors.red : StudentColors.secondary,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: StudentColors.muted,
              height: 1.45,
              fontSize: 13,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh, size: 17),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
    ),
  );
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isError ? StudentColors.redSoft : StudentColors.surfaceLow,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.info_outline,
          color: isError ? StudentColors.red : StudentColors.secondary,
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: isError ? StudentColors.red : StudentColors.ink,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
}

String _partName(dynamic part) => switch (part) {
  5 => 'Incomplete Sentences',
  6 => 'Text Completion',
  7 => 'Reading Comprehension',
  _ => 'TOEIC Reading',
};
