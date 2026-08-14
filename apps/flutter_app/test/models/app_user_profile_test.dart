import 'package:flutter_app/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('patient profile exposes its linked patient', () {
    final profile = AppUserProfile.fromMap('patient-user', <String, dynamic>{
      'role': 'patient',
      'patientId': 'patient-1',
    });

    expect(profile.accessiblePatientIds, <String>['patient-1']);
  });

  test('relative profile exposes each linked patient without duplicates', () {
    final profile = AppUserProfile.fromMap('relative-user', <String, dynamic>{
      'role': 'relative',
      'patientId': 'patient-1',
      'patientIds': <String>['patient-1', 'patient-2'],
    });

    expect(profile.accessiblePatientIds, <String>['patient-1', 'patient-2']);
  });
}
