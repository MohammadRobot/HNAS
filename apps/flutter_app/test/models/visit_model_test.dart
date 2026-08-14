import 'package:flutter_app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VisitModel parses cached checklist progress', () {
    final visit = VisitModel.fromMap(<String, dynamic>{
      'id': '2026-08-05_patient_1',
      'patientId': 'patient_1',
      'patientName': 'Demo Patient',
      'dateId': '2026-08-05',
      'status': 'in_progress',
      'taskCount': 4,
      'completedTaskCount': 3,
      'pendingTaskCount': 1,
      'issueCount': 1,
      'assignedCaregiverIds': <String>['nurse_1'],
    });

    expect(visit.isInProgress, isTrue);
    expect(visit.needsAttention, isTrue);
    expect(visit.progress, 0.75);
    expect(visit.assignedCaregiverIds, <String>['nurse_1']);
  });

  test('VisitModel protects progress from invalid task totals', () {
    final visit = VisitModel.fromMap(<String, dynamic>{
      'id': 'empty_visit',
      'patientId': 'patient_1',
      'patientName': 'Demo Patient',
      'dateId': '2026-08-05',
      'status': 'scheduled',
      'taskCount': 0,
      'completedTaskCount': 0,
      'pendingTaskCount': 0,
      'issueCount': 0,
    });

    expect(visit.progress, 0);
  });
}
