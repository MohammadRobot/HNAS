import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? bootstrapError;
  StackTrace? bootstrapStackTrace;

  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: _buildWebFirebaseOptions()).timeout(
        const Duration(seconds: 12),
      );
    } else {
      await Firebase.initializeApp().timeout(
        const Duration(seconds: 12),
      );
    }

    const useFirebaseEmulators =
        bool.fromEnvironment('HNAS_USE_FIREBASE_EMULATORS', defaultValue: true);
    if (kIsWeb && useFirebaseEmulators) {
      _configureFirestoreWebForEmulator();
    }
    if (useFirebaseEmulators) {
      await _connectFirebaseEmulators();
      if (kIsWeb) {
        // Avoid stale persisted auth sessions after emulator restarts.
        await FirebaseAuth.instance.signOut();
      }
    }
  } catch (error, stackTrace) {
    bootstrapError = error;
    bootstrapStackTrace = stackTrace;
    debugPrint('BOOTSTRAP_FAILED: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  runApp(
    ProviderScope(
      child: bootstrapError == null
          ? const HnasApp()
          : _BootstrapErrorApp(
              error: bootstrapError,
              stackTrace: bootstrapStackTrace,
            ),
    ),
  );
}

Future<void> _connectFirebaseEmulators() async {
  const host =
      String.fromEnvironment('HNAS_EMULATOR_HOST', defaultValue: '127.0.0.1');
  const firestorePort =
      int.fromEnvironment('HNAS_FIRESTORE_EMULATOR_PORT', defaultValue: 8080);
  const authPort =
      int.fromEnvironment('HNAS_AUTH_EMULATOR_PORT', defaultValue: 9099);

  FirebaseFirestore.instance.useFirestoreEmulator(host, firestorePort);
  await FirebaseAuth.instance
      .useAuthEmulator(host, authPort)
      .timeout(const Duration(seconds: 8));
}

void _configureFirestoreWebForEmulator() {
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
    webExperimentalForceLongPolling: true,
    webExperimentalAutoDetectLongPolling: false,
  );
}

FirebaseOptions _buildWebFirebaseOptions() {
  const configuredProjectId =
      String.fromEnvironment('HNAS_FIREBASE_PROJECT_ID');
  final projectId = configuredProjectId.trim().isEmpty
      ? 'demo-hnas'
      : configuredProjectId.trim();

  return FirebaseOptions(
    apiKey: const String.fromEnvironment('HNAS_FIREBASE_API_KEY',
        defaultValue: 'demo-api-key'),
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

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({
    required this.error,
    required this.stackTrace,
  });

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    final details = '$error';
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('HNAS Startup Error')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: <Widget>[
              const Text(
                'App startup failed before rendering the main UI.',
              ),
              const SizedBox(height: 12),
              Text('Error: $details'),
              const SizedBox(height: 12),
              const Text(
                'Checks:',
              ),
              const SizedBox(height: 4),
              const Text('1. Start emulators with `npm run serve:functions`'),
              const Text(
                  '2. Seed demo data with `npm --prefix functions run seed:demo`'),
              const Text('3. Re-run Flutter app with HNAS dart-defines'),
              if (stackTrace != null) ...<Widget>[
                const SizedBox(height: 12),
                const Text('Stack trace:'),
                const SizedBox(height: 4),
                Text(
                  '$stackTrace',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
