import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models.dart';
import '../providers.dart';

class CarePortalScreen extends ConsumerStatefulWidget {
  const CarePortalScreen({super.key});

  @override
  ConsumerState<CarePortalScreen> createState() => _CarePortalScreenState();
}

class _CarePortalScreenState extends ConsumerState<CarePortalScreen> {
  String? _selectedPatientId;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final patientsAsync = ref.watch(patientsStreamProvider);
    final isRelative = profile?.role == 'relative';

    return Scaffold(
      appBar: AppBar(
        title: Text(isRelative ? 'Family care' : 'My care'),
        actions: <Widget>[
          PopupMenuButton<String>(
            tooltip: 'Language',
            icon: const Icon(Icons.language_rounded),
            onSelected: (code) {
              ref.read(localeProvider.notifier).setLocale(Locale(code));
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ar', child: Text('العربية')),
            ],
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: patientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _PortalMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Unable to load care information',
          message: '$error',
          onRetry: () => ref.invalidate(patientsStreamProvider),
        ),
        data: (patients) {
          if (patients.isEmpty) {
            return const _PortalMessage(
              icon: Icons.person_search_outlined,
              title: 'No patient is linked to this account',
              message: 'Ask the care agency to check your account access.',
            );
          }

          final selectedId = patients.any((p) => p.id == _selectedPatientId)
              ? _selectedPatientId!
              : patients.first.id;
          final patient = patients.firstWhere((p) => p.id == selectedId);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(patientsStreamProvider);
              ref.invalidate(medicinesProvider(patient.id));
              ref.invalidate(
                checklistProvider(
                  ChecklistQuery(
                    patientId: patient.id,
                    dateId: ref.read(todayDateIdProvider),
                  ),
                ),
              );
              ref.invalidate(reportsProvider(patient.id));
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _WelcomeCard(
                          displayName: profile?.displayName ?? '',
                          patient: patient,
                          isRelative: isRelative,
                        ),
                        if (patients.length > 1) ...<Widget>[
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            initialValue: selectedId,
                            decoration: const InputDecoration(
                              labelText: 'Viewing care for',
                              prefixIcon: Icon(Icons.people_outline_rounded),
                            ),
                            items: patients
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item.id,
                                    child: Text(item.fullName),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _selectedPatientId = value);
                              }
                            },
                          ),
                        ],
                        const SizedBox(height: 14),
                        _SafetyCard(patient: patient),
                        const SizedBox(height: 14),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 760;
                            final care = _TodayCareCard(patientId: patient.id);
                            final medicines = _MedicationCard(
                              patientId: patient.id,
                            );
                            if (!wide) {
                              return Column(
                                children: <Widget>[
                                  care,
                                  const SizedBox(height: 14),
                                  medicines,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(child: care),
                                const SizedBox(width: 14),
                                Expanded(child: medicines),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        _ReportsCard(patientId: patient.id),
                        const SizedBox(height: 14),
                        const _PrivacyNotice(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.displayName,
    required this.patient,
    required this.isRelative,
  });

  final String displayName;
  final PatientModel patient;
  final bool isRelative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, const Color(0xFF00838F)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isRelative
                  ? Icons.family_restroom_rounded
                  : Icons.favorite_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  displayName.isEmpty ? 'Welcome' : 'Welcome, $displayName',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  isRelative
                      ? 'A clear, read-only view of ${patient.fullName}\'s care.'
                      : 'Your care plan and today\'s progress in one place.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                ),
              ],
            ),
          ),
          Chip(
            avatar: Icon(
              patient.active ? Icons.check_circle_outline : Icons.pause_circle,
              size: 18,
            ),
            label: Text(patient.active ? 'Active care' : 'Care paused'),
          ),
        ],
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard({required this.patient});

  final PatientModel patient;

  @override
  Widget build(BuildContext context) {
    final warnings = <String>{...patient.allergies, ...patient.riskFlags};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const _SectionTitle(
              icon: Icons.health_and_safety_outlined,
              title: 'Care profile',
              subtitle: 'Important information shared by the care team',
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (patient.diagnosis.isNotEmpty)
                  ...patient.diagnosis.map(
                    (item) => Chip(
                      avatar: const Icon(Icons.medical_information_outlined),
                      label: Text(item),
                    ),
                  ),
                if (warnings.isEmpty)
                  const Chip(
                    avatar: Icon(Icons.check_circle_outline),
                    label: Text('No safety alerts recorded'),
                  )
                else
                  ...warnings.map(
                    (item) => Chip(
                      avatar: const Icon(Icons.warning_amber_rounded),
                      label: Text(item),
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .errorContainer
                          .withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayCareCard extends ConsumerWidget {
  const _TodayCareCard({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateId = ref.watch(todayDateIdProvider);
    final checklistAsync = ref.watch(
      checklistProvider(ChecklistQuery(patientId: patientId, dateId: dateId)),
    );
    return _PortalCard(
      title: "Today's care",
      subtitle: 'Live progress from the care team',
      icon: Icons.today_outlined,
      child: checklistAsync.when(
        loading: () => const _CardLoading(),
        error: (error, _) => Text('Unable to load today\'s care: $error'),
        data: (checklist) {
          if (checklist == null || checklist.tasks.isEmpty) {
            return const Text('No care tasks are scheduled today.');
          }
          final resultById = checklist.resultByTaskId();
          final complete = checklist.tasks
              .where((task) => resultById[task.id]?.status == 'done')
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: LinearProgressIndicator(
                      value: complete / checklist.tasks.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '$complete/${checklist.tasks.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...checklist.tasks.map((task) {
                final status = resultById[task.id]?.status ?? 'pending';
                final done = status == 'done';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    done ? Icons.check_circle_rounded : Icons.schedule_rounded,
                    color: done
                        ? Colors.green.shade700
                        : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(task.title),
                  subtitle: task.scheduledTime == null
                      ? null
                      : Text(task.scheduledTime!),
                  trailing: Text(_statusLabel(status)),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _MedicationCard extends ConsumerWidget {
  const _MedicationCard({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final medicinesAsync = ref.watch(medicinesProvider(patientId));
    return _PortalCard(
      title: 'Medications',
      subtitle: 'Current information from the approved care plan',
      icon: Icons.medication_outlined,
      child: medicinesAsync.when(
        loading: () => const _CardLoading(),
        error: (error, _) => Text('Unable to load medications: $error'),
        data: (medicines) {
          final active = medicines.where((item) => item.active).toList();
          if (active.isEmpty) {
            return const Text('No active medications listed.');
          }
          return Column(
            children: active
                .map(
                  (medicine) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.medication_rounded),
                    ),
                    title: Text(medicine.name),
                    subtitle: Text(
                      <String>[
                        if (medicine.doseAmount != null)
                          '${medicine.doseAmount} ${medicine.doseUnit ?? ''}'
                              .trim(),
                        if (medicine.scheduleTimes.isNotEmpty)
                          medicine.scheduleTimes.join(', '),
                      ].join(' • '),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _ReportsCard extends ConsumerWidget {
  const _ReportsCard({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(reportsProvider(patientId));
    return _PortalCard(
      title: 'Recent care summaries',
      subtitle: 'The latest daily activity shared by the care team',
      icon: Icons.insights_outlined,
      child: reportsAsync.when(
        loading: () => const _CardLoading(),
        error: (error, _) => Text('Unable to load care summaries: $error'),
        data: (reports) {
          if (reports.isEmpty) {
            return const Text('No daily summaries have been published yet.');
          }
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: reports.take(7).map((report) {
              return Container(
                width: 190,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      report.dateId,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text('${report.done} completed • ${report.missed} missed'),
                    Text('${report.late} late • ${report.skipped} skipped'),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  const _PortalCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _SectionTitle(icon: icon, title: title, subtitle: subtitle),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(
          Icons.lock_outline_rounded,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'This is a private, read-only view. Contact the care team for changes or urgent concerns.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CardLoading extends StatelessWidget {
  const _CardLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(18),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _PortalMessage extends StatelessWidget {
  const _PortalMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'done':
      return 'Done';
    case 'skipped':
      return 'Skipped';
    case 'failed':
      return 'Needs attention';
    case 'late':
      return 'Late';
    default:
      return 'Pending';
  }
}
