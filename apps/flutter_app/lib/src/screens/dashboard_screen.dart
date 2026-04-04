import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models.dart';
import '../providers.dart';

const List<String> _timezoneOptions = <String>[
  'Etc/UTC',
  'Asia/Dubai',
  'Europe/London',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
];

const Map<String, String> _genderOptions = <String, String>{
  'male': 'Male',
  'female': 'Female',
  'other': 'Other',
  'prefer_not_to_say': 'Prefer not to say',
};

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
    final canManageUsers = role == 'admin' || role == 'supervisor';

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
              gender: input.gender,
              phoneNumber: input.phoneNumber,
              emergencyContactName: input.emergencyContactName,
              emergencyContactPhone: input.emergencyContactPhone,
              address: input.address,
              notes: input.notes,
              riskFlags: input.riskFlags,
              diagnosis: input.diagnosis,
              allergies: input.allergies,
              initialHealthCheckAt: input.initialHealthCheckAt,
              initialWeightKg: input.initialWeightKg,
              initialTemperatureC: input.initialTemperatureC,
              initialBloodPressureSystolic: input.initialBloodPressureSystolic,
              initialBloodPressureDiastolic:
                  input.initialBloodPressureDiastolic,
              initialPulseBpm: input.initialPulseBpm,
              initialSpo2Pct: input.initialSpo2Pct,
              initialHealthCheckNotes: input.initialHealthCheckNotes,
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
        title: const Text('HNAS Dashboard'),
        actions: <Widget>[
          if (profile?.displayName != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Chip(
                  avatar: const Icon(Icons.verified_user_outlined, size: 16),
                  label: Text('${profile!.displayName} • $role'),
                ),
              ),
            ),
          if (canManagePatients)
            IconButton(
              tooltip: 'Add patient',
              onPressed: openCreatePatientDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          if (canManageUsers)
            IconButton(
              tooltip: 'Manage users',
              onPressed: () => context.push('/users'),
              icon: const Icon(Icons.manage_accounts_outlined),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: <Widget>[
          _DashboardHero(
            role: role,
            canManagePatients: canManagePatients,
            onAddPatient: openCreatePatientDialog,
            canManageUsers: canManageUsers,
            onManageUsers: () => context.push('/users'),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: buildCountsContent(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text(
                'Patient Directory',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              Text(
                'Tap a patient to open details',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          buildPatientsContent(),
        ],
      ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.role,
    required this.canManagePatients,
    required this.onAddPatient,
    required this.canManageUsers,
    required this.onManageUsers,
  });

  final String role;
  final bool canManagePatients;
  final VoidCallback onAddPatient;
  final bool canManageUsers;
  final VoidCallback onManageUsers;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            colorScheme.primary,
            colorScheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Care Operations',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Role: $role',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              if (canManagePatients)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.onPrimary,
                    foregroundColor: colorScheme.primary,
                  ),
                  onPressed: onAddPatient,
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New Patient Intake'),
                ),
              if (canManageUsers)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.onPrimary,
                    side: BorderSide(
                      color: colorScheme.onPrimary.withValues(alpha: 0.65),
                    ),
                  ),
                  onPressed: onManageUsers,
                  icon: const Icon(Icons.manage_accounts_outlined),
                  label: const Text('Manage Users'),
                ),
            ],
          ),
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
        _CountTile(
          label: 'Patients',
          value: counts.totalPatients.toString(),
          icon: Icons.people_alt_outlined,
        ),
        _CountTile(
          label: 'Done',
          value: counts.done.toString(),
          icon: Icons.check_circle_outline,
        ),
        _CountTile(
          label: 'Missed',
          value: counts.missed.toString(),
          icon: Icons.error_outline,
        ),
        _CountTile(
          label: 'Late',
          value: counts.late.toString(),
          icon: Icons.schedule_outlined,
        ),
        _CountTile(
          label: 'Skipped',
          value: counts.skipped.toString(),
          icon: Icons.skip_next_outlined,
        ),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 142,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
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

    final dateOfBirth = patient.dateOfBirth;
    final ageText = dateOfBirth == null ? null : _formatAge(dateOfBirth);
    final info = <String>[
      if (patient.gender != null) _displayGender(patient.gender!),
      if (ageText != null) ageText,
      if (patient.phoneNumber != null) patient.phoneNumber!,
    ];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: patient.active
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.grey.shade300,
        child: Text(patient.fullName.isEmpty ? '?' : patient.fullName[0]),
      ),
      title: Text(patient.fullName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (info.isNotEmpty) Text(info.join(' • ')),
          Text(subtitleParts.join(' | ')),
        ],
      ),
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
    this.gender,
    this.phoneNumber,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.address,
    this.notes,
    this.riskFlags = const <String>[],
    this.diagnosis = const <String>[],
    this.allergies = const <String>[],
    this.initialHealthCheckAt,
    this.initialWeightKg,
    this.initialTemperatureC,
    this.initialBloodPressureSystolic,
    this.initialBloodPressureDiastolic,
    this.initialPulseBpm,
    this.initialSpo2Pct,
    this.initialHealthCheckNotes,
    this.agencyId,
    this.assignedNurseIds = const <String>[],
  });

  final String fullName;
  final String timezone;
  final bool active;
  final String? dateOfBirth;
  final String? gender;
  final String? phoneNumber;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? address;
  final String? notes;
  final List<String> riskFlags;
  final List<String> diagnosis;
  final List<String> allergies;
  final DateTime? initialHealthCheckAt;
  final num? initialWeightKg;
  final num? initialTemperatureC;
  final num? initialBloodPressureSystolic;
  final num? initialBloodPressureDiastolic;
  final num? initialPulseBpm;
  final num? initialSpo2Pct;
  final String? initialHealthCheckNotes;
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
  late final TextEditingController _dateOfBirthController;
  late final TextEditingController _agencyIdController;
  late final TextEditingController _assignedNursesController;
  late final TextEditingController _phoneNumberController;
  late final TextEditingController _emergencyNameController;
  late final TextEditingController _emergencyPhoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _riskFlagsController;
  late final TextEditingController _diagnosisController;
  late final TextEditingController _allergiesController;
  late final TextEditingController _notesController;
  late final TextEditingController _weightController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _systolicController;
  late final TextEditingController _diastolicController;
  late final TextEditingController _pulseController;
  late final TextEditingController _spo2Controller;
  late final TextEditingController _healthCheckNotesController;
  late String _timezone;
  String? _gender;
  DateTime? _initialHealthCheckAt;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _dateOfBirthController = TextEditingController();
    _agencyIdController = TextEditingController(
      text: widget.initialAgencyId ?? '',
    );
    _assignedNursesController = TextEditingController();
    _phoneNumberController = TextEditingController();
    _emergencyNameController = TextEditingController();
    _emergencyPhoneController = TextEditingController();
    _addressController = TextEditingController();
    _riskFlagsController = TextEditingController();
    _diagnosisController = TextEditingController();
    _allergiesController = TextEditingController();
    _notesController = TextEditingController();
    _weightController = TextEditingController();
    _temperatureController = TextEditingController();
    _systolicController = TextEditingController();
    _diastolicController = TextEditingController();
    _pulseController = TextEditingController();
    _spo2Controller = TextEditingController();
    _healthCheckNotesController = TextEditingController();
    _timezone = _timezoneOptions.first;
    _initialHealthCheckAt = DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateOfBirthController.dispose();
    _agencyIdController.dispose();
    _assignedNursesController.dispose();
    _phoneNumberController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _addressController.dispose();
    _riskFlagsController.dispose();
    _diagnosisController.dispose();
    _allergiesController.dispose();
    _notesController.dispose();
    _weightController.dispose();
    _temperatureController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _healthCheckNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final healthCheckLabel = _initialHealthCheckAt == null
        ? 'Now'
        : _formatDateTime(_initialHealthCheckAt!);

    return AlertDialog(
      title: const Text('New Patient Intake'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Basic Details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Full name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender (optional)',
                    prefixIcon: Icon(Icons.wc_outlined),
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    ..._genderOptions.entries.map(
                      (entry) => DropdownMenuItem<String?>(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _gender = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _timezone,
                  decoration: const InputDecoration(
                    labelText: 'Timezone',
                    prefixIcon: Icon(Icons.schedule_outlined),
                  ),
                  items: _timezoneOptions
                      .map(
                        (timezone) => DropdownMenuItem<String>(
                          value: timezone,
                          child: Text(timezone),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _timezone = value;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dateOfBirthController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Date of Birth (optional)',
                    hintText: 'YYYY-MM-DD',
                    prefixIcon: Icon(Icons.cake_outlined),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: _selectDateOfBirth,
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
                Text(
                  'Contact',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phoneNumberController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number (optional)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emergencyNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Emergency Contact Name (optional)',
                    prefixIcon: Icon(Icons.contact_emergency_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emergencyPhoneController,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Emergency Contact Phone (optional)',
                    prefixIcon: Icon(Icons.phone_forwarded_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  textInputAction: TextInputAction.next,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Address (optional)',
                    prefixIcon: Icon(Icons.home_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Clinical Context',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _diagnosisController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Diagnosis (optional)',
                    hintText: 'diabetes, hypertension',
                    prefixIcon: Icon(Icons.medical_services_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _riskFlagsController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Risk Flags (optional)',
                    hintText: 'fall risk, low appetite',
                    prefixIcon: Icon(Icons.warning_amber_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _allergiesController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Allergies (optional)',
                    hintText: 'penicillin, peanuts',
                    prefixIcon: Icon(Icons.coronavirus_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  textInputAction: TextInputAction.next,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    prefixIcon: Icon(Icons.sticky_note_2_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Initial Health Check (optional)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Recorded at: $healthCheckLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _selectInitialHealthCheckDate,
                      icon: const Icon(Icons.event_outlined),
                      label: const Text('Select Date'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _selectInitialHealthCheckTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('Select Time'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _weightController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Weight (kg)',
                        ),
                        validator: (value) => _validateNumber(value, min: 0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _temperatureController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Temperature (C)',
                        ),
                        validator: (value) => _validateNumber(value, min: 25),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _systolicController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'BP Systolic',
                        ),
                        validator: (value) {
                          final diastolic = _diastolicController.text.trim();
                          final raw = (value ?? '').trim();
                          if (raw.isEmpty && diastolic.isEmpty) {
                            return null;
                          }
                          if (raw.isEmpty || diastolic.isEmpty) {
                            return 'Enter both BP values.';
                          }
                          return _validateNumber(raw, min: 40);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolicController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'BP Diastolic',
                        ),
                        validator: (value) {
                          final systolic = _systolicController.text.trim();
                          final raw = (value ?? '').trim();
                          if (raw.isEmpty && systolic.isEmpty) {
                            return null;
                          }
                          if (raw.isEmpty || systolic.isEmpty) {
                            return 'Enter both BP values.';
                          }
                          return _validateNumber(raw, min: 30);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _pulseController,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Pulse (bpm)',
                        ),
                        validator: (value) => _validateNumber(value, min: 20),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _spo2Controller,
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'SpO2 (%)',
                        ),
                        validator: (value) =>
                            _validateNumber(value, min: 40, max: 100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _healthCheckNotesController,
                  minLines: 1,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Health Check Notes (optional)',
                  ),
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
          child: const Text('Create Patient'),
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
    final weightKg = _readOptionalNumber(_weightController);
    final temperatureC = _readOptionalNumber(_temperatureController);
    final bloodPressureSystolic = _readOptionalNumber(_systolicController);
    final bloodPressureDiastolic = _readOptionalNumber(_diastolicController);
    final pulseBpm = _readOptionalNumber(_pulseController);
    final spo2Pct = _readOptionalNumber(_spo2Controller);

    if (bloodPressureSystolic != null &&
        bloodPressureDiastolic != null &&
        bloodPressureSystolic <= bloodPressureDiastolic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Blood pressure systolic must be higher than diastolic.'),
        ),
      );
      return;
    }

    final hasInitialHealthMetrics = weightKg != null ||
        temperatureC != null ||
        bloodPressureSystolic != null ||
        bloodPressureDiastolic != null ||
        pulseBpm != null ||
        spo2Pct != null;
    final healthCheckNotes = _healthCheckNotesController.text.trim();

    Navigator.of(context).pop(
      _CreatePatientInput(
        fullName: _nameController.text.trim(),
        timezone: _timezone,
        active: _active,
        dateOfBirth: dateOfBirth.isEmpty ? null : dateOfBirth,
        gender: _gender,
        phoneNumber: _emptyToNull(_phoneNumberController.text),
        emergencyContactName: _emptyToNull(_emergencyNameController.text),
        emergencyContactPhone: _emptyToNull(_emergencyPhoneController.text),
        address: _emptyToNull(_addressController.text),
        notes: _emptyToNull(_notesController.text),
        riskFlags: _splitCsv(_riskFlagsController.text),
        diagnosis: _splitCsv(_diagnosisController.text),
        allergies: _splitCsv(_allergiesController.text),
        initialHealthCheckAt: hasInitialHealthMetrics
            ? _initialHealthCheckAt ?? DateTime.now()
            : null,
        initialWeightKg: weightKg,
        initialTemperatureC: temperatureC,
        initialBloodPressureSystolic: bloodPressureSystolic,
        initialBloodPressureDiastolic: bloodPressureDiastolic,
        initialPulseBpm: pulseBpm,
        initialSpo2Pct: spo2Pct,
        initialHealthCheckNotes:
            hasInitialHealthMetrics && healthCheckNotes.isNotEmpty
                ? healthCheckNotes
                : null,
        agencyId: agencyId.isEmpty ? null : agencyId,
        assignedNurseIds: assignedNurseIds,
      ),
    );
  }

  Future<void> _selectDateOfBirth() async {
    final initial = _dateOfBirthController.text.trim().isEmpty
        ? DateTime.now()
        : DateTime.tryParse('${_dateOfBirthController.text.trim()}T00:00:00') ??
            DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Select Date Of Birth',
    );
    if (picked == null) {
      return;
    }

    _dateOfBirthController.text = _formatDateId(picked);
  }

  Future<void> _selectInitialHealthCheckDate() async {
    final initial = _initialHealthCheckAt ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Select Health Check Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      final existing = _initialHealthCheckAt ?? DateTime.now();
      _initialHealthCheckAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        existing.hour,
        existing.minute,
      );
    });
  }

  Future<void> _selectInitialHealthCheckTime() async {
    final initial = _initialHealthCheckAt ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Select Health Check Time',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      final existing = _initialHealthCheckAt ?? DateTime.now();
      _initialHealthCheckAt = DateTime(
        existing.year,
        existing.month,
        existing.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  bool _isValidDateId(String value) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!pattern.hasMatch(value)) {
      return false;
    }
    return DateTime.tryParse('${value}T00:00:00Z') != null;
  }

  String? _validateNumber(String? value, {required num min, num? max}) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }

    final parsed = num.tryParse(raw);
    if (parsed == null) {
      return 'Enter a valid number.';
    }
    if (parsed < min) {
      return 'Must be at least $min.';
    }
    if (max != null && parsed > max) {
      return 'Must be at most $max.';
    }
    return null;
  }

  num? _readOptionalNumber(TextEditingController controller) {
    final raw = controller.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return num.tryParse(raw);
  }

  String? _emptyToNull(String value) {
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  List<String> _splitCsv(String raw) {
    return raw
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }
}

String _formatDateId(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatDateTime(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '${date.year}-$month-$day $hour:$minute';
}

String _displayGender(String gender) {
  final label = _genderOptions[gender.trim().toLowerCase()];
  return label ?? gender;
}

String? _formatAge(String dateOfBirth) {
  final date = DateTime.tryParse('${dateOfBirth.trim()}T00:00:00');
  if (date == null) {
    return null;
  }

  final now = DateTime.now();
  var age = now.year - date.year;
  if (now.month < date.month ||
      (now.month == date.month && now.day < date.day)) {
    age -= 1;
  }
  if (age < 0) {
    return null;
  }
  return '$age yrs';
}
