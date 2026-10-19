import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kiemtragk/toeic/toeic_api.dart';

void main() {
  test(
    'login unwraps ABP token and authenticates subsequent requests',
    () async {
      var sawBearer = false;
      final api = ToeicApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('Authenticate')) {
            expect(jsonDecode(request.body)['userNameOrEmailAddress'], 'sv01');
            return http.Response(
              jsonEncode({
                '__abp': true,
                'success': true,
                'result': {'accessToken': 'test-token'},
              }),
              200,
            );
          }
          sawBearer = request.headers['Authorization'] == 'Bearer test-token';
          return http.Response('{"canManage":false}', 200);
        }),
      );
      await api.login(' sv01 ', 'password');
      expect(sawBearer, isTrue);
      expect(api.profile?['canManage'], isFalse);
      api.dispose();
    },
  );
  test('failed save is surfaced instead of reported as saved', () async {
    final api = ToeicApi(
      client: MockClient(
        (_) async => http.Response('{"message":"Bai da khoa"}', 400),
      ),
    );
    await expectLater(
      api.save('a', {'revision': 1}),
      throwsA(isA<Exception>()),
    );
    api.dispose();
  });
  test('submit permits zero answers and sends no local score', () async {
    final api = ToeicApi(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), isEmpty);
        return http.Response(
          '{"attempt":{"status":"Submitted","correctCount":0,"wrongCount":0,"skippedCount":100},"questions":[]}',
          200,
        );
      }),
    );
    final result = await api.submit('attempt-id');
    expect(result['attempt']['skippedCount'], 100);
    api.dispose();
  });
}
