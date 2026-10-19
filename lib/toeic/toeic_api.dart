import 'dart:convert';
import 'session_storage_stub.dart'
    if (dart.library.js_interop) 'session_storage_web.dart' as session;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class ToeicApi {
  ToeicApi({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  static const _configuredBaseUrl = String.fromEnvironment('API_BASE_URL');
  static final String baseUrl = _configuredBaseUrl.isNotEmpty
      ? _configuredBaseUrl
      : kIsWeb
      ? 'https://localhost:44311'
      : 'http://10.0.2.2:5000';
  String? _token;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile =>
      _profile == null ? null : Map.of(_profile!);
  // TOEIC_SESSION_RESTORE_V1
  String get _sessionKey => 'toeic.student.session.v1:$baseUrl';
  Future<bool> restoreSession() async {
    final saved = session.readSession(_sessionKey);
    if (saved == null || saved.isEmpty) return false;
    _token = saved;
    _profile = Map<String, dynamic>.from(await request('/api/toeic/me') as Map);
    return true;
  }

  void logout() {
    session.clearSession(_sessionKey);
    _token = null;
    _profile = null;
  }

  void dispose() => _client.close();

  Future<dynamic> request(String path, {Object? body}) async {
    final url = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };
    final response =
        await (body == null
                ? _client.get(url, headers: headers)
                : _client.post(url, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401) {
      logout();
      throw Exception('Phiên đăng nhập hết hạn. Vui lòng đăng nhập lại.');
    }
    dynamic value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'Server không trả JSON (HTTP ${response.statusCode}). Kiểm tra API_BASE_URL và backend.',
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (value is Map && value['success'] == false)) {
      final message = value is Map
          ? value['message'] ??
                (value['error'] is Map ? value['error']['message'] : null)
          : null;
      throw Exception(
        message ??
            (response.statusCode == 401
                ? 'Phiên đăng nhập hết hạn. Quay về đăng nhập rồi mở lại ca thi.'
                : 'Yêu cầu thất bại (HTTP ${response.statusCode}).'),
      );
    }
    if (value is Map && value['__abp'] == true) return value['result'];
    return value;
  }

  Future<void> login(String username, String password) async {
    _token = null;
    _profile = null;
    final result = await request(
      '/api/TokenAuth/Authenticate',
      body: {
        'userNameOrEmailAddress': username.trim(),
        'password': password,
        'rememberClient': false,
      },
    );
    _token = result['accessToken'] as String;
    try {
      _profile = Map<String, dynamic>.from(
        await request('/api/toeic/me') as Map,
      );
      session.writeSession(_sessionKey, _token!);
    } catch (_) {
      _token = null;
      _profile = null;
      rethrow;
    }
  }

  Future<List<dynamic>> sessions() async =>
      List<dynamic>.from(await request('/api/toeic/sessions'));
  Future<Map<String, dynamic>> start(int id) async => Map<String, dynamic>.from(
    await request('/api/toeic/sessions/$id/start', body: {}),
  );
  Future<Map<String, dynamic>> attempt(String id) async =>
      Map<String, dynamic>.from(await request('/api/toeic/attempts/$id'));
  Future<Map<String, dynamic>> save(
    String id,
    Map<String, dynamic> body,
  ) async => Map<String, dynamic>.from(
    await request('/api/toeic/attempts/$id/answers', body: body),
  );
  Future<Map<String, dynamic>> submit(String id) async =>
      Map<String, dynamic>.from(
        await request('/api/toeic/attempts/$id/submit', body: {}),
      );
}
