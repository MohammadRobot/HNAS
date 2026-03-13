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
    final canManagePatients = role == 'admin' || role == 'supervisor';

    void refreshDashboardData() {
      ref.invalidate(userProfileProvider);
      ref.invalidate(patientsStreamProvider);
      ref.invalidate(dashboardCountsProvider);
    }

    Future<void> openCreatePatientDialog() async {
      if (profile == null) {
        return;
      }

      final input = await showDialog<_CreatePatientInput>(
        context: context,
        builder: (dialogContext) => _CreatePatientDialog(
          initialAgencyId: profile.agencyId,
          canEditAgencyId: role == 'admin',
        ),
      );

      if (input == null) {
        return;
      }

      try {
        final patientId = await ref.read(apiClientProvider).createPatient(
              fullName: input.fullName,
              timezone: input.timezone,
              active: input.active,
              dateOfBirth: input.dateOfBirth,
              agencyId: input.agencyId,
              assignedNurseIds: input.assignedNurseIds,
            );

        refreshDashboardData();

        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient created successfully.')),
        );
        context.push('/patient/$patientId');
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create patient: $error')),
        );
      }
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
          if (canManagePatients)
            IconButton(
              tooltip: 'Add patient',
              onPressed: openCreatePatientDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
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

class _CreatePatientInput {
  const _CreatePatientInput({
    required this.fullName,
    required this.timezone,
    required this.active,
    this.dateOfBirth,
    this.agencyId,
    this.assignedNurseIds = const <String>[],
  });

  final String fullName;
  final String timezone;
  final bool active;
  final String? dateOfBirth;
  final String? agencyId;
  final List<String> assignedNurseIds;
}

class _CreatePatientDialog extends StatefulWidget {
  const _CreatePatientDialog({
    required this.initialAgencyId,
    required this.canEditAgencyId,
  });

  final String? initialAgencyId;
  final bool canEditAgencyId;

  @override
  State<_CreatePatientDialog> createState() => _CreatePatientDialogState();
}

class _CreatePatientDialogState extends State<_CreatePatientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _timezoneController;
  late final TextEditingController _dateOfBirthController;
  late final TextEditingController _agencyIdController;
  late final TextEditingController _assignedNursesController;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _timezoneController = TextEditingController(text: 'Etc/UTC');
    _dateOfBirthController = TextEditingController();
    _agencyIdController = TextEditingController(
      text: widget.initialAgencyId ?? '',
    );
    _assignedNursesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _timezoneController.dispose();
    _dateOfBirthController.dispose();
    _agencyIdController.dispose();
    _assignedNursesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Patient'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _timezoneController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    hintText: 'Etc/UTC',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Timezone is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dateOfBirthController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth (optional)',
                    hintText: 'YYYY-MM-DD',
                  ),
                  validator: (value) {
                    final raw = (value ?? '').trim();
                    if (raw.isEmpty) {
                      return null;
                    }
                    if (!_isValidDateId(raw)) {
                      return 'Use YYYY-MM-DD format.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _assignedNursesController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Assigned Nurse UIDs (optional)',
                    hintText: 'uid-1, uid-2',
                  ),
                ),
                if (widget.canEditAgencyId) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _agencyIdController,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Agency ID',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Agency ID is required.';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: _active,
                  onChanged: (value) {
                    setState(() {
                      _active = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final assignedNurseIds = _assignedNursesController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();

    final dateOfBirth = _dateOfBirthController.text.trim();
    final agencyId = _agencyIdController.text.trim();

    Navigator.of(context).pop(
      _CreatePatientInput(
        fullName: _nameController.text.trim(),
        timezone: _timezoneController.text.trim(),
        active: _active,
        dateOfBirth: dateOfBirth.isEmpty ? null : dateOfBirth,
        agencyId: agencyId.isEmpty ? null : agencyId,
        assignedNurseIds: assignedNurseIds,
      ),
    );
  }

  bool _isValidDateId(String value) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!pattern.hasMatch(value)) {
      return false;
    }
    return DateTime.tryParse('${value}T00:00:00Z') != null;
  }
}
