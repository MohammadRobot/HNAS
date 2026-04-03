import 'dart:math';

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.role,
    this.agencyId,
    this.displayName,
  });

  final String uid;
  final String role;
  final String? agencyId;
  final String? displayName;

  factory AppUserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return AppUserProfile(
      uid: uid,
      role: _readString(map['role']) ?? 'viewer',
      agencyId: _readString(map['agencyId']),
      displayName: _readString(map['displayName']),
    );
  }
}

class PatientModel {
  const PatientModel({
    required this.id,
    required this.fullName,
    required this.active,
    this.timezone,
    this.agencyId,
    this.dateOfBirth,
    this.gender,
    this.phoneNumber,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.address,
    this.notes,
    this.riskFlags = const <String>[],
    this.diagnosis = const <String>[],
    this.allergies = const <String>[],
  });

  final String id;
  final String fullName;
  final bool active;
  final String? timezone;
  final String? agencyId;
  final String? dateOfBirth;
  final String? gender;
  final String? phoneNumber;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? address;
  final String? notes;
  final List<String> riskFlags;
  final List<String> diagnosis;
  final List<String> allergies;

  factory PatientModel.fromMap(String id, Map<String, dynamic> map) {
    return PatientModel(
      id: id,
      fullName: _readString(map['fullName']) ?? 'Unnamed Patient',
      active: _readBool(map['active']) ?? true,
      timezone: _readString(map['timezone']),
      agencyId: _readString(map['agencyId']),
      dateOfBirth: _readString(map['dateOfBirth']),
      gender: _readString(map['gender']),
      phoneNumber: _readString(map['phoneNumber']),
      emergencyContactName: _readString(map['emergencyContactName']),
      emergencyContactPhone: _readString(map['emergencyContactPhone']),
      address: _readString(map['address']),
      notes: _readString(map['notes']),
      riskFlags: _readStringList(map['riskFlags']),
      diagnosis: _normalizeDiagnosis(map['diagnosis']),
      allergies: _readStringList(map['allergies']),
    );
  }
}

class MedicineModel {
  const MedicineModel({
    required this.id,
    required this.name,
    this.instructions,
    this.doseAmount,
    this.doseUnit,
    this.scheduleTimes = const <String>[],
    this.active = true,
  });

  final String id;
  final String name;
  final String? instructions;
  final num? doseAmount;
  final String? doseUnit;
  final List<String> scheduleTimes;
  final bool active;

  factory MedicineModel.fromMap(String id, Map<String, dynamic> map) {
    return MedicineModel(
      id: id,
      name: _readString(map['name']) ?? 'Medicine',
      instructions: _readString(map['instructions']),
      doseAmount: _readNum(map['doseAmount']),
      doseUnit: _readString(map['doseUnit']),
      scheduleTimes: _readScheduleTimes(map),
      active: _readBool(map['active']) ?? true,
    );
  }
}

class ProcedureModel {
  const ProcedureModel({
    required this.id,
    required this.name,
    this.instructions,
    this.frequency,
    this.scheduleTimes = const <String>[],
    this.active = true,
  });

  final String id;
  final String name;
  final String? instructions;
  final String? frequency;
  final List<String> scheduleTimes;
  final bool active;

  factory ProcedureModel.fromMap(String id, Map<String, dynamic> map) {
    return ProcedureModel(
      id: id,
      name: _readString(map['name']) ?? 'Procedure',
      instructions: _readString(map['instructions']),
      frequency: _readString(map['frequency']),
      scheduleTimes: _readScheduleTimes(map),
      active: _readBool(map['active']) ?? true,
    );
  }
}

class LabTestModel {
  const LabTestModel({
    required this.id,
    required this.testName,
    required this.status,
    this.panel,
    this.scheduleDate,
    this.scheduleTime,
    this.priority,
    this.orderedBy,
    this.notes,
    this.resultValue,
    this.resultUnit,
    this.referenceRange,
    this.interpretation,
    this.resultFlag,
    this.resultAt,
  });

  final String id;
  final String testName;
  final String status;
  final String? panel;
  final String? scheduleDate;
  final String? scheduleTime;
  final String? priority;
  final String? orderedBy;
  final String? notes;
  final String? resultValue;
  final String? resultUnit;
  final String? referenceRange;
  final String? interpretation;
  final String? resultFlag;
  final String? resultAt;

  bool get hasResult {
    return resultValue != null ||
        interpretation != null ||
        resultFlag != null ||
        resultAt != null;
  }

  factory LabTestModel.fromMap(String id, Map<String, dynamic> map) {
    return LabTestModel(
      id: id,
      testName: _readString(map['testName']) ??
          _readString(map['name']) ??
          'Lab Test',
      status: _readString(map['status']) ?? 'scheduled',
      panel: _readString(map['panel']),
      scheduleDate: _readString(map['scheduleDate']),
      scheduleTime: _readString(map['scheduleTime']),
      priority: _readString(map['priority']),
      orderedBy: _readString(map['orderedBy']),
      notes: _readString(map['notes']),
      resultValue: _readStringOrNum(map['resultValue']),
      resultUnit: _readString(map['resultUnit']),
      referenceRange: _readString(map['referenceRange']),
      interpretation: _readString(map['interpretation']),
      resultFlag: _readString(map['resultFlag']),
      resultAt: _readString(map['resultAt']),
    );
  }
}

class InsulinProfileModel {
  const InsulinProfileModel({
    required this.id,
    required this.type,
    required this.label,
    this.insulinName,
    this.active = true,
    this.notes,
    this.fixedUnits,
    this.scheduleTimes = const <String>[],
    this.slidingScaleMgdl = const <num>[],
    this.mealBaseUnits = const <String, num>{},
    this.defaultBaseUnits,
  });

  final String id;
  final String type;
  final String label;
  final String? insulinName;
  final bool active;
  final String? notes;
  final num? fixedUnits;
  final List<String> scheduleTimes;
  final List<num> slidingScaleMgdl;
  final Map<String, num> mealBaseUnits;
  final num? defaultBaseUnits;

  bool get isRapid => type == 'rapid';
  bool get isBasal => type == 'basal';

  factory InsulinProfileModel.fromMap(String id, Map<String, dynamic> map) {
    final mealBaseRaw = map['mealBaseUnits'];
    final mealBase = <String, num>{};
    if (mealBaseRaw is Map) {
      for (final entry in mealBaseRaw.entries) {
        final key = entry.key.toString();
        final value = _readNum(entry.value);
        if (value != null) {
          mealBase[key] = value;
        }
      }
    }

    return InsulinProfileModel(
      id: id,
      type: _readString(map['type']) ?? 'rapid',
      label: _readString(map['label']) ??
          _readString(map['insulinName']) ??
          'Insulin Profile',
      insulinName: _readString(map['insulinName']),
      active: _readBool(map['active']) ?? true,
      notes: _readString(map['notes']),
      fixedUnits: _readNum(map['fixedUnits']),
      scheduleTimes: _readScheduleTimes(map),
      slidingScaleMgdl: _readNumList(map['slidingScaleMgdl']),
      mealBaseUnits: mealBase,
      defaultBaseUnits: _readNum(map['defaultBaseUnits']),
    );
  }
}

class ChecklistTaskModel {
  const ChecklistTaskModel({
    required this.id,
    required this.type,
    required this.title,
    this.scheduledTime,
    this.notes,
    this.medicineId,
    this.procedureId,
    this.insulinProfileId,
  });

  final String id;
  final String type;
  final String title;
  final String? scheduledTime;
  final String? notes;
  final String? medicineId;
  final String? procedureId;
  final String? insulinProfileId;

  bool get isInsulinRapid => type == 'insulin_rapid';

  factory ChecklistTaskModel.fromMap(Map<String, dynamic> map) {
    return ChecklistTaskModel(
      id: _readString(map['id']) ?? '',
      type: _readString(map['type']) ?? 'unknown',
      title: _readString(map['title']) ?? 'Task',
      scheduledTime: _readString(map['scheduledTime']),
      notes: _readString(map['notes']),
      medicineId: _readString(map['medicineId']),
      procedureId: _readString(map['procedureId']),
      insulinProfileId: _readString(map['insulinProfileId']),
    );
  }
}

class ChecklistResultModel {
  const ChecklistResultModel({
    required this.taskId,
    required this.type,
    required this.status,
    this.completedAt,
    this.note,
    this.glucoseMgDl,
    this.mealTag,
    this.baseUnits,
    this.slidingUnits,
    this.totalUnits,
  });

  final String taskId;
  final String type;
  final String status;
  final String? completedAt;
  final String? note;
  final num? glucoseMgDl;
  final String? mealTag;
  final num? baseUnits;
  final num? slidingUnits;
  final num? totalUnits;

  factory ChecklistResultModel.fromMap(Map<String, dynamic> map) {
    return ChecklistResultModel(
      taskId: _readString(map['taskId']) ?? '',
      type: _readString(map['type']) ?? 'unknown',
      status: _readString(map['status']) ?? 'pending',
      completedAt: _readString(map['completedAt']),
      note: _readString(map['note']),
      glucoseMgDl: _readNum(map['glucoseMgDl']),
      mealTag: _readString(map['mealTag']),
      baseUnits: _readNum(map['baseUnits']),
      slidingUnits: _readNum(map['slidingUnits']),
      totalUnits: _readNum(map['totalUnits']),
    );
  }
}

class DailyChecklistModel {
  const DailyChecklistModel({
    required this.id,
    required this.dateId,
    required this.tasks,
    required this.results,
    this.updatedAt,
  });

  final String id;
  final String dateId;
  final List<ChecklistTaskModel> tasks;
  final List<ChecklistResultModel> results;
  final String? updatedAt;

  factory DailyChecklistModel.fromMap(String id, Map<String, dynamic> map) {
    final tasksRaw = map['tasks'];
    final resultsRaw = map['results'];
    return DailyChecklistModel(
      id: id,
      dateId: _readString(map['dateId']) ?? id,
      tasks: tasksRaw is List
          ? tasksRaw
              .whereType<Map>()
              .map(
                (entry) => ChecklistTaskModel.fromMap(
                  entry.cast<String, dynamic>(),
                ),
              )
              .toList()
          : const <ChecklistTaskModel>[],
      results: resultsRaw is List
          ? resultsRaw
              .whereType<Map>()
              .map(
                (entry) => ChecklistResultModel.fromMap(
                  entry.cast<String, dynamic>(),
                ),
              )
              .toList()
          : const <ChecklistResultModel>[],
      updatedAt: _readString(map['updatedAt']),
    );
  }

  Map<String, ChecklistResultModel> resultByTaskId() {
    return {
      for (final result in results) result.taskId: result,
    };
  }
}

class DailyReportModel {
  const DailyReportModel({
    required this.dateId,
    required this.done,
    required this.missed,
    required this.late,
    required this.skipped,
  });

  final String dateId;
  final int done;
  final int missed;
  final int late;
  final int skipped;

  int get total => max(1, done + missed + late + skipped);

  factory DailyReportModel.fromMap(String id, Map<String, dynamic> map) {
    return DailyReportModel(
      dateId: _readString(map['dateId']) ?? id,
      done: _readInt(map['done']) ?? 0,
      missed: _readInt(map['missed']) ?? 0,
      late: _readInt(map['late']) ?? 0,
      skipped: _readInt(map['skipped']) ?? 0,
    );
  }
}

class HealthCheckModel {
  const HealthCheckModel({
    required this.id,
    required this.patientId,
    required this.checkedAt,
    this.dateId,
    this.weightKg,
    this.temperatureC,
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.pulseBpm,
    this.spo2Pct,
    this.notes,
    this.recordedByUid,
  });

  final String id;
  final String patientId;
  final String checkedAt;
  final String? dateId;
  final num? weightKg;
  final num? temperatureC;
  final num? bloodPressureSystolic;
  final num? bloodPressureDiastolic;
  final num? pulseBpm;
  final num? spo2Pct;
  final String? notes;
  final String? recordedByUid;

  factory HealthCheckModel.fromMap(String id, Map<String, dynamic> map) {
    return HealthCheckModel(
      id: id,
      patientId: _readString(map['patientId']) ?? '',
      checkedAt: _readString(map['checkedAt']) ?? '',
      dateId: _readString(map['dateId']),
      weightKg: _readNum(map['weightKg']),
      temperatureC: _readNum(map['temperatureC']),
      bloodPressureSystolic: _readNum(map['bloodPressureSystolic']),
      bloodPressureDiastolic: _readNum(map['bloodPressureDiastolic']),
      pulseBpm: _readNum(map['pulseBpm']),
      spo2Pct: _readNum(map['spo2Pct']),
      notes: _readString(map['notes']),
      recordedByUid: _readString(map['recordedByUid']),
    );
  }
}

class DashboardCounts {
  const DashboardCounts({
    required this.totalPatients,
    required this.done,
    required this.missed,
    required this.late,
    required this.skipped,
  });

  final int totalPatients;
  final int done;
  final int missed;
  final int late;
  final int skipped;
}

class AiAskResponseModel {
  const AiAskResponseModel({
    required this.answerText,
    required this.answerType,
    required this.bullets,
    required this.disclaimer,
    required this.references,
    required this.safetyFlags,
    required this.nextActions,
  });

  final String answerText;
  final String answerType;
  final List<String> bullets;
  final String disclaimer;
  final List<String> references;
  final List<String> safetyFlags;
  final List<String> nextActions;

  factory AiAskResponseModel.fromJson(Map<String, dynamic> json) {
    return AiAskResponseModel(
      answerText: _readString(json['answer_text']) ?? '',
      answerType: _readString(json['answer_type']) ?? 'general_guidance',
      bullets: _readStringList(json['bullets']),
      disclaimer: _readString(json['disclaimer']) ?? '',
      references: _readStringList(json['references']),
      safetyFlags: _readStringList(json['safety_flags']),
      nextActions: _readStringList(json['next_actions']),
    );
  }
}

class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.fromUser,
    required this.text,
    this.meta = const <String>[],
  });

  final String id;
  final bool fromUser;
  final String text;
  final List<String> meta;
}

String? _readString(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  return null;
}

String? _readStringOrNum(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  if (value is num) {
    return value.toString();
  }
  return null;
}

bool? _readBool(Object? value) {
  if (value is bool) {
    return value;
  }
  return null;
}

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}

num? _readNum(Object? value) {
  if (value is num) {
    return value;
  }
  return null;
}

List<num> _readNumList(Object? value) {
  if (value is List) {
    return value.whereType<num>().toList();
  }
  return const <num>[];
}

List<String> _readStringList(Object? value) {
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const <String>[];
}

List<String> _normalizeDiagnosis(Object? value) {
  if (value is String && value.trim().isNotEmpty) {
    return <String>[value.trim()];
  }
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const <String>[];
}

List<String> _readScheduleTimes(Map<String, dynamic> map) {
  final times = <String>{};

  void collect(Object? value) {
    if (value is String) {
      final normalized = _normalizeClockTime(value);
      if (normalized != null) {
        times.add(normalized);
      }
      return;
    }

    if (value is List) {
      for (final item in value) {
        collect(item);
      }
      return;
    }

    if (value is Map) {
      collect(value['time']);
      collect(value['times']);
      collect(value['scheduleTimes']);
      collect(value['entries']);
      collect(value['at']);
      collect(value['scheduledTime']);
      collect(value['startTime']);
    }
  }

  collect(map['time']);
  collect(map['times']);
  collect(map['scheduleTimes']);
  collect(map['schedule']);

  final result = times.toList();
  result.sort();
  return result;
}

String? _normalizeClockTime(String raw) {
  final value = raw.trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match == null) {
    return null;
  }

  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null) {
    return null;
  }
  if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
    return null;
  }
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}
