import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/patient_details_screen.dart';
import 'screens/users_management_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final refresh = GoRouterRefreshStream(auth.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/users',
        name: 'users',
        builder: (context, state) => const UsersManagementScreen(),
      ),
      GoRoute(
        path: '/patient/:patientId',
        name: 'patient',
        builder: (context, state) {
          final patientId = state.pathParameters['patientId'] ?? '';
          return PatientDetailsScreen(patientId: patientId);
        },
      ),
    ],
    redirect: (context, state) {
      final isLoggedIn = auth.currentUser != null;
      final isLoginRoute = state.matchedLocation == '/login';
      final onRoot = state.matchedLocation == '/';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      if (isLoggedIn && (isLoginRoute || onRoot)) {
        return '/dashboard';
      }

      if (onRoot) {
        return isLoggedIn ? '/dashboard' : '/login';
      }

      return null;
    },
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
