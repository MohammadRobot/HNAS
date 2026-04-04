import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'services/api_client.dart';

const _firebaseStreamTimeout = Duration(seconds: 15);

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return ApiClient(auth: auth);
});

final authStateProvider = StreamProvider<User?>((ref) {
  return _withStreamTimeout(
    ref.watch(firebaseAuthProvider).authStateChanges(),
    'authentication state',
  );
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});

final userProfileProvider = StreamProvider<AppUserProfile?>((ref) {
  final authAsync = ref.watch(authStateProvider);
  if (authAsync.hasError) {
    return Stream.error(authAsync.error!, authAsync.stackTrace);
  }

  final uid = authAsync.value?.uid;
  if (uid == null) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firestoreProvider);
  return _withStreamTimeout(
    firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return AppUserProfile.fromMap(uid, snapshot.data()!);
    }),
    'user profile',
  );
});

final todayDateIdProvider = Provider<String>((ref) {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
});

final patientsStreamProvider = StreamProvider<List<PatientModel>>((ref) {
  final userProfileAsync = ref.watch(userProfileProvider);
  if (userProfileAsync.hasError) {
    return Stream.error(userProfileAsync.error!, userProfileAsync.stackTrace);
  }

  final userProfile = userProfileAsync.value;
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null || userProfile == null) {
    return Stream.value(const <PatientModel>[]);
  }

  Query<Map<String, dynamic>> query =
      ref.watch(firestoreProvider).collection('patients');

  if (userProfile.role == 'nurse') {
    query = query.where('assignedNurseIds', arrayContains: uid);
  } else if (userProfile.role == 'admin' || userProfile.role == 'supervisor') {
    final agencyId = userProfile.agencyId;
    if (agencyId == null || agencyId.isEmpty) {
      return Stream.error(
        StateError(
          'User profile is missing agencyId. '
          'Update /users/$uid with a valid agencyId.',
        ),
      );
    }
    query = query.where('agencyId', isEqualTo: agencyId);
  } else {
    return Stream.error(
      StateError(
        'Unsupported role "${userProfile.role}" for patient access.',
      ),
    );
  }

  return _withStreamTimeout(
    query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PatientModel.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    }),
    'patients list',
  );
});

final patientProvider =
    StreamProvider.family<PatientModel?, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return PatientModel.fromMap(snapshot.id, snapshot.data()!);
    }),
    'patient details',
  );
});

final medicinesProvider =
    StreamProvider.family<List<MedicineModel>, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('medicines')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MedicineModel.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }),
    'medicines',
  );
});

final proceduresProvider =
    StreamProvider.family<List<ProcedureModel>, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('procedures')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ProcedureModel.fromMap(doc.id, doc.data()))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    }),
    'procedures',
  );
});

final labTestsProvider =
    StreamProvider.family<List<LabTestModel>, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('labTests')
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => LabTestModel.fromMap(doc.id, doc.data()))
          .toList();

      list.sort((left, right) {
        final leftKey =
            '${left.scheduleDate ?? '0000-00-00'} ${left.scheduleTime ?? '00:00'}';
        final rightKey =
            '${right.scheduleDate ?? '0000-00-00'} ${right.scheduleTime ?? '00:00'}';
        final byDate = rightKey.compareTo(leftKey);
        if (byDate != 0) {
          return byDate;
        }
        return left.testName.compareTo(right.testName);
      });

      return list;
    }),
    'lab tests',
  );
});

final insulinProfilesProvider =
    StreamProvider.family<List<InsulinProfileModel>, String>((ref, patientId) {
  final firestore = ref.watch(firestoreProvider);
  final patientRef = firestore.collection('patients').doc(patientId);
  return _withStreamTimeout(
    patientRef.collection('insulinProfiles').snapshots(),
    'insulin profiles',
  ).asyncMap((snapshot) async {
    final profiles = snapshot.docs
        .map((doc) => InsulinProfileModel.fromMap(doc.id, doc.data()))
        .toList();

    if (profiles.isNotEmpty) {
      profiles.sort((a, b) => a.label.compareTo(b.label));
      return profiles;
    }

    final patientSnapshot = await patientRef.get().timeout(
          const Duration(seconds: 10),
        );
    final data = patientSnapshot.data();
    if (data == null) {
      return const <InsulinProfileModel>[];
    }

    final inline = data['insulinProfiles'];
    if (inline is! List) {
      return const <InsulinProfileModel>[];
    }

    final result = inline.whereType<Map>().map((entry) {
      final map = entry.cast<String, dynamic>();
      final id = map['id'] is String && (map['id'] as String).isNotEmpty
          ? map['id'] as String
          : 'inline';
      return InsulinProfileModel.fromMap(id, map);
    }).toList();
    result.sort((a, b) => a.label.compareTo(b.label));
    return result;
  });
});

class ChecklistQuery {
  const ChecklistQuery({
    required this.patientId,
    required this.dateId,
  });

  final String patientId;
  final String dateId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ChecklistQuery &&
        other.patientId == patientId &&
        other.dateId == dateId;
  }

  @override
  int get hashCode => Object.hash(patientId, dateId);
}

final checklistProvider =
    StreamProvider.family<DailyChecklistModel?, ChecklistQuery>((ref, query) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(query.patientId)
        .collection('dailyChecklists')
        .doc(query.dateId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return DailyChecklistModel.fromMap(snapshot.id, snapshot.data()!);
    }),
    'daily checklist',
  );
});

final reportsProvider =
    StreamProvider.family<List<DailyReportModel>, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('reports')
        .doc('daily')
        .collection('byDate')
        .orderBy('dateId', descending: true)
        .limit(14)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => DailyReportModel.fromMap(doc.id, doc.data()))
          .toList();
    }),
    'reports',
  );
});

final healthChecksProvider =
    StreamProvider.family<List<HealthCheckModel>, String>((ref, patientId) {
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('healthChecks')
        .orderBy('checkedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => HealthCheckModel.fromMap(doc.id, doc.data()))
          .toList();
    }),
    'health checks',
  );
});

final todayReportProvider =
    StreamProvider.family<DailyReportModel?, String>((ref, patientId) {
  final dateId = ref.watch(todayDateIdProvider);
  return _withStreamTimeout(
    ref
        .watch(firestoreProvider)
        .collection('patients')
        .doc(patientId)
        .collection('reports')
        .doc('daily')
        .collection('byDate')
        .doc(dateId)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists || snapshot.data() == null) {
        return null;
      }
      return DailyReportModel.fromMap(snapshot.id, snapshot.data()!);
    }),
    'today report',
  );
});

final dashboardCountsProvider = FutureProvider<DashboardCounts>((ref) async {
  final dateId = ref.watch(todayDateIdProvider);
  final profile = await ref.watch(userProfileProvider.future);
  if (profile == null) {
    return const DashboardCounts(
      totalPatients: 0,
      done: 0,
      missed: 0,
      late: 0,
      skipped: 0,
    );
  }

  return ref.read(apiClientProvider).fetchDashboardCounts(date: dateId);
});

Stream<T> _withStreamTimeout<T>(Stream<T> stream, String label) {
  const useFirebaseEmulators =
      bool.fromEnvironment('HNAS_USE_FIREBASE_EMULATORS', defaultValue: true);

  // Work around a Firestore Web SDK assertion crash seen with wrapped
  // watch streams while connected to the local emulator.
  if (kIsWeb && useFirebaseEmulators) {
    return stream;
  }

  return Stream<T>.multi((controller) {
    var receivedFirstEvent = false;
    var isClosed = false;

    void closeOnce() {
      if (isClosed) {
        return;
      }
      isClosed = true;
      controller.close();
    }

    late final StreamSubscription<T> subscription;
    final timeout = Timer(_firebaseStreamTimeout, () {
      if (receivedFirstEvent || isClosed) {
        return;
      }
      controller.addError(
        TimeoutException(
          'Timed out while loading $label. '
          'Ensure emulators are running and demo data is seeded.',
        ),
      );
      unawaited(subscription.cancel());
      closeOnce();
    });

    subscription = stream.listen(
      (event) {
        if (!receivedFirstEvent) {
          receivedFirstEvent = true;
          timeout.cancel();
        }
        if (!isClosed) {
          controller.add(event);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!receivedFirstEvent) {
          timeout.cancel();
        }
        if (!isClosed) {
          controller.addError(error, stackTrace);
        }
      },
      onDone: () {
        timeout.cancel();
        closeOnce();
      },
    );

    controller.onCancel = () async {
      timeout.cancel();
      isClosed = true;
      await subscription.cancel();
    };
  });
}
