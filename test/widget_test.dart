// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:kiemtragk/classroom_app.dart';
import 'package:kiemtragk/toeic/student_mobile_app.dart';
import 'package:kiemtragk/toeic/toeic_api.dart';

void main() {
  testWidgets('teacher can open the exam management page on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ToeicClassroomApp());
    await tester.tap(find.text('Vào hệ thống'));
    await tester.pumpAndSettle();

    expect(find.text('Xin chào, Nguyễn Văn An!'), findsOneWidget);
    await tester.tap(find.text('Đề thi TOEIC'));
    await tester.pumpAndSettle();
    expect(find.text('Quản lý đề thi'), findsOneWidget);
  });

  testWidgets('student can enter the student dashboard', (tester) async {
    await tester.pumpWidget(const ToeicClassroomApp());

    expect(find.text('Đăng nhập'), findsOneWidget);
    await tester.tap(find.text('Sinh viên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vào hệ thống'));
    await tester.pumpAndSettle();

    expect(find.text('Chào Minh Anh!'), findsOneWidget);
    expect(find.text('Bài thi nên làm tiếp'), findsOneWidget);
  });

  testWidgets('student app stays mobile-width and resizes for keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ToeicStudentApp());
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('student-app-viewport'))).width,
      430,
    );

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const ValueKey('student-app-viewport'))).width,
      390,
    );

    await tester.tap(find.byType(TextField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('student rich content keeps image between text fragments', (
    tester,
  ) async {
    const pixel =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+nS8sAAAAASUVORK5CYII=';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StudentRichContent(
            content:
                'Before [[TOEIC_IMAGE:data:image/png;base64,$pixel]] after',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Before '), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text(' after'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student can submit an incomplete mock exam and view results', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final serverNow = DateTime.now().toUtc();
    final deadline = serverNow.add(const Duration(minutes: 75));
    var savedAnswers = 0;
    final questions = List.generate(100, (index) {
      final number = index + 101;
      final part = number <= 130
          ? 5
          : number <= 146
          ? 6
          : 7;
      return {
        'id': number,
        'blockId': number,
        'partNo': part,
        'originalNumber': number,
        'stem': 'Mock stem $number',
        'choiceId': null,
        'markedForReview': false,
        'revision': 0,
        'passages': <String>[],
        'choices': [
          for (final label in ['A', 'B', 'C', 'D'])
            {
              'choiceId': number * 10 + label.codeUnitAt(0),
              'displayLabel': label,
              'content': 'Option $number $label',
            },
        ],
      };
    });
    final api = ToeicApi(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/Authenticate')) {
          return http.Response(
            jsonEncode({
              '__abp': true,
              'success': true,
              'result': {'accessToken': 'mock-token'},
            }),
            200,
          );
        }
        if (path == '/api/toeic/me') {
          expect(request.headers['Authorization'], 'Bearer mock-token');
          return http.Response('{"personId":7,"canManage":false}', 200);
        }
        if (path == '/api/toeic/sessions') {
          return http.Response(
            jsonEncode([
              {
                'id': 12,
                'name': 'Ca thi mock',
                'title': 'TOEIC Reading Mock',
                'shift': 'Morning',
                'startsAt': serverNow.toIso8601String(),
                'entryClosesAt': serverNow
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
                'endsAt': deadline.toIso8601String(),
                'status': 'Published',
                'durationMinutes': 75,
                'attemptId': null,
                'attemptStatus': null,
              },
            ]),
            200,
          );
        }
        if (path.endsWith('/sessions/12/start')) {
          return http.Response(
            jsonEncode({
              'attempt': {
                'id': 'mock-attempt',
                'sessionId': 12,
                'status': 'InProgress',
                'activeLeaseId': 'mock-lease',
                'deadlineAt': deadline.toIso8601String(),
                'serverNow': serverNow.toIso8601String(),
                'sessionStatus': 'Published',
                'scoreReleaseAt': deadline.toIso8601String(),
                'name': 'Ca thi mock',
                'title': 'TOEIC Reading Mock',
              },
              'questions': questions,
            }),
            200,
          );
        }
        if (path.endsWith('/answers')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['leaseId'], 'mock-lease');
          expect(body['choiceId'], isNotNull);
          savedAnswers++;
          return http.Response(
            jsonEncode({
              'choiceId': body['choiceId'],
              'markedForReview': body['markedForReview'],
              'revision': body['revision'],
            }),
            200,
          );
        }
        if (path.endsWith('/submit')) {
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), isEmpty);
          return http.Response(
            jsonEncode({
              'attempt': {
                'id': 'mock-attempt',
                'sessionId': 12,
                'status': 'Submitted',
                'deadlineAt': deadline.toIso8601String(),
                'serverNow': DateTime.now().toUtc().toIso8601String(),
                'sessionStatus': 'Published',
                'scoreReleaseAt': serverNow.toIso8601String(),
                'correctCount': 2,
                'wrongCount': 0,
                'skippedCount': 98,
                'name': 'Ca thi mock',
                'title': 'TOEIC Reading Mock',
              },
              'questions': [],
            }),
            200,
          );
        }
        throw StateError('Unexpected mock request: $path');
      }),
    );
    addTearDown(api.dispose);

    await tester.pumpWidget(ToeicStudentApp(api: api));
    await tester.enterText(find.byType(TextField).first, 'sv-mock');
    await tester.enterText(find.byType(TextField).last, 'mock-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pumpAndSettle();

    expect(find.text('Ca thi mock'), findsOneWidget);
    await tester.tap(find.text('Chi tiết ca thi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu làm bài'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Danh sách câu'));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(BottomSheet).last).width,
      lessThanOrEqualTo(430),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '1').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Option 101 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Tiếp'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Option 102 A'));
    await tester.pumpAndSettle();
    expect(savedAnswers, 2);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Nộp bài'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Đã trả lời 2/100 câu. Còn 98 câu bỏ trống.'),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byType(AlertDialog)).width,
      lessThanOrEqualTo(430),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Nộp bài'));
    await tester.pumpAndSettle();

    expect(find.text('Bài thi đã được nộp'), findsOneWidget);
    expect(find.textContaining('Đúng: 2'), findsOneWidget);
  });
}
