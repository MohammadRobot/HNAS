import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_localizations.dart';
import '../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      setState(() => _errorMessage = l.signInTimeout);
    } on FirebaseAuthException catch (error) {
      setState(() => _errorMessage = error.message ?? l.unableToSignIn);
    } catch (_) {
      setState(() => _errorMessage = l.unableToSignIn);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters(<String, String>{'prompt': 'select_account'});

      if (!kIsWeb) {
        throw FirebaseAuthException(
          code: 'operation-not-supported',
          message: l.googleSignInWebOnly,
        );
      }

      await FirebaseAuth.instance
          .signInWithPopup(provider)
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      setState(() => _errorMessage = l.googleSignInTimeout);
    } on FirebaseAuthException catch (error) {
      setState(
          () => _errorMessage = error.message ?? l.unableToSignInWithGoogle);
    } catch (_) {
      setState(() => _errorMessage = l.unableToSignInWithGoogle);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInDemo(String email) async {
    _emailController.text = email;
    _passwordController.text = 'Passw0rd!';
    await _signIn();
  }

  void _toggleLocale() {
    final current = ref.read(localeProvider);
    ref.read(localeProvider.notifier).setLocale(
          current.languageCode == 'en'
              ? const Locale('ar')
              : const Locale('en'),
        );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colorScheme.primary,
                  const Color(0xFF0D47A1),
                  colorScheme.secondary.withValues(alpha: 0.85),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // ── Subtle pattern overlay ─────────────────────────────────────
          Positioned.fill(
            child: Opacity(
              opacity: 0.04,
              child: Image.network(
                '',
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),

          // ── Language toggle (top-right) ────────────────────────────────
          SafeArea(
            child: Align(
              alignment: l.isRtl ? Alignment.topLeft : Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _LanguageToggleButton(
                  label: l.isRtl ? l.languageEnglish : l.languageArabic,
                  onTap: _toggleLocale,
                ),
              ),
            ),
          ),

          // ── Main card ─────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 80,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Brand header ─────────────────────────────────
                      _BrandHeader(l: l),
                      const SizedBox(height: 32),

                      // ── Form card ────────────────────────────────────
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(28),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l.signIn,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.onSurface,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l.appTagline,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Email field
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                textDirection: TextDirection.ltr,
                                autofillHints: const [AutofillHints.email],
                                decoration: InputDecoration(
                                  labelText: l.email,
                                  prefixIcon: const Icon(
                                    Icons.alternate_email_rounded,
                                  ),
                                ),
                                validator: (value) {
                                  final input = value?.trim() ?? '';
                                  if (input.isEmpty) {
                                    return l.emailRequired;
                                  }
                                  if (!input.contains('@')) {
                                    return l.emailInvalid;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 14),

                              // Password field
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                decoration: InputDecoration(
                                  labelText: l.password,
                                  prefixIcon: const Icon(
                                    Icons.lock_outline_rounded,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () => setState(
                                      () =>
                                          _obscurePassword = !_obscurePassword,
                                    ),
                                  ),
                                ),
                                validator: (value) {
                                  if ((value ?? '').isEmpty) {
                                    return l.passwordRequired;
                                  }
                                  return null;
                                },
                              ),

                              // Error banner
                              if (_errorMessage != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.error_outline_rounded,
                                        size: 18,
                                        color: colorScheme.error,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: colorScheme.onErrorContainer,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 20),

                              // Sign-in button
                              FilledButton.icon(
                                onPressed: _loading ? null : _signIn,
                                icon: _loading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                  _loading ? l.signingIn : l.signIn,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Divider
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'or',
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Google sign-in
                              OutlinedButton.icon(
                                onPressed: _loading ? null : _signInWithGoogle,
                                icon: const Icon(Icons.account_circle_outlined),
                                label: Text(l.signInWithGoogle),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Demo portal access',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose a view to sign in with the local demo account.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: <Widget>[
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () => _signInDemo(
                                                'patient@hnas.local',
                                              ),
                                      icon: const Icon(
                                        Icons.favorite_outline_rounded,
                                      ),
                                      label: const Text('Patient'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _loading
                                          ? null
                                          : () => _signInDemo(
                                                'relative@hnas.local',
                                              ),
                                      icon: const Icon(
                                        Icons.family_restroom_rounded,
                                      ),
                                      label: const Text('Relative'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Brand header above the card ───────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo circle
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.local_hospital_rounded,
            size: 36,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l.appTitle,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.appFullName,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

// ── Language toggle chip ──────────────────────────────────────────────────────

class _LanguageToggleButton extends StatelessWidget {
  const _LanguageToggleButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language_rounded, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
