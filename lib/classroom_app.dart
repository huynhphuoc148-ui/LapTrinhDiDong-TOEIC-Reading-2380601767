import 'package:flutter/material.dart';

const _blue = Color(0xFF155EEF);
const _ink = Color(0xFF172B4D);
const _muted = Color(0xFF667085);
const _background = Color(0xFFF5F7FC);
const _line = Color(0xFFE4E9F2);
const _teal = Color(0xFF078779);
const _amber = Color(0xFFB86112);

enum _Role { teacher, student }

extension on _Role {
  String get label => this == _Role.teacher ? 'Giảng viên' : 'Sinh viên';
}

class ToeicClassroomApp extends StatelessWidget {
  const ToeicClassroomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TOEIC Classroom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: _background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _blue,
          surface: _background,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _blue, width: 1.5),
          ),
        ),
      ),
      home: const _AccessScreen(),
    );
  }
}

class _AccessScreen extends StatefulWidget {
  const _AccessScreen();

  @override
  State<_AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<_AccessScreen> {
  _Role _role = _Role.teacher;

  void _enter() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => _Dashboard(role: _role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1000;
            if (!isWide) {
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _brandPanel(compact: true),
                  const SizedBox(height: 22),
                  _loginForm(),
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 5, child: _brandPanel(compact: false)),
                Expanded(
                  flex: 6,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Padding(
                        padding: const EdgeInsets.all(44),
                        child: _loginForm(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _brandPanel({required bool compact}) {
    return Container(
      padding: EdgeInsets.all(compact ? 20 : 56),
      decoration: BoxDecoration(
        color: const Color(0xFF1048B8),
        borderRadius: BorderRadius.circular(compact ? 12 : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: compact
            ? MainAxisAlignment.start
            : MainAxisAlignment.center,
        children: [
          const Row(
            children: [
              Icon(Icons.school_rounded, color: Colors.white, size: 30),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOEIC CLASSROOM',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  Text(
                    'ACADEMIC ASSESSMENT SYSTEM',
                    style: TextStyle(color: Color(0xFFDCE7FF), fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: compact ? 18 : 42),
          Text(
            compact
                ? 'Luyện thi TOEIC,\nđúng trọng tâm.'
                : 'Dạy tốt hơn.\nHọc tự tin hơn.',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 26 : 38,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!compact) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 390,
              child: Text(
                'Không gian học và đánh giá TOEIC dành cho giảng viên và sinh viên.',
                style: TextStyle(
                  color: Color(0xFFDCE7FF),
                  fontSize: 15,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 38),
            Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(24),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white.withAlpha(40)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_user_outlined, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bảo mật dữ liệu học tập\nBài thi và kết quả được tổ chức tập trung.',
                      style: TextStyle(
                        color: Colors.white,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Đăng nhập',
          style: TextStyle(
            color: _ink,
            fontSize: 25,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chọn tài khoản để tiếp tục vào hệ thống.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        SegmentedButton<_Role>(
          segments: const [
            ButtonSegment(
              value: _Role.teacher,
              label: Text('Giảng viên'),
              icon: Icon(Icons.co_present_outlined),
            ),
            ButtonSegment(
              value: _Role.student,
              label: Text('Sinh viên'),
              icon: Icon(Icons.school_outlined),
            ),
          ],
          selected: {_role},
          onSelectionChanged: (selection) =>
              setState(() => _role = selection.first),
        ),
        const SizedBox(height: 20),
        const _FieldLabel('Email hoặc mã tài khoản'),
        const SizedBox(height: 7),
        const TextField(
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'name@toeicclassroom.edu.vn',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
        const SizedBox(height: 16),
        const _FieldLabel('Mật khẩu'),
        const SizedBox(height: 7),
        const TextField(
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Nhập mật khẩu',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _message(
              context,
              'Vui lòng liên hệ quản trị viên để đặt lại mật khẩu.',
            ),
            child: const Text('Quên mật khẩu?'),
          ),
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _enter,
          icon: const Icon(Icons.login_rounded),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Text('Vào hệ thống'),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: _blue,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Bản giao diện minh họa · Chưa kết nối xác thực',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Dashboard extends StatefulWidget {
  const _Dashboard({required this.role});

  final _Role role;

  @override
  State<_Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<_Dashboard> {
  late _Role _role = widget.role;
  int _tab = 0;
  final _exams = <_ExamData>[
    _ExamData(
      'TOEIC 2025 - Test 01',
      'Reading & Listening',
      100,
      'Đang mở',
      true,
    ),
    _ExamData(
      'TOEIC 2025 - Test 02',
      'Reading & Listening',
      100,
      'Sắp diễn ra',
      false,
    ),
    _ExamData(
      'Economy TOEIC Vol. 5 - Test 03',
      'Reading',
      50,
      'Bản nháp',
      false,
    ),
    _ExamData('Mock Test Reading - Test 08', 'Reading', 50, 'Đang mở', true),
  ];

  List<String> get _tabs => _role == _Role.teacher
      ? ['Tổng quan', 'Đề thi TOEIC', 'Kết quả học tập']
      : ['Tổng quan', 'Bài thi', 'Kết quả của tôi'];

  void _switchRole(_Role role) => setState(() {
    _role = role;
    _tab = 0;
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.school_rounded, color: _blue),
            SizedBox(width: 9),
            Text(
              'TOEIC Classroom',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ],
        ),
        actions: [
          if (wide)
            Center(
              child: _Badge(label: _role.label, color: _blue),
            ),
          PopupMenuButton<_Role>(
            tooltip: 'Chuyển vai trò',
            icon: const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFEAF0FF),
              child: Icon(Icons.person_outline, size: 19, color: _blue),
            ),
            onSelected: _switchRole,
            itemBuilder: (context) => [
              for (final role in _Role.values)
                PopupMenuItem(
                  value: role,
                  child: Text('Dùng giao diện ${role.label.toLowerCase()}'),
                ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: wide
          ? Row(
              children: [
                _Sidebar(
                  role: _role,
                  tabs: _tabs,
                  selected: _tab,
                  onSelect: (index) => setState(() => _tab = index),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 17,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(bottom: BorderSide(color: _line)),
                        ),
                        child: Text(
                          'Bảng điều khiển ${_role.label.toLowerCase()}',
                          style: const TextStyle(color: _muted, fontSize: 13),
                        ),
                      ),
                      Expanded(child: _content()),
                    ],
                  ),
                ),
              ],
            )
          : _content(),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: [
                for (var index = 0; index < _tabs.length; index++)
                  NavigationDestination(
                    icon: Icon(_tabIcon(index)),
                    selectedIcon: Icon(_tabIcon(index, selected: true)),
                    label: _tabs[index],
                  ),
              ],
            ),
    );
  }

  IconData _tabIcon(int index, {bool selected = false}) {
    if (index == 0)
      return selected ? Icons.dashboard_rounded : Icons.dashboard_outlined;
    if (index == 1)
      return selected ? Icons.assignment_rounded : Icons.assignment_outlined;
    return selected ? Icons.insights_rounded : Icons.insights_outlined;
  }

  Widget _content() => _tab == 0
      ? _overview()
      : _tab == 1
      ? _examList()
      : _results();

  Widget _overview() {
    final teacher = _role == _Role.teacher;
    return _PageScroll(
      children: [
        _PageHeading(
          eyebrow: teacher ? 'KHÔNG GIAN GIẢNG VIÊN' : 'KHÔNG GIAN SINH VIÊN',
          title: teacher ? 'Xin chào, Nguyễn Văn An!' : 'Chào Minh Anh!',
          subtitle: teacher
              ? 'Tình hình học tập và các bài thi gần đây của lớp.'
              : 'Sẵn sàng cho mục tiêu TOEIC tiếp theo của bạn chưa?',
          action: teacher
              ? FilledButton.icon(
                  onPressed: _createExam,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tạo đề thi'),
                )
              : OutlinedButton.icon(
                  onPressed: () => setState(() => _tab = 1),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Tìm bài thi'),
                ),
        ),
        const SizedBox(height: 20),
        _MetricGrid(
          items: teacher
              ? const [
                  _MetricData(
                    'Đề thi đã tạo',
                    '24',
                    '+3 tháng này',
                    Icons.description_outlined,
                    _blue,
                  ),
                  _MetricData(
                    'Bài đang mở',
                    '03',
                    '2 sắp kết thúc',
                    Icons.timer_outlined,
                    _teal,
                  ),
                  _MetricData(
                    'Lượt dự thi',
                    '186',
                    'Trong tháng này',
                    Icons.people_outline,
                    _amber,
                  ),
                  _MetricData(
                    'Điểm trung bình',
                    '68.5%',
                    '+4.2% kỳ trước',
                    Icons.trending_up,
                    Color(0xFFB54745),
                  ),
                ]
              : const [
                  _MetricData(
                    'Bài đã hoàn thành',
                    '18',
                    '+4 trong tháng này',
                    Icons.task_alt,
                    _blue,
                  ),
                  _MetricData(
                    'Điểm trung bình',
                    '785',
                    '+35 điểm gần đây',
                    Icons.trending_up,
                    _teal,
                  ),
                  _MetricData(
                    'Thời gian học',
                    '26 giờ',
                    'Trong tháng này',
                    Icons.schedule,
                    _amber,
                  ),
                  _MetricData(
                    'Mục tiêu TOEIC',
                    '850',
                    'Còn 65 điểm',
                    Icons.flag_outlined,
                    Color(0xFFB54745),
                  ),
                ],
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final primary = teacher ? _recentExams() : _studentNext();
            final secondary = teacher ? _activity() : _studentProgress();
            if (constraints.maxWidth < 900)
              return Column(
                children: [primary, const SizedBox(height: 16), secondary],
              );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: primary),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: secondary),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _recentExams() => _Panel(
    title: 'Danh sách đề thi hôm nay',
    action: TextButton(
      onPressed: () => setState(() => _tab = 1),
      child: const Text('Xem tất cả'),
    ),
    child: Column(
      children: [
        for (final exam in _exams.take(3))
          _ExamRow(
            exam: exam,
            trailing: Text(
              '${exam.questions} câu',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
      ],
    ),
  );

  Widget _activity() => const _Panel(
    title: 'Hoạt động gần đây',
    child: Column(
      children: [
        _Activity(
          icon: Icons.person_add_alt_1,
          color: _blue,
          title: '12 sinh viên đã tham gia',
          detail: 'Lớp TOEIC Reading · 20 phút trước',
        ),
        _Activity(
          icon: Icons.assignment_turned_in_outlined,
          color: _teal,
          title: 'Bài thi vừa được hoàn thành',
          detail: 'TOEIC 2025 - Test 01 · 1 giờ trước',
        ),
        _Activity(
          icon: Icons.edit_note,
          color: _amber,
          title: 'Đã cập nhật đề thi',
          detail: 'Mock Test Reading · Hôm nay, 09:15',
        ),
      ],
    ),
  );

  Widget _studentNext() => _Panel(
    title: 'Bài thi nên làm tiếp',
    action: TextButton(
      onPressed: () => setState(() => _tab = 1),
      child: const Text('Tất cả bài thi'),
    ),
    child: Column(
      children: [
        _StudentExam(
          title: 'TOEIC 2025 - Test 01',
          detail: 'Reading & Listening · 100 câu',
          badge: 'Còn 2 ngày',
          onStart: () => _startExam('TOEIC 2025 - Test 01'),
        ),
        _StudentExam(
          title: 'Luyện nghe Part 3',
          detail: 'Listening · 13 câu',
          badge: 'Luyện tập',
          onStart: () => _startExam('Luyện nghe Part 3'),
        ),
      ],
    ),
  );

  Widget _studentProgress() => _Panel(
    title: 'Tiến độ mục tiêu',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '785',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 6, bottom: 5),
              child: Text('/ 850 điểm', style: TextStyle(color: _muted)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: const LinearProgressIndicator(
            value: 0.82,
            minHeight: 9,
            color: _teal,
            backgroundColor: Color(0xFFEAF0FA),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Bạn đã đạt 82% mục tiêu điểm số.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 20),
        const _Skill(label: 'Listening', value: 0.78, color: _blue),
        const SizedBox(height: 13),
        const _Skill(label: 'Reading', value: 0.86, color: _teal),
      ],
    ),
  );

  Widget _examList() {
    final teacher = _role == _Role.teacher;
    return _PageScroll(
      children: [
        _PageHeading(
          eyebrow: teacher ? 'NGÂN HÀNG ĐỀ THI TOEIC' : 'KHO BÀI LUYỆN TẬP',
          title: teacher ? 'Quản lý đề thi' : 'Bài thi dành cho bạn',
          subtitle: teacher
              ? 'Theo dõi trạng thái và số lượt dự thi.'
              : 'Chọn bài phù hợp với kế hoạch ôn tập.',
          action: teacher
              ? FilledButton.icon(
                  onPressed: _createExam,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tạo đề thi'),
                )
              : null,
        ),
        const SizedBox(height: 16),
        if (teacher)
          _Panel(
            title: '${_exams.length} đề thi',
            child: Column(
              children: [
                for (final exam in _exams)
                  InkWell(
                    onTap: () => _examDetails(exam),
                    child: _ExamRow(
                      exam: exam,
                      trailing: _StatusBadge(label: exam.status),
                    ),
                  ),
              ],
            ),
          )
        else ...[
          for (final exam in _exams.where((exam) => exam.available))
            _StudentExam(
              title: exam.title,
              detail: '${exam.category} · ${exam.questions} câu · 90 phút',
              badge: 'Đang mở',
              onStart: () => _startExam(exam.title),
            ),
          const SizedBox(height: 10),
          const _SectionCaption('GỢI Ý LUYỆN TẬP'),
          const SizedBox(height: 8),
          _StudentExam(
            title: 'Luyện nghe Part 3',
            detail: 'Listening · 13 câu · Khoảng 15 phút',
            badge: 'Luyện tập',
            onStart: () => _startExam('Luyện nghe Part 3'),
          ),
        ],
      ],
    );
  }

  Widget _results() {
    final teacher = _role == _Role.teacher;
    final records = teacher
        ? const [
            ('TOEIC 2025 - Test 01', 'Lớp Reading 02', '42 sinh viên', '68.5%'),
            (
              'Mock Test Reading - Test 08',
              'Lớp TOEIC 450+',
              '28 sinh viên',
              '74.2%',
            ),
            ('TOEIC 2024 - Test 03', 'Lớp Reading 01', '36 sinh viên', '71.8%'),
          ]
        : const [
            (
              'TOEIC 2025 - Test 01',
              'Hoàn thành · 12/10/2026',
              '100 câu',
              '785',
            ),
            (
              'Mock Test Reading - Test 08',
              'Hoàn thành · 08/10/2026',
              '50 câu',
              '810',
            ),
            (
              'TOEIC 2024 - Test 03',
              'Hoàn thành · 01/10/2026',
              '100 câu',
              '760',
            ),
          ];
    return _PageScroll(
      children: [
        _PageHeading(
          eyebrow: 'BÁO CÁO HỌC TẬP',
          title: teacher ? 'Kết quả học tập' : 'Kết quả của tôi',
          subtitle: teacher
              ? 'Tổng hợp tình hình làm bài của các lớp.'
              : 'Theo dõi điểm số và quá trình luyện tập.',
        ),
        const SizedBox(height: 18),
        _Panel(
          title: teacher ? 'Kết quả các bài thi gần đây' : 'Lịch sử làm bài',
          child: Column(
            children: [
              for (final record in records)
                _ResultRow(
                  title: record.$1,
                  detail: record.$2,
                  count: record.$3,
                  score: record.$4,
                  scoreLabel: teacher ? 'Điểm TB' : 'Điểm',
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createExam() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo đề thi mới'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên đề thi',
            hintText: 'Ví dụ: TOEIC Practice Test 01',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Tạo đề'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;
    setState(
      () => _exams.insert(
        0,
        _ExamData(title, 'Reading & Listening', 100, 'Bản nháp', false),
      ),
    );
    _message(context, 'Đã thêm "$title" vào danh sách đề thi mẫu.');
  }

  void _examDetails(_ExamData exam) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(exam.title),
      content: Text(
        '${exam.category}\n${exam.questions} câu hỏi · 90 phút\nTrạng thái: ${exam.status}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    ),
  );

  void _startExam(String title) => showDialog<void>(
    context: context,
    builder: (context) => _PracticeDialog(title: title),
  );
}

class _PracticeDialog extends StatefulWidget {
  const _PracticeDialog({required this.title});
  final String title;

  @override
  State<_PracticeDialog> createState() => _PracticeDialogState();
}

class _PracticeDialogState extends State<_PracticeDialog> {
  int? _answer;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Câu 1 / 100',
            style: TextStyle(color: _blue, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text('Please submit the report _____ Friday afternoon.'),
          for (var index = 0; index < 4; index++)
            RadioListTile<int>(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: index,
              groupValue: _answer,
              onChanged: (value) => setState(() => _answer = value),
              title: Text(
                ['(A) at', '(B) by', '(C) during', '(D) since'][index],
              ),
            ),
          const Text(
            'Bài làm minh họa · Tiến độ chưa được lưu',
            style: TextStyle(fontSize: 12, color: _muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Thoát'),
      ),
      FilledButton(
        onPressed: _answer == null
            ? null
            : () {
                Navigator.pop(context);
                _message(context, 'Đã ghi nhận câu trả lời mẫu.');
              },
        child: const Text('Trả lời'),
      ),
    ],
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.role,
    required this.tabs,
    required this.selected,
    required this.onSelect,
  });
  final _Role role;
  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    width: 232,
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(14, 20, 14, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionCaption('MENU'),
        const SizedBox(height: 10),
        for (var index = 0; index < tabs.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _NavItem(
              index: index,
              title: tabs[index],
              selected: selected == index,
              onTap: () => onSelect(index),
            ),
          ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 17,
                backgroundColor: Color(0xFFDCE7FF),
                child: Icon(Icons.person_outline, color: _blue, size: 19),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role == _Role.teacher ? 'Nguyễn Văn An' : 'Trần Minh Anh',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      role.label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.index,
    required this.title,
    required this.selected,
    required this.onTap,
  });
  final int index;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = index == 0
        ? Icons.dashboard_outlined
        : index == 1
        ? Icons.assignment_outlined
        : Icons.insights_outlined;
    return Material(
      color: selected ? const Color(0xFFEAF0FF) : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 19, color: selected ? _blue : _muted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? _blue : _ink,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width >= 850 ? 26 : 18,
      22,
      MediaQuery.sizeOf(context).width >= 850 ? 26 : 18,
      28,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.action,
  });
  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: _ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 13)),
        ],
      );
      if (action == null) return titleBlock;
      if (constraints.maxWidth < 520)
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), action!],
        );
      return Row(
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 12),
          action!,
        ],
      );
    },
  );
}

class _MetricData {
  const _MetricData(this.label, this.value, this.note, this.icon, this.color);
  final String label;
  final String value;
  final String note;
  final IconData icon;
  final Color color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_MetricData> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1000
          ? 4
          : constraints.maxWidth >= 560
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in items)
            SizedBox(
              width: width,
              child: _MetricCard(item: item),
            ),
        ],
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.item});
  final _MetricData item;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 116),
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ),
            Icon(item.icon, color: item.color, size: 19),
          ],
        ),
        const SizedBox(height: 9),
        Text(
          item.value,
          style: const TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.note,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _muted, fontSize: 11),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const Divider(height: 18, color: _line),
        child,
      ],
    ),
  );
}

class _ExamData {
  const _ExamData(
    this.title,
    this.category,
    this.questions,
    this.status,
    this.available,
  );
  final String title;
  final String category;
  final int questions;
  final String status;
  final bool available;
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({required this.exam, required this.trailing});
  final _ExamData exam;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0FF),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.description_outlined, size: 18, color: _blue),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exam.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _ink,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                exam.category,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        trailing,
      ],
    ),
  );
}

class _StudentExam extends StatelessWidget {
  const _StudentExam({
    required this.title,
    required this.detail,
    required this.badge,
    required this.onStart,
  });
  final String title;
  final String detail;
  final String badge;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _line),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF0FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.assignment_outlined, color: _blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 5),
              Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
              const SizedBox(height: 7),
              _StatusBadge(label: badge),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Bắt đầu bài thi',
          onPressed: onStart,
          icon: const Icon(Icons.play_arrow_rounded),
        ),
      ],
    ),
  );
}

class _Activity extends StatelessWidget {
  const _Activity({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 3),
              Text(detail, style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Skill extends StatelessWidget {
  const _Skill({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _ink, fontSize: 12),
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 6,
          color: color,
          backgroundColor: const Color(0xFFEAF0FA),
        ),
      ),
    ],
  );
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.title,
    required this.detail,
    required this.count,
    required this.score,
    required this.scoreLabel,
  });
  final String title;
  final String detail;
  final String count;
  final String score;
  final String scoreLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        const Icon(Icons.assignment_turned_in_outlined, color: _blue),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(detail, style: const TextStyle(fontSize: 11, color: _muted)),
            ],
          ),
        ),
        if (MediaQuery.sizeOf(context).width > 500)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              count,
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              score,
              style: const TextStyle(
                color: _blue,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            Text(
              scoreLabel,
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = label == 'Đang mở' || label == 'Luyện tập'
        ? _teal
        : label == 'Bản nháp'
        ? _amber
        : _blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(23),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF0FF),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _ink,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    ),
  );
}

class _SectionCaption extends StatelessWidget {
  const _SectionCaption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: _muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    ),
  );
}

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
}
