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

  Future<Map<String, dynamic>> generateChecklist({
    required String patientId,
    String? date,
  }) async {
    return _post('/api/checklist/generate', <String, dynamic>{
      'patientId': patientId.trim(),
      if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
    });
  }

  Future<Map<String, dynamic>> generatePatientReports({
    required String patientId,
    String? startDate,
    String? endDate,
    int maxDays = 90,
  }) async {
    final boundedMaxDays = maxDays.clamp(1, 365);
    return _post('/api/reports/generate', <String, dynamic>{
      'patientId': patientId.trim(),
      if (startDate != null && startDate.trim().isNotEmpty)
        'startDate': startDate.trim(),
      if (endDate != null && endDate.trim().isNotEmpty)
        'endDate': endDate.trim(),
      'maxDays': boundedMaxDays,
    });
  }

  Future<String> createPatient({
    required String fullName,
    String? timezone,
    bool active = true,
    String? dateOfBirth,
    String? gender,
    String? phoneNumber,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? address,
    String? notes,
    List<String>? riskFlags,
    List<String>? diagnosis,
    List<String>? allergies,
    DateTime? initialHealthCheckAt,
    num? initialWeightKg,
    num? initialTemperatureC,
    num? initialBloodPressureSystolic,
    num? initialBloodPressureDiastolic,
    num? initialPulseBpm,
    num? initialSpo2Pct,
    String? initialHealthCheckNotes,
    String? agencyId,
    List<String>? assignedNurseIds,
  }) async {
    final normalizedName = fullName.trim();
    if (normalizedName.isEmpty) {
      throw ApiException(
        code: 'invalid-argument',
        message: 'fullName is required.',
      );
    }

    final normalizedTimezone = timezone?.trim();
    final normalizedDateOfBirth = dateOfBirth?.trim();
    final normalizedGender = gender?.trim().toLowerCase();
    final normalizedPhoneNumber = phoneNumber?.trim();
    final normalizedEmergencyContactName = emergencyContactName?.trim();
    final normalizedEmergencyContactPhone = emergencyContactPhone?.trim();
    final normalizedAddress = address?.trim();
    final normalizedNotes = notes?.trim();
    final normalizedRiskFlags = _cleanStringList(riskFlags);
    final normalizedDiagnosis = _cleanStringList(diagnosis);
    final normalizedAllergies = _cleanStringList(allergies);
    final normalizedAgencyId = agencyId?.trim();
    final normalizedNurseIds = (assignedNurseIds ?? const <String>[])
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final initialHealthCheck = <String, dynamic>{
      if (initialWeightKg != null) 'weightKg': initialWeightKg,
      if (initialTemperatureC != null) 'temperatureC': initialTemperatureC,
      if (initialBloodPressureSystolic != null)
        'bloodPressureSystolic': initialBloodPressureSystolic,
      if (initialBloodPressureDiastolic != null)
        'bloodPressureDiastolic': initialBloodPressureDiastolic,
      if (initialPulseBpm != null) 'pulseBpm': initialPulseBpm,
      if (initialSpo2Pct != null) 'spo2Pct': initialSpo2Pct,
      if (initialHealthCheckAt != null)
        'checkedAt': initialHealthCheckAt.toUtc().toIso8601String(),
      if (initialHealthCheckNotes != null &&
          initialHealthCheckNotes.trim().isNotEmpty)
        'notes': initialHealthCheckNotes.trim(),
    };

    final response = await _post('/api/patients/create', <String, dynamic>{
      'fullName': normalizedName,
      if (normalizedTimezone != null && normalizedTimezone.isNotEmpty)
        'timezone': normalizedTimezone,
      'active': active,
      if (normalizedDateOfBirth != null && normalizedDateOfBirth.isNotEmpty)
        'dateOfBirth': normalizedDateOfBirth,
      if (normalizedGender != null && normalizedGender.isNotEmpty)
        'gender': normalizedGender,
      if (normalizedPhoneNumber != null && normalizedPhoneNumber.isNotEmpty)
        'phoneNumber': normalizedPhoneNumber,
      if (normalizedEmergencyContactName != null &&
          normalizedEmergencyContactName.isNotEmpty)
        'emergencyContactName': normalizedEmergencyContactName,
      if (normalizedEmergencyContactPhone != null &&
          normalizedEmergencyContactPhone.isNotEmpty)
        'emergencyContactPhone': normalizedEmergencyContactPhone,
      if (normalizedAddress != null && normalizedAddress.isNotEmpty)
        'address': normalizedAddress,
      if (normalizedNotes != null && normalizedNotes.isNotEmpty)
        'notes': normalizedNotes,
      if (normalizedRiskFlags.isNotEmpty) 'riskFlags': normalizedRiskFlags,
      if (normalizedDiagnosis.isNotEmpty) 'diagnosis': normalizedDiagnosis,
      if (normalizedAllergies.isNotEmpty) 'allergies': normalizedAllergies,
      if (initialHealthCheck.isNotEmpty)
        'initialHealthCheck': initialHealthCheck,
      if (normalizedAgencyId != null && normalizedAgencyId.isNotEmpty)
        'agencyId': normalizedAgencyId,
      if (normalizedNurseIds.isNotEmpty) 'assignedNurseIds': normalizedNurseIds,
    });

    final patientId = response['patientId'];
    if (patientId is! String || patientId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing patientId.',
      );
    }
    return patientId;
  }

  Future<String> createHealthCheck({
    required String patientId,
    DateTime? checkedAt,
    num? weightKg,
    num? temperatureC,
    num? bloodPressureSystolic,
    num? bloodPressureDiastolic,
    num? pulseBpm,
    num? spo2Pct,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      if (checkedAt != null) 'checkedAt': checkedAt.toUtc().toIso8601String(),
      if (weightKg != null) 'weightKg': weightKg,
      if (temperatureC != null) 'temperatureC': temperatureC,
      if (bloodPressureSystolic != null)
        'bloodPressureSystolic': bloodPressureSystolic,
      if (bloodPressureDiastolic != null)
        'bloodPressureDiastolic': bloodPressureDiastolic,
      if (pulseBpm != null) 'pulseBpm': pulseBpm,
      if (spo2Pct != null) 'spo2Pct': spo2Pct,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };

    final response = await _post('/api/patients/healthChecks/create', body);
    final healthCheckId = response['healthCheckId'];
    if (healthCheckId is! String || healthCheckId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing healthCheckId.',
      );
    }
    return healthCheckId;
  }

  Future<String> createLabTest({
    required String patientId,
    required String testName,
    String? panel,
    String? scheduleDate,
    String? scheduleTime,
    String status = 'scheduled',
    String? priority,
    String? orderedBy,
    String? notes,
  }) async {
    final response = await _post('/api/labTests/create', <String, dynamic>{
      'patientId': patientId.trim(),
      'testName': testName.trim(),
      if (panel != null && panel.trim().isNotEmpty) 'panel': panel.trim(),
      if (scheduleDate != null && scheduleDate.trim().isNotEmpty)
        'scheduleDate': scheduleDate.trim(),
      if (scheduleTime != null && scheduleTime.trim().isNotEmpty)
        'scheduleTime': scheduleTime.trim(),
      'status': status.trim().toLowerCase(),
      if (priority != null && priority.trim().isNotEmpty)
        'priority': priority.trim(),
      if (orderedBy != null && orderedBy.trim().isNotEmpty)
        'orderedBy': orderedBy.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });

    final labTestId = response['labTestId'];
    if (labTestId is! String || labTestId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing labTestId.',
      );
    }
    return labTestId;
  }

  Future<void> updateLabTest({
    required String patientId,
    required String labTestId,
    String? testName,
    String? panel,
    String? scheduleDate,
    String? scheduleTime,
    String? status,
    String? priority,
    String? orderedBy,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      'labTestId': labTestId.trim(),
      if (testName != null) 'testName': testName.trim(),
      if (panel != null) 'panel': panel.trim(),
      if (scheduleDate != null) 'scheduleDate': scheduleDate.trim(),
      if (scheduleTime != null) 'scheduleTime': scheduleTime.trim(),
      if (status != null) 'status': status.trim().toLowerCase(),
      if (priority != null) 'priority': priority.trim(),
      if (orderedBy != null) 'orderedBy': orderedBy.trim(),
      if (notes != null) 'notes': notes.trim(),
    };
    await _post('/api/labTests/update', body);
  }

  Future<void> recordLabTestResult({
    required String patientId,
    required String labTestId,
    required String resultValue,
    String? resultUnit,
    String? referenceRange,
    String? interpretation,
    String? resultFlag,
    DateTime? resultAt,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      'labTestId': labTestId.trim(),
      'resultValue': resultValue.trim(),
      if (resultUnit != null && resultUnit.trim().isNotEmpty)
        'resultUnit': resultUnit.trim(),
      if (referenceRange != null && referenceRange.trim().isNotEmpty)
        'referenceRange': referenceRange.trim(),
      if (interpretation != null && interpretation.trim().isNotEmpty)
        'interpretation': interpretation.trim(),
      if (resultFlag != null && resultFlag.trim().isNotEmpty)
        'resultFlag': resultFlag.trim().toLowerCase(),
      if (resultAt != null) 'resultAt': resultAt.toUtc().toIso8601String(),
    };
    await _post('/api/labTests/result', body);
  }

  Future<String> createMedicine({
    required String patientId,
    required String name,
    String? instructions,
    num? doseAmount,
    String? doseUnit,
    bool active = true,
    List<String>? scheduleTimes,
  }) async {
    final response = await _post('/api/medicines/create', <String, dynamic>{
      'patientId': patientId.trim(),
      'name': name.trim(),
      if (instructions != null && instructions.trim().isNotEmpty)
        'instructions': instructions.trim(),
      if (doseAmount != null) 'doseAmount': doseAmount,
      if (doseUnit != null && doseUnit.trim().isNotEmpty)
        'doseUnit': doseUnit.trim(),
      'active': active,
      if (_cleanStringList(scheduleTimes).isNotEmpty)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    });

    final medicineId = response['medicineId'];
    if (medicineId is! String || medicineId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing medicineId.',
      );
    }
    return medicineId;
  }

  Future<void> updateMedicine({
    required String patientId,
    required String medicineId,
    String? name,
    String? instructions,
    num? doseAmount,
    String? doseUnit,
    bool? active,
    List<String>? scheduleTimes,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      'medicineId': medicineId.trim(),
      if (name != null) 'name': name.trim(),
      if (instructions != null) 'instructions': instructions.trim(),
      if (doseAmount != null) 'doseAmount': doseAmount,
      if (doseUnit != null) 'doseUnit': doseUnit.trim(),
      if (active != null) 'active': active,
      if (scheduleTimes != null)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    };
    await _post('/api/medicines/update', body);
  }

  Future<String> createProcedure({
    required String patientId,
    required String name,
    String? instructions,
    String? frequency,
    bool active = true,
    List<String>? scheduleTimes,
  }) async {
    final response = await _post('/api/procedures/create', <String, dynamic>{
      'patientId': patientId.trim(),
      'name': name.trim(),
      if (instructions != null && instructions.trim().isNotEmpty)
        'instructions': instructions.trim(),
      if (frequency != null && frequency.trim().isNotEmpty)
        'frequency': frequency.trim(),
      'active': active,
      if (_cleanStringList(scheduleTimes).isNotEmpty)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    });

    final procedureId = response['procedureId'];
    if (procedureId is! String || procedureId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing procedureId.',
      );
    }
    return procedureId;
  }

  Future<void> updateProcedure({
    required String patientId,
    required String procedureId,
    String? name,
    String? instructions,
    String? frequency,
    bool? active,
    List<String>? scheduleTimes,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      'procedureId': procedureId.trim(),
      if (name != null) 'name': name.trim(),
      if (instructions != null) 'instructions': instructions.trim(),
      if (frequency != null) 'frequency': frequency.trim(),
      if (active != null) 'active': active,
      if (scheduleTimes != null)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    };
    await _post('/api/procedures/update', body);
  }

  Future<String> createInsulinProfile({
    required String patientId,
    required String type,
    required String label,
    String? insulinName,
    bool active = true,
    List<num>? slidingScaleMgdl,
    Map<String, num>? mealBaseUnits,
    num? defaultBaseUnits,
    num? fixedUnits,
    String? notes,
    List<String>? scheduleTimes,
  }) async {
    final response =
        await _post('/api/insulinProfiles/create', <String, dynamic>{
      'patientId': patientId.trim(),
      'type': type.trim().toLowerCase(),
      'label': label.trim(),
      if (insulinName != null && insulinName.trim().isNotEmpty)
        'insulinName': insulinName.trim(),
      'active': active,
      if (_cleanNumList(slidingScaleMgdl).isNotEmpty)
        'slidingScaleMgdl': _cleanNumList(slidingScaleMgdl),
      if (_cleanNumMap(mealBaseUnits).isNotEmpty)
        'mealBaseUnits': _cleanNumMap(mealBaseUnits),
      if (defaultBaseUnits != null) 'defaultBaseUnits': defaultBaseUnits,
      if (fixedUnits != null) 'fixedUnits': fixedUnits,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (_cleanStringList(scheduleTimes).isNotEmpty)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    });

    final insulinProfileId = response['insulinProfileId'];
    if (insulinProfileId is! String || insulinProfileId.isEmpty) {
      throw ApiException(
        code: 'invalid-response',
        message: 'API response is missing insulinProfileId.',
      );
    }
    return insulinProfileId;
  }

  Future<void> updateInsulinProfile({
    required String patientId,
    required String insulinProfileId,
    String? type,
    String? label,
    String? insulinName,
    bool? active,
    List<num>? slidingScaleMgdl,
    Map<String, num>? mealBaseUnits,
    num? defaultBaseUnits,
    num? fixedUnits,
    String? notes,
    List<String>? scheduleTimes,
  }) async {
    final body = <String, dynamic>{
      'patientId': patientId.trim(),
      'insulinProfileId': insulinProfileId.trim(),
      if (type != null) 'type': type.trim().toLowerCase(),
      if (label != null) 'label': label.trim(),
      if (insulinName != null) 'insulinName': insulinName.trim(),
      if (active != null) 'active': active,
      if (slidingScaleMgdl != null)
        'slidingScaleMgdl': _cleanNumList(slidingScaleMgdl),
      if (mealBaseUnits != null) 'mealBaseUnits': _cleanNumMap(mealBaseUnits),
      if (defaultBaseUnits != null) 'defaultBaseUnits': defaultBaseUnits,
      if (fixedUnits != null) 'fixedUnits': fixedUnits,
      if (notes != null) 'notes': notes.trim(),
      if (scheduleTimes != null)
        'scheduleTimes': _cleanStringList(scheduleTimes),
    };
    await _post('/api/insulinProfiles/update', body);
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
      message:
          'Missing API base URL. Pass --dart-define=HNAS_API_BASE_URL=<function-url>.',
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

  static List<String> _cleanStringList(List<String>? values) {
    if (values == null) {
      return const <String>[];
    }
    return values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
  }

  static List<num> _cleanNumList(List<num>? values) {
    if (values == null) {
      return const <num>[];
    }
    return values.where((value) => value.isFinite).toList();
  }

  static Map<String, num> _cleanNumMap(Map<String, num>? values) {
    if (values == null) {
      return const <String, num>{};
    }

    final result = <String, num>{};
    for (final entry in values.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || !entry.value.isFinite) {
        continue;
      }
      result[key] = entry.value;
    }
    return result;
  }
}
