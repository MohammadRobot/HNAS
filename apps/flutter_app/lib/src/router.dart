import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import 'screens/dashboard_screen.dart';
import 'screens/guided_visit_screen.dart';
import 'screens/login_screen.dart';
import 'screens/patient_details_screen.dart';
import 'screens/role_home_screen.dart';
import 'screens/today_screen.dart';
import 'screens/users_management_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final profile = ref.watch(userProfileProvider).value;
  final refresh = GoRouterRefreshStream(auth.authStateChanges());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: refresh,
    routes: <RouteBase>[
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        name: 'home',
        builder: (context, state) => const RoleHomeScreen(),
      ),
      GoRoute(
        path: '/today',
        name: 'today',
        builder: (context, state) => const TodayScreen(),
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
        path: '/visit/:visitId',
        name: 'visit',
        builder: (context, state) {
          final visitId = state.pathParameters['visitId'] ?? '';
          return GuidedVisitScreen(visitId: visitId);
        },
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
      final isPortalUser =
          profile?.role == 'patient' || profile?.role == 'relative';

      if (!isLoggedIn && !isLoginRoute) {
        return '/login';
      }

      if (isLoggedIn && (isLoginRoute || onRoot)) {
        return '/home';
      }

      if (isLoggedIn && isPortalUser && state.matchedLocation != '/home') {
        return '/home';
      }

      if (onRoot) {
        return isLoggedIn ? '/home' : '/login';
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
