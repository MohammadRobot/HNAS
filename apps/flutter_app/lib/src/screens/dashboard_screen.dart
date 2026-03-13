import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models.dart';
import '../providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final patientsAsync = ref.watch(patientsStreamProvider);
    final countsAsync = ref.watch(dashboardCountsProvider);
    final uid = ref.watch(currentUserIdProvider);

    final profile = profileAsync.value;
    final role = profile?.role ?? 'unknown';

    void refreshDashboardData() {
      ref.invalidate(userProfileProvider);
      ref.invalidate(patientsStreamProvider);
      ref.invalidate(dashboardCountsProvider);
    }

    Widget buildCountsContent() {
      if (profileAsync.isLoading) {
        return const _LoadingBlock(height: 70);
      }

      if (profileAsync.hasError) {
        return _NoticeCard(
          message: 'Unable to load user profile: ${profileAsync.error}',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        );
      }

      if (profile == null) {
        return _NoticeCard(
          message:
              'No user profile found at /users/$uid. Seed demo data or create this document.',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        );
      }

      return countsAsync.when(
        data: (counts) => _DashboardCountsRow(counts: counts),
        loading: () => const _LoadingBlock(height: 70),
        error: (error, _) => _NoticeCard(
          message: 'Unable to load counts: $error',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        ),
      );
    }

    Widget buildPatientsContent() {
      if (profileAsync.isLoading) {
        return const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: _LoadingBlock(height: 90),
          ),
        );
      }

      if (profileAsync.hasError) {
        return _NoticeCard(
          message: 'Unable to load user profile: ${profileAsync.error}',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        );
      }

      if (profile == null) {
        return _NoticeCard(
          message:
              'No user profile found at /users/$uid. Without this profile the patient list cannot be loaded.',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        );
      }

      return patientsAsync.when(
        data: (patients) {
          if (patients.isEmpty) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No patients available for role "$role".'),
              ),
            );
          }

          return Card(
            child: Column(
              children: patients
                  .map((patient) => _PatientTile(patient: patient))
                  .toList(),
            ),
          );
        },
        loading: () => const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: _LoadingBlock(height: 90),
          ),
        ),
        error: (error, _) => _NoticeCard(
          message: 'Unable to load patients: $error',
          actionLabel: 'Retry',
          onAction: refreshDashboardData,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: <Widget>[
          if (profile?.displayName != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Chip(
                label: Text('${profile!.displayName} ($role)'),
              ),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: refreshDashboardData,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: buildCountsContent(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Patients',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          buildPatientsContent(),
        ],
      ),
    );
  }
}

class _DashboardCountsRow extends StatelessWidget {
  const _DashboardCountsRow({required this.counts});

  final DashboardCounts counts;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        _CountTile(label: 'Patients', value: counts.totalPatients.toString()),
        _CountTile(label: 'Done', value: counts.done.toString()),
        _CountTile(label: 'Missed', value: counts.missed.toString()),
        _CountTile(label: 'Late', value: counts.late.toString()),
        _CountTile(label: 'Skipped', value: counts.skipped.toString()),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient});

  final PatientModel patient;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[];
    if (patient.diagnosis.isNotEmpty) {
      subtitleParts.add(patient.diagnosis.join(', '));
    }
    if (patient.riskFlags.isNotEmpty) {
      subtitleParts.add('Risk: ${patient.riskFlags.join(', ')}');
    }
    if (subtitleParts.isEmpty) {
      subtitleParts.add('No diagnosis/risk flags recorded');
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: patient.active ? null : Colors.grey.shade300,
        child: Text(patient.fullName.isEmpty ? '?' : patient.fullName[0]),
      ),
      title: Text(patient.fullName),
      subtitle: Text(subtitleParts.join(' | ')),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push('/patient/${patient.id}'),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final showAction = actionLabel != null && onAction != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message),
            if (showAction) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
