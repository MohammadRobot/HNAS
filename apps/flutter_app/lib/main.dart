import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    await Firebase.initializeApp(options: _buildWebFirebaseOptions());
  } else {
    await Firebase.initializeApp();
  }

  const useFirebaseEmulators =
      bool.fromEnvironment('HNAS_USE_FIREBASE_EMULATORS', defaultValue: true);
  if (useFirebaseEmulators) {
    await _connectFirebaseEmulators();
  }

  runApp(const ProviderScope(child: HnasApp()));
}

Future<void> _connectFirebaseEmulators() async {
  const host = String.fromEnvironment('HNAS_EMULATOR_HOST', defaultValue: '127.0.0.1');
  const firestorePort = int.fromEnvironment('HNAS_FIRESTORE_EMULATOR_PORT', defaultValue: 8080);
  const authPort = int.fromEnvironment('HNAS_AUTH_EMULATOR_PORT', defaultValue: 9099);

  FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  await FirebaseAuth.instance.useAuthEmulator(host, authPort);
}

FirebaseOptions _buildWebFirebaseOptions() {
  const configuredProjectId = String.fromEnvironment('HNAS_FIREBASE_PROJECT_ID');
  final projectId = configuredProjectId.trim().isEmpty
      ? 'demo-hnas'
      : configuredProjectId.trim();

  return FirebaseOptions(
    apiKey: const String.fromEnvironment('HNAS_FIREBASE_API_KEY', defaultValue: 'demo-api-key'),
    appId: const String.fromEnvironment(
      'HNAS_FIREBASE_APP_ID',
      defaultValue: '1:1234567890:web:demohnas',
    ),
    messagingSenderId: const String.fromEnvironment(
      'HNAS_FIREBASE_MESSAGING_SENDER_ID',
      defaultValue: '1234567890',
    ),
    projectId: projectId,
    authDomain: '$projectId.firebaseapp.com',
    storageBucket: '$projectId.appspot.com',
  );
}
