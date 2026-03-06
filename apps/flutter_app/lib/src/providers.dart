import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'services/api_client.dart';

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
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});

final userProfileProvider = StreamProvider<AppUserProfile?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firestoreProvider);
  return firestore.collection('users').doc(uid).snapshots().map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return AppUserProfile.fromMap(uid, snapshot.data()!);
  });
});

final todayDateIdProvider = Provider<String>((ref) {
  final now = DateTime.now().toUtc();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
});

final patientsStreamProvider = StreamProvider<List<PatientModel>>((ref) {
  final userProfile = ref.watch(userProfileProvider).value;
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null || userProfile == null) {
    return Stream.value(const <PatientModel>[]);
  }

  Query<Map<String, dynamic>> query =
      ref.watch(firestoreProvider).collection('patients');

  if (userProfile.role == 'nurse') {
    query = query.where('assignedNurseIds', arrayContains: uid);
  } else if ((userProfile.role == 'admin' || userProfile.role == 'supervisor') &&
      userProfile.agencyId != null &&
      userProfile.agencyId!.isNotEmpty) {
    query = query.where('agencyId', isEqualTo: userProfile.agencyId);
  }

  return query.snapshots().map((snapshot) {
    return snapshot.docs
        .map((doc) => PatientModel.fromMap(doc.id, doc.data()))
        .toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  });
});

final patientProvider = StreamProvider.family<PatientModel?, String>((ref, patientId) {
  return ref
      .watch(firestoreProvider)
      .collection('patients')
      .doc(patientId)
      .snapshots()
      .map((snapshot) {
    if (!snapshot.exists || snapshot.data() == null) {
      return null;
    }
    return PatientModel.fromMap(snapshot.id, snapshot.data()!);
  });
});

final medicinesProvider = StreamProvider.family<List<MedicineModel>, String>((ref, patientId) {
  return ref
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
  });
});

final proceduresProvider = StreamProvider.family<List<ProcedureModel>, String>((ref, patientId) {
  return ref
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
  });
});

final insulinProfilesProvider =
    StreamProvider.family<List<InsulinProfileModel>, String>((ref, patientId) {
  final firestore = ref.watch(firestoreProvider);
  final patientRef = firestore.collection('patients').doc(patientId);
  return patientRef.collection('insulinProfiles').snapshots().asyncMap((snapshot) async {
    final profiles = snapshot.docs
        .map((doc) => InsulinProfileModel.fromMap(doc.id, doc.data()))
        .toList();

    if (profiles.isNotEmpty) {
      profiles.sort((a, b) => a.label.compareTo(b.label));
      return profiles;
    }

    final patientSnapshot = await patientRef.get();
    final data = patientSnapshot.data();
    if (data == null) {
      return const <InsulinProfileModel>[];
    }

    final inline = data['insulinProfiles'];
    if (inline is! List) {
      return const <InsulinProfileModel>[];
    }

    final result = inline
        .whereType<Map>()
        .map((entry) {
          final map = entry.cast<String, dynamic>();
          final id = map['id'] is String && (map['id'] as String).isNotEmpty
              ? map['id'] as String
              : 'inline';
          return InsulinProfileModel.fromMap(id, map);
        })
        .toList();
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
  return ref
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
  });
});

final reportsProvider = StreamProvider.family<List<DailyReportModel>, String>((ref, patientId) {
  return ref
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
  });
});

final todayReportProvider = StreamProvider.family<DailyReportModel?, String>((ref, patientId) {
  final dateId = ref.watch(todayDateIdProvider);
  return ref
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
  });
});

final dashboardCountsProvider = StreamProvider<DashboardCounts>((ref) {
  final dateId = ref.watch(todayDateIdProvider);
  final totalPatients = ref.watch(patientsStreamProvider).value?.length ?? 0;

  return ref
      .watch(firestoreProvider)
      .collectionGroup('dailyChecklists')
      .where('dateId', isEqualTo: dateId)
      .snapshots()
      .map((snapshot) {
    var done = 0;
    var missed = 0;
    var late = 0;
    var skipped = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final checklist = DailyChecklistModel.fromMap(doc.id, data);
      final resultMap = checklist.resultByTaskId();

      for (final task in checklist.tasks) {
        final status = resultMap[task.id]?.status ?? 'pending';
        if (status == 'completed' || status == 'done') {
          done += 1;
        } else if (status == 'late') {
          late += 1;
        } else if (status == 'skipped') {
          skipped += 1;
        } else {
          missed += 1;
        }
      }
    }

    return DashboardCounts(
      totalPatients: totalPatients,
      done: done,
      missed: missed,
      late: late,
      skipped: skipped,
    );
  });
});

