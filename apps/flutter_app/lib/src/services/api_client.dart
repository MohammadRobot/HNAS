import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:http/http.dart' as http;
import '../models.dart';

class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
  });

  final String code;
  final String message;
  final int? statusCode;

  @override
  String toString() {
    if (statusCode == null) {
      return '$code: $message';
    }
    return '$code ($statusCode): $message';
  }
}

class ApiClient {
  ApiClient({
    required FirebaseAuth auth,
    http.Client? httpClient,
    String? baseUrl,
  })  : _auth = auth,
        _httpClient = httpClient ?? http.Client(),
        _baseUrl = _resolveBaseUrl(baseUrl);

  final FirebaseAuth _auth;
  final http.Client _httpClient;
  final String _baseUrl;

  Future<Map<String, dynamic>> updateChecklistTask({
    required String patientId,
    required String date,
    required String taskId,
    required String status,
    Map<String, dynamic>? inputs,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId,
      'date': date,
      'taskId': taskId,
      'status': status,
      if (inputs != null && inputs.isNotEmpty) 'inputs': inputs,
    };
    return _post('/api/checklist/updateTask', body);
  }

  Future<AiAskResponseModel> askAi({
    required String patientId,
    required String question,
    String? date,
    String? taskId,
    String? insulinProfileId,
    String? mealTag,
    double? glucoseMgDl,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId,
      'question': question,
      if (date != null) 'date': date,
      if (taskId != null) 'taskId': taskId,
      if (insulinProfileId != null) 'insulinProfileId': insulinProfileId,
      if (mealTag != null) 'mealTag': mealTag,
      if (glucoseMgDl != null) 'glucoseMgDl': glucoseMgDl,
    };

    final response = await _post('/api/ai/ask', body);
    return AiAskResponseModel.fromJson(response);
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw ApiException(
        code: 'unauthenticated',
        message: 'Sign in is required.',
      );
    }

    final token = await user.getIdToken();
    final uri = Uri.parse('$_baseUrl${_normalizePath(path)}');

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    } catch (error) {
      throw ApiException(
        code: 'network-error',
        message: 'Unable to reach API endpoint: $error',
      );
    }

    Map<String, dynamic> payload = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        payload = decoded;
      } else {
        throw ApiException(
          code: 'invalid-response',
          message: 'API returned invalid JSON payload.',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorNode = payload['error'];
      if (errorNode is Map<String, dynamic>) {
        throw ApiException(
          code: (errorNode['code'] as String?) ?? 'api-error',
          message: (errorNode['message'] as String?) ??
              'Request failed with status ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        code: 'api-error',
        message: 'Request failed with status ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    if (payload['ok'] == false) {
      final errorNode = payload['error'];
      if (errorNode is Map<String, dynamic>) {
        throw ApiException(
          code: (errorNode['code'] as String?) ?? 'api-error',
          message: (errorNode['message'] as String?) ?? 'Request failed.',
          statusCode: response.statusCode,
        );
      }
      throw ApiException(
        code: 'api-error',
        message: 'Request failed.',
        statusCode: response.statusCode,
      );
    }

    return payload;
  }

  static String _resolveBaseUrl(String? provided) {
    final direct = (provided ?? '').trim();
    if (direct.isNotEmpty) {
      return _trimTrailingSlash(direct);
    }

    const env = String.fromEnvironment('HNAS_API_BASE_URL');
    if (env.trim().isNotEmpty) {
      return _trimTrailingSlash(env.trim());
    }

    try {
      final projectId = Firebase.app().options.projectId;
      if (projectId.isNotEmpty) {
        return 'https://us-central1-$projectId.cloudfunctions.net/api';
      }
    } catch (_) {}

    throw ApiException(
      code: 'config-missing',
      message: 'Missing API base URL. Pass --dart-define=HNAS_API_BASE_URL=<function-url>.',
    );
  }

  static String _normalizePath(String path) {
    if (path.startsWith('/')) {
      return path;
    }
    return '/$path';
  }

  static String _trimTrailingSlash(String value) {
    if (value.endsWith('/')) {
      return value.substring(0, value.length - 1);
    }
    return value;
  }
}
