import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_app/src/app_localizations.dart';
import 'package:flutter_app/src/screens/login_screen.dart';

void main() {
  testWidgets('login form validates required fields', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pump();

    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('login form validates email format', (tester) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
    await tester.enterText(find.byType(TextFormField).last, 'password');
    await tester.ensureVisible(find.text('Sign in').last);
    await tester.tap(find.text('Sign in').last);
    await tester.pump();

    expect(find.text('Enter a valid email.'), findsOneWidget);
  });
}

Widget _buildTestApp() {
  return const ProviderScope(
    child: MaterialApp(
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: LoginScreen(),
    ),
  );
}
