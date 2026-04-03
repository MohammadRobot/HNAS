import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import '../services/insulin_preview.dart';

class PatientDetailsScreen extends ConsumerWidget {
  const PatientDetailsScreen({
    super.key,
    required this.patientId,
  });

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (patientId.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Invalid patient id.')),
      );
    }

    final patientAsync = ref.watch(patientProvider(patientId));

    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: patientAsync.when(
            data: (patient) => Text(patient?.fullName ?? 'Patient'),
            loading: () => const Text('Patient'),
            error: (_, __) => const Text('Patient'),
          ),
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Overview'),
              Tab(text: 'Medicines'),
              Tab(text: 'Procedures'),
              Tab(text: 'Insulin'),
              Tab(text: 'Checklist'),
              Tab(text: 'Health Checks'),
              Tab(text: 'Reports'),
              Tab(text: 'AI Assistant'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _OverviewTab(patientId: patientId),
            _MedicinesTab(patientId: patientId),
            _ProceduresTab(patientId: patientId),
            _InsulinTab(patientId: patientId),
            _ChecklistTab(patientId: patientId),
            _HealthChecksTab(patientId: patientId),
            _ReportsTab(patientId: patientId),
            _AiAssistantTab(patientId: patientId),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patientAsync = ref.watch(patientProvider(patientId));
    final todayReportAsync = ref.watch(todayReportProvider(patientId));
    final healthChecksAsync = ref.watch(healthChecksProvider(patientId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        patientAsync.when(
          data: (patient) {
            if (patient == null) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Patient not found.'),
                ),
              );
            }

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            patient.fullName,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        Chip(
                          label: Text(patient.active ? 'Active' : 'Inactive'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(
                        label: 'Timezone', value: patient.timezone ?? '-'),
                    _KeyValue(label: 'Agency', value: patient.agencyId ?? '-'),
                    _KeyValue(
                      label: 'Risk Flags',
                      value: patient.riskFlags.isEmpty
                          ? 'None'
                          : patient.riskFlags.join(', '),
                    ),
                    _KeyValue(
                      label: 'Diagnosis',
                      value: patient.diagnosis.isEmpty
                          ? 'None'
                          : patient.diagnosis.join(', '),
                    ),
                    _KeyValue(
                      label: 'Date of Birth',
                      value: patient.dateOfBirth ?? '-',
                    ),
                    _KeyValue(
                      label: 'Gender',
                      value: patient.gender == null
                          ? '-'
                          : _displayGender(patient.gender!),
                    ),
                    _KeyValue(
                      label: 'Phone',
                      value: patient.phoneNumber ?? '-',
                    ),
                    _KeyValue(
                      label: 'Emergency Contact',
                      value: [
                        if (patient.emergencyContactName != null)
                          patient.emergencyContactName!,
                        if (patient.emergencyContactPhone != null)
                          patient.emergencyContactPhone!,
                      ].isEmpty
                          ? '-'
                          : [
                              if (patient.emergencyContactName != null)
                                patient.emergencyContactName!,
                              if (patient.emergencyContactPhone != null)
                                patient.emergencyContactPhone!,
                            ].join(' • '),
                    ),
                    _KeyValue(
                      label: 'Address',
                      value: patient.address ?? '-',
                    ),
                    _KeyValue(
                      label: 'Allergies',
                      value: patient.allergies.isEmpty
                          ? 'None'
                          : patient.allergies.join(', '),
                    ),
                    _KeyValue(
                      label: 'Notes',
                      value: patient.notes ?? '-',
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const _LoadingCard(),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Unable to load patient: $error'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        healthChecksAsync.when(
          data: (checks) {
            if (checks.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No health checks yet. Use the Health Checks tab to record vitals.',
                  ),
                ),
              );
            }

            final latest = checks.first;
            final checkedAt = _formatIsoDateTime(latest.checkedAt);
            final bloodPressure = latest.bloodPressureSystolic != null &&
                    latest.bloodPressureDiastolic != null
                ? '${latest.bloodPressureSystolic}/${latest.bloodPressureDiastolic}'
                : '-';

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Latest Health Check',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(label: 'Checked At', value: checkedAt),
                    _KeyValue(
                      label: 'Weight',
                      value: latest.weightKg == null
                          ? '-'
                          : '${latest.weightKg} kg',
                    ),
                    _KeyValue(
                      label: 'Temperature',
                      value: latest.temperatureC == null
                          ? '-'
                          : '${latest.temperatureC} C',
                    ),
                    _KeyValue(label: 'Blood Pressure', value: bloodPressure),
                    _KeyValue(
                      label: 'Pulse',
                      value: latest.pulseBpm == null
                          ? '-'
                          : '${latest.pulseBpm} bpm',
                    ),
                    _KeyValue(
                      label: 'SpO2',
                      value:
                          latest.spo2Pct == null ? '-' : '${latest.spo2Pct}%',
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const _LoadingCard(),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Unable to load health checks: $error'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        todayReportAsync.when(
          data: (report) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: report == null
                  ? const Text('No daily report generated yet.')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Today Summary (${report.dateId})',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _StatChip(label: 'Done', value: report.done),
                            _StatChip(label: 'Missed', value: report.missed),
                            _StatChip(label: 'Late', value: report.late),
                            _StatChip(label: 'Skipped', value: report.skipped),
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          loading: () => const _LoadingCard(),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Unable to load daily report: $error'),
            ),
          ),
        ),
      ],
    );
  }
}

class _MedicinesTab extends ConsumerWidget {
  const _MedicinesTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        _canManageRecords(ref.watch(userProfileProvider).value?.role);
    final medicinesAsync = ref.watch(medicinesProvider(patientId));

    Future<void> createMedicine() async {
      final draft = await showDialog<_MedicineDraft>(
        context: context,
        builder: (_) => const _MedicineDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createMedicine(
              patientId: patientId,
              name: draft.name,
              instructions: draft.instructions,
              doseAmount: draft.doseAmount,
              doseUnit: draft.doseUnit,
              active: draft.active,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medicine added.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add medicine: $error')),
        );
      }
    }

    Future<void> editMedicine(MedicineModel medicine) async {
      final draft = await showDialog<_MedicineDraft>(
        context: context,
        builder: (_) => _MedicineDialog(initialValue: medicine),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).updateMedicine(
              patientId: patientId,
              medicineId: medicine.id,
              name: draft.name,
              instructions: draft.instructions,
              doseAmount: draft.doseAmount,
              doseUnit: draft.doseUnit,
              active: draft.active,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medicine updated.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update medicine: $error')),
        );
      }
    }

    return medicinesAsync.when(
      data: (medicines) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canManage)
              _TabActionHeader(
                label: 'Medicines',
                actionLabel: 'Add Medicine',
                onPressed: createMedicine,
              ),
            if (medicines.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No medicines.'),
                ),
              ),
            ...medicines.map((medicine) {
              final dose = medicine.doseAmount != null
                  ? '${medicine.doseAmount} ${medicine.doseUnit ?? ''}'.trim()
                  : '-';
              final schedule = medicine.scheduleTimes.isEmpty
                  ? '-'
                  : medicine.scheduleTimes.join(', ');

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                medicine.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (canManage)
                              IconButton(
                                tooltip: 'Edit medicine',
                                onPressed: () => editMedicine(medicine),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _KeyValue(label: 'Dose', value: dose),
                        _KeyValue(label: 'Schedule', value: schedule),
                        _KeyValue(
                          label: 'Instructions',
                          value: medicine.instructions ?? '-',
                        ),
                        _KeyValue(
                          label: 'Status',
                          value: medicine.active ? 'Active' : 'Inactive',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load medicines: $error')),
    );
  }
}

class _ProceduresTab extends ConsumerWidget {
  const _ProceduresTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        _canManageRecords(ref.watch(userProfileProvider).value?.role);
    final proceduresAsync = ref.watch(proceduresProvider(patientId));

    Future<void> createProcedure() async {
      final draft = await showDialog<_ProcedureDraft>(
        context: context,
        builder: (_) => const _ProcedureDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createProcedure(
              patientId: patientId,
              name: draft.name,
              instructions: draft.instructions,
              frequency: draft.frequency,
              active: draft.active,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Procedure added.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add procedure: $error')),
        );
      }
    }

    Future<void> editProcedure(ProcedureModel procedure) async {
      final draft = await showDialog<_ProcedureDraft>(
        context: context,
        builder: (_) => _ProcedureDialog(initialValue: procedure),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).updateProcedure(
              patientId: patientId,
              procedureId: procedure.id,
              name: draft.name,
              instructions: draft.instructions,
              frequency: draft.frequency,
              active: draft.active,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Procedure updated.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update procedure: $error')),
        );
      }
    }

    return proceduresAsync.when(
      data: (procedures) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canManage)
              _TabActionHeader(
                label: 'Procedures',
                actionLabel: 'Add Procedure',
                onPressed: createProcedure,
              ),
            if (procedures.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No procedures.'),
                ),
              ),
            ...procedures.map((procedure) {
              final schedule = procedure.scheduleTimes.isEmpty
                  ? '-'
                  : procedure.scheduleTimes.join(', ');

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                procedure.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (canManage)
                              IconButton(
                                tooltip: 'Edit procedure',
                                onPressed: () => editProcedure(procedure),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _KeyValue(
                            label: 'Frequency',
                            value: procedure.frequency ?? '-'),
                        _KeyValue(label: 'Schedule', value: schedule),
                        _KeyValue(
                          label: 'Instructions',
                          value: procedure.instructions ?? '-',
                        ),
                        _KeyValue(
                          label: 'Status',
                          value: procedure.active ? 'Active' : 'Inactive',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load procedures: $error')),
    );
  }
}

class _InsulinTab extends ConsumerWidget {
  const _InsulinTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage =
        _canManageRecords(ref.watch(userProfileProvider).value?.role);
    final profilesAsync = ref.watch(insulinProfilesProvider(patientId));

    Future<void> createInsulinProfile() async {
      final draft = await showDialog<_InsulinProfileDraft>(
        context: context,
        builder: (_) => const _InsulinProfileDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createInsulinProfile(
              patientId: patientId,
              type: draft.type,
              label: draft.label,
              insulinName: draft.insulinName,
              active: draft.active,
              slidingScaleMgdl: draft.slidingScaleMgdl,
              mealBaseUnits: draft.mealBaseUnits,
              defaultBaseUnits: draft.defaultBaseUnits,
              fixedUnits: draft.fixedUnits,
              notes: draft.notes,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insulin profile added.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add insulin profile: $error')),
        );
      }
    }

    Future<void> editInsulinProfile(InsulinProfileModel profile) async {
      final draft = await showDialog<_InsulinProfileDraft>(
        context: context,
        builder: (_) => _InsulinProfileDialog(initialValue: profile),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).updateInsulinProfile(
              patientId: patientId,
              insulinProfileId: profile.id,
              type: draft.type,
              label: draft.label,
              insulinName: draft.insulinName,
              active: draft.active,
              slidingScaleMgdl: draft.slidingScaleMgdl,
              mealBaseUnits: draft.mealBaseUnits,
              defaultBaseUnits: draft.defaultBaseUnits,
              fixedUnits: draft.fixedUnits,
              notes: draft.notes,
              scheduleTimes: draft.scheduleTimes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insulin profile updated.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update insulin profile: $error')),
        );
      }
    }

    return profilesAsync.when(
      data: (profiles) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canManage)
              _TabActionHeader(
                label: 'Insulin Profiles',
                actionLabel: 'Add Profile',
                onPressed: createInsulinProfile,
              ),
            if (profiles.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No insulin profiles.'),
                ),
              ),
            ...profiles.map((profile) {
              final typeLabel = profile.isRapid ? 'Rapid' : 'Basal';
              final scale = profile.slidingScaleMgdl.isEmpty
                  ? '-'
                  : profile.slidingScaleMgdl.join(', ');
              final mealBase = profile.mealBaseUnits.isEmpty
                  ? '-'
                  : profile.mealBaseUnits.entries
                      .map((entry) => '${entry.key}: ${entry.value}')
                      .join(', ');
              final schedule = profile.scheduleTimes.isEmpty
                  ? '-'
                  : profile.scheduleTimes.join(', ');

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                profile.label,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            Chip(label: Text(typeLabel)),
                            if (canManage)
                              IconButton(
                                tooltip: 'Edit profile',
                                onPressed: () => editInsulinProfile(profile),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _KeyValue(
                            label: 'Insulin',
                            value: profile.insulinName ?? '-'),
                        _KeyValue(label: 'Schedule', value: schedule),
                        if (profile.isRapid) ...<Widget>[
                          _KeyValue(
                              label: 'Sliding Scale (mg/dL)', value: scale),
                          _KeyValue(
                              label: 'Meal Base (units)', value: mealBase),
                          _KeyValue(
                            label: 'Default Base Units',
                            value: profile.defaultBaseUnits?.toString() ?? '-',
                          ),
                        ] else ...<Widget>[
                          _KeyValue(
                            label: 'Fixed Units',
                            value: profile.fixedUnits?.toString() ?? '-',
                          ),
                        ],
                        _KeyValue(label: 'Notes', value: profile.notes ?? '-'),
                        _KeyValue(
                          label: 'Status',
                          value: profile.active ? 'Active' : 'Inactive',
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load insulin profiles: $error')),
    );
  }
}

bool _canManageRecords(String? role) {
  return role == 'admin' || role == 'supervisor';
}

const List<String> _medicineDoseUnitOptions = <String>[
  'mg',
  'ml',
  'tablet',
  'capsule',
  'units',
];

const List<String> _procedureFrequencyOptions = <String>[
  'once',
  'daily',
  'weekly',
  'as_needed',
];

class _TabActionHeader extends StatelessWidget {
  const _TabActionHeader({
    required this.label,
    required this.actionLabel,
    required this.onPressed,
  });

  final String label;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.add_rounded),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MedicineDraft {
  const _MedicineDraft({
    required this.name,
    required this.instructions,
    required this.doseAmount,
    required this.doseUnit,
    required this.active,
    required this.scheduleTimes,
  });

  final String name;
  final String? instructions;
  final num? doseAmount;
  final String? doseUnit;
  final bool active;
  final List<String> scheduleTimes;
}

class _MedicineDialog extends StatefulWidget {
  const _MedicineDialog({
    this.initialValue,
  });

  final MedicineModel? initialValue;

  @override
  State<_MedicineDialog> createState() => _MedicineDialogState();
}

class _MedicineDialogState extends State<_MedicineDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;
  late final TextEditingController _doseAmountController;
  late String? _doseUnit;
  late final List<String> _scheduleTimes;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _instructionsController = TextEditingController(
      text: initial?.instructions ?? '',
    );
    _doseAmountController = TextEditingController(
      text: initial?.doseAmount?.toString() ?? '',
    );
    _doseUnit = initial?.doseUnit;
    _scheduleTimes = List<String>.from(initial?.scheduleTimes ?? <String>[])
      ..sort();
    _active = initial?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    _doseAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Medicine' : 'Add Medicine'),
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
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _doseAmountController,
                  textInputAction: TextInputAction.next,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Dose Amount (optional)',
                  ),
                  validator: (value) {
                    final raw = (value ?? '').trim();
                    if (raw.isEmpty) {
                      return null;
                    }
                    return num.tryParse(raw) == null
                        ? 'Enter a valid number.'
                        : null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _doseUnit,
                  decoration: const InputDecoration(
                    labelText: 'Dose Unit (optional)',
                  ),
                  items: _buildDoseUnitItems(),
                  onChanged: (value) {
                    setState(() {
                      _doseUnit = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ScheduleTimeEditor(
                  label: 'Schedule Times (optional)',
                  times: _scheduleTimes,
                  onAddTime: _pickAndAddScheduleTime,
                  onRemoveTime: (time) {
                    setState(() {
                      _scheduleTimes.remove(time);
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _instructionsController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
                  ),
                ),
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
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final instructions = _instructionsController.text.trim();
    final doseRaw = _doseAmountController.text.trim();

    Navigator.of(context).pop(
      _MedicineDraft(
        name: _nameController.text.trim(),
        instructions: instructions.isEmpty ? null : instructions,
        doseAmount: doseRaw.isEmpty ? null : num.tryParse(doseRaw),
        doseUnit: _doseUnit,
        active: _active,
        scheduleTimes: _scheduleTimes.toList()..sort(),
      ),
    );
  }

  List<DropdownMenuItem<String?>> _buildDoseUnitItems() {
    final options = <String>{..._medicineDoseUnitOptions};
    if (_doseUnit != null && _doseUnit!.trim().isNotEmpty) {
      options.add(_doseUnit!.trim());
    }

    final sortedOptions = options.toList()..sort();
    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Not set'),
      ),
      ...sortedOptions.map(
        (unit) => DropdownMenuItem<String?>(
          value: unit,
          child: Text(unit),
        ),
      ),
    ];
  }

  Future<void> _pickAndAddScheduleTime() async {
    final pickedTime = await _pickScheduleTime(context);
    if (pickedTime == null) {
      return;
    }

    setState(() {
      final deduped = <String>{..._scheduleTimes, pickedTime}.toList()..sort();
      _scheduleTimes
        ..clear()
        ..addAll(deduped);
    });
  }
}

class _ProcedureDraft {
  const _ProcedureDraft({
    required this.name,
    required this.instructions,
    required this.frequency,
    required this.active,
    required this.scheduleTimes,
  });

  final String name;
  final String? instructions;
  final String? frequency;
  final bool active;
  final List<String> scheduleTimes;
}

class _ProcedureDialog extends StatefulWidget {
  const _ProcedureDialog({
    this.initialValue,
  });

  final ProcedureModel? initialValue;

  @override
  State<_ProcedureDialog> createState() => _ProcedureDialogState();
}

class _ProcedureDialogState extends State<_ProcedureDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _instructionsController;
  late String? _frequency;
  late final List<String> _scheduleTimes;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _instructionsController = TextEditingController(
      text: initial?.instructions ?? '',
    );
    _frequency = initial?.frequency;
    _scheduleTimes = List<String>.from(initial?.scheduleTimes ?? <String>[])
      ..sort();
    _active = initial?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Procedure' : 'Add Procedure'),
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
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _frequency,
                  decoration: const InputDecoration(
                    labelText: 'Frequency (optional)',
                  ),
                  items: _buildFrequencyItems(),
                  onChanged: (value) {
                    setState(() {
                      _frequency = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _ScheduleTimeEditor(
                  label: 'Schedule Times (optional)',
                  times: _scheduleTimes,
                  onAddTime: _pickAndAddScheduleTime,
                  onRemoveTime: (time) {
                    setState(() {
                      _scheduleTimes.remove(time);
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _instructionsController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
                  ),
                ),
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
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final instructions = _instructionsController.text.trim();
    Navigator.of(context).pop(
      _ProcedureDraft(
        name: _nameController.text.trim(),
        instructions: instructions.isEmpty ? null : instructions,
        frequency: _frequency,
        active: _active,
        scheduleTimes: _scheduleTimes.toList()..sort(),
      ),
    );
  }

  List<DropdownMenuItem<String?>> _buildFrequencyItems() {
    final options = <String>{..._procedureFrequencyOptions};
    if (_frequency != null && _frequency!.trim().isNotEmpty) {
      options.add(_frequency!.trim());
    }

    final sortedOptions = options.toList()..sort();
    return <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Not set'),
      ),
      ...sortedOptions.map(
        (value) => DropdownMenuItem<String?>(
          value: value,
          child: Text(value),
        ),
      ),
    ];
  }

  Future<void> _pickAndAddScheduleTime() async {
    final pickedTime = await _pickScheduleTime(context);
    if (pickedTime == null) {
      return;
    }

    setState(() {
      final deduped = <String>{..._scheduleTimes, pickedTime}.toList()..sort();
      _scheduleTimes
        ..clear()
        ..addAll(deduped);
    });
  }
}

class _InsulinProfileDraft {
  const _InsulinProfileDraft({
    required this.type,
    required this.label,
    required this.insulinName,
    required this.active,
    required this.scheduleTimes,
    required this.slidingScaleMgdl,
    required this.mealBaseUnits,
    required this.defaultBaseUnits,
    required this.fixedUnits,
    required this.notes,
  });

  final String type;
  final String label;
  final String? insulinName;
  final bool active;
  final List<String> scheduleTimes;
  final List<num> slidingScaleMgdl;
  final Map<String, num> mealBaseUnits;
  final num? defaultBaseUnits;
  final num? fixedUnits;
  final String? notes;
}

class _InsulinProfileDialog extends StatefulWidget {
  const _InsulinProfileDialog({
    this.initialValue,
  });

  final InsulinProfileModel? initialValue;

  @override
  State<_InsulinProfileDialog> createState() => _InsulinProfileDialogState();
}

class _InsulinProfileDialogState extends State<_InsulinProfileDialog> {
  static const _mealTags = <String>[
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'none',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _insulinNameController;
  late final TextEditingController _notesController;
  late final TextEditingController _slidingScaleController;
  late final TextEditingController _defaultBaseController;
  late final TextEditingController _fixedUnitsController;
  late final Map<String, TextEditingController> _mealBaseControllers;
  late final List<String> _scheduleTimes;
  late String _type;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _type = initial?.type == 'basal' ? 'basal' : 'rapid';
    _active = initial?.active ?? true;

    _labelController = TextEditingController(text: initial?.label ?? '');
    _insulinNameController = TextEditingController(
      text: initial?.insulinName ?? '',
    );
    _scheduleTimes = List<String>.from(initial?.scheduleTimes ?? <String>[])
      ..sort();
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _slidingScaleController = TextEditingController(
      text: initial?.slidingScaleMgdl.join(', ') ?? '',
    );
    _defaultBaseController = TextEditingController(
      text: initial?.defaultBaseUnits?.toString() ?? '',
    );
    _fixedUnitsController = TextEditingController(
      text: initial?.fixedUnits?.toString() ?? '',
    );
    _mealBaseControllers = <String, TextEditingController>{
      for (final tag in _mealTags)
        tag: TextEditingController(
          text: initial?.mealBaseUnits[tag]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    _labelController.dispose();
    _insulinNameController.dispose();
    _notesController.dispose();
    _slidingScaleController.dispose();
    _defaultBaseController.dispose();
    _fixedUnitsController.dispose();
    for (final controller in _mealBaseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Insulin Profile' : 'Add Insulin Profile'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'rapid', child: Text('Rapid')),
                    DropdownMenuItem(value: 'basal', child: Text('Basal')),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _type = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _labelController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Label'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Label is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _insulinNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Insulin Name (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                _ScheduleTimeEditor(
                  label: 'Schedule Times',
                  times: _scheduleTimes,
                  onAddTime: _pickAndAddScheduleTime,
                  onRemoveTime: (time) {
                    setState(() {
                      _scheduleTimes.remove(time);
                    });
                  },
                ),
                const SizedBox(height: 10),
                if (_type == 'rapid') ...<Widget>[
                  TextFormField(
                    controller: _slidingScaleController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Sliding Scale mg/dL (optional)',
                      hintText: '150, 200, 250',
                    ),
                    validator: (value) {
                      try {
                        _parseNumberCsv(value ?? '');
                        return null;
                      } catch (_) {
                        return 'Use comma-separated numbers.';
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _defaultBaseController,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Default Base Units (optional)',
                    ),
                    validator: _optionalNumberValidator,
                  ),
                  const SizedBox(height: 10),
                  ..._mealTags.map((tag) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextFormField(
                        controller: _mealBaseControllers[tag],
                        textInputAction: TextInputAction.next,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Meal Base: $tag (optional)',
                        ),
                        validator: _optionalNumberValidator,
                      ),
                    );
                  }),
                ] else ...<Widget>[
                  TextFormField(
                    controller: _fixedUnitsController,
                    textInputAction: TextInputAction.next,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Fixed Units (optional)',
                    ),
                    validator: _optionalNumberValidator,
                  ),
                ],
                TextFormField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
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
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  String? _optionalNumberValidator(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) {
      return null;
    }
    return num.tryParse(raw) == null ? 'Enter a valid number.' : null;
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final mealBaseUnits = <String, num>{};
    for (final entry in _mealBaseControllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) {
        continue;
      }
      final parsed = num.tryParse(raw);
      if (parsed != null) {
        mealBaseUnits[entry.key] = parsed;
      }
    }

    final insulinName = _insulinNameController.text.trim();
    final notes = _notesController.text.trim();
    final defaultBaseRaw = _defaultBaseController.text.trim();
    final fixedUnitsRaw = _fixedUnitsController.text.trim();

    Navigator.of(context).pop(
      _InsulinProfileDraft(
        type: _type,
        label: _labelController.text.trim(),
        insulinName: insulinName.isEmpty ? null : insulinName,
        active: _active,
        scheduleTimes: _scheduleTimes.toList()..sort(),
        slidingScaleMgdl: _type == 'rapid'
            ? _parseNumberCsv(_slidingScaleController.text)
            : const <num>[],
        mealBaseUnits: _type == 'rapid' ? mealBaseUnits : const <String, num>{},
        defaultBaseUnits: _type == 'rapid' && defaultBaseRaw.isNotEmpty
            ? num.tryParse(defaultBaseRaw)
            : null,
        fixedUnits: _type == 'basal' && fixedUnitsRaw.isNotEmpty
            ? num.tryParse(fixedUnitsRaw)
            : null,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  Future<void> _pickAndAddScheduleTime() async {
    final pickedTime = await _pickScheduleTime(context);
    if (pickedTime == null) {
      return;
    }

    setState(() {
      final deduped = <String>{..._scheduleTimes, pickedTime}.toList()..sort();
      _scheduleTimes
        ..clear()
        ..addAll(deduped);
    });
  }
}

Future<String?> _pickScheduleTime(BuildContext context) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
    helpText: 'Select Time',
  );
  if (picked == null) {
    return null;
  }
  return _formatTimeOfDay(picked);
}

String _formatTimeOfDay(TimeOfDay value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatDateId(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

class _ScheduleTimeEditor extends StatelessWidget {
  const _ScheduleTimeEditor({
    required this.label,
    required this.times,
    required this.onAddTime,
    required this.onRemoveTime,
  });

  final String label;
  final List<String> times;
  final VoidCallback onAddTime;
  final ValueChanged<String> onRemoveTime;

  @override
  Widget build(BuildContext context) {
    final hasTimes = times.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            TextButton.icon(
              onPressed: onAddTime,
              icon: const Icon(Icons.schedule_outlined),
              label: const Text('Add Time'),
            ),
          ],
        ),
        if (!hasTimes)
          Text(
            'No times selected',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: times
                .map(
                  (time) => InputChip(
                    label: Text(time),
                    onDeleted: () => onRemoveTime(time),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}

List<num> _parseNumberCsv(String input) {
  final result = <num>[];
  for (final part in input.split(',')) {
    final value = part.trim();
    if (value.isEmpty) {
      continue;
    }
    final parsed = num.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Invalid number format');
    }
    result.add(parsed);
  }
  return result;
}

class _ChecklistTab extends ConsumerStatefulWidget {
  const _ChecklistTab({required this.patientId});

  final String patientId;

  @override
  ConsumerState<_ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends ConsumerState<_ChecklistTab> {
  final Map<String, TextEditingController> _glucoseControllers =
      <String, TextEditingController>{};
  final Map<String, String> _mealTags = <String, String>{};
  String? _busyTaskId;
  bool _isGeneratingChecklist = false;
  String? _selectedDateId;

  @override
  void dispose() {
    for (final controller in _glucoseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _glucoseController(String taskId, num? initialGlucose) {
    final existing = _glucoseControllers[taskId];
    if (existing != null) {
      return existing;
    }

    final controller = TextEditingController(
      text: initialGlucose == null ? '' : initialGlucose.toString(),
    );
    _glucoseControllers[taskId] = controller;
    return controller;
  }

  Future<void> _submitTask({
    required ChecklistTaskModel task,
    required String status,
    required String dateId,
  }) async {
    if (_busyTaskId != null) {
      return;
    }

    final inputs = <String, dynamic>{};
    if (task.isInsulinRapid) {
      final glucoseText = _glucoseControllers[task.id]?.text.trim() ?? '';
      final glucose = double.tryParse(glucoseText);
      final mealTag = (_mealTags[task.id] ?? 'none').trim();

      if (status == 'done' && glucose == null) {
        _showSnack('Enter glucose value before marking rapid insulin as done.');
        return;
      }

      if (glucose != null) {
        inputs['glucoseMgDl'] = glucose;
      }
      inputs['mealTag'] = mealTag.isEmpty ? 'none' : mealTag;
    }

    setState(() {
      _busyTaskId = task.id;
    });

    try {
      await ref.read(apiClientProvider).updateChecklistTask(
            patientId: widget.patientId,
            date: dateId,
            taskId: task.id,
            status: status,
            inputs: inputs.isEmpty ? null : inputs,
          );
      _showSnack('Task updated.');
    } catch (error) {
      _showSnack('Update failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _busyTaskId = null;
        });
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _generateChecklist({required String dateId}) async {
    if (_isGeneratingChecklist) {
      return;
    }

    setState(() {
      _isGeneratingChecklist = true;
    });

    try {
      final response = await ref.read(apiClientProvider).generateChecklist(
            patientId: widget.patientId,
            date: dateId,
          );
      final taskCount = response['taskCount'];
      _showSnack(
        taskCount is num
            ? 'Checklist generated with ${taskCount.toInt()} tasks.'
            : 'Checklist generated.',
      );
      ref.invalidate(
        checklistProvider(
          ChecklistQuery(patientId: widget.patientId, dateId: dateId),
        ),
      );
    } catch (error) {
      _showSnack('Checklist generation failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingChecklist = false;
        });
      }
    }
  }

  Widget _checklistActionCard({required String dateId}) {
    final parsed = DateTime.tryParse('${dateId}T00:00:00');
    final dateLabel =
        parsed == null ? dateId : DateFormat('EEE, MMM d, yyyy').format(parsed);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          spacing: 8,
          children: <Widget>[
            Text(
              'Checklist date: $dateLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            OutlinedButton.icon(
              onPressed: () => _selectChecklistDate(fallbackDateId: dateId),
              icon: const Icon(Icons.event_outlined),
              label: const Text('Change Date'),
            ),
            FilledButton.icon(
              onPressed: _isGeneratingChecklist
                  ? null
                  : () => _generateChecklist(dateId: dateId),
              icon: _isGeneratingChecklist
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check_rounded),
              label: const Text('Generate'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectChecklistDate({required String fallbackDateId}) async {
    final initial = DateTime.tryParse(
          '${(_selectedDateId ?? fallbackDateId)}T00:00:00',
        ) ??
        DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Checklist Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDateId = _formatDateId(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final todayDateId = ref.watch(todayDateIdProvider);
    final dateId = _selectedDateId ?? todayDateId;
    final canGenerateChecklist = ref.watch(userProfileProvider).value != null;
    final checklistAsync = ref.watch(
      checklistProvider(
        ChecklistQuery(patientId: widget.patientId, dateId: dateId),
      ),
    );
    final insulinProfilesAsync =
        ref.watch(insulinProfilesProvider(widget.patientId));

    return checklistAsync.when(
      data: (checklist) {
        if (checklist == null || checklist.tasks.isEmpty) {
          final selectedDate = DateTime.tryParse('${dateId}T00:00:00');
          final selectedDateLabel = selectedDate == null
              ? dateId
              : DateFormat('EEE, MMM d, yyyy').format(selectedDate);
          if (!canGenerateChecklist) {
            return Center(
              child: Text('No checklist generated for $selectedDateLabel yet.'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _checklistActionCard(dateId: dateId),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                      'No checklist generated for $selectedDateLabel yet.'),
                ),
              ),
            ],
          );
        }

        final resultByTask = checklist.resultByTaskId();
        final insulinById = <String, InsulinProfileModel>{
          for (final profile
              in insulinProfilesAsync.value ?? <InsulinProfileModel>[])
            profile.id: profile,
        };

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canGenerateChecklist) ...<Widget>[
              _checklistActionCard(dateId: dateId),
              const SizedBox(height: 12),
            ],
            ...checklist.tasks.map((task) {
              final result = resultByTask[task.id];
              final currentStatus = (result?.status ?? 'pending').toLowerCase();
              final busy = _busyTaskId == task.id;

              final children = <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        task.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    _StatusChip(status: currentStatus),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  [
                    if (task.scheduledTime != null)
                      'Time: ${task.scheduledTime}',
                    'Type: ${task.type}',
                  ].join(' | '),
                ),
                if (task.notes != null && task.notes!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(task.notes!),
                ],
                if (result != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    _resultSummary(result),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ];

              if (task.isInsulinRapid) {
                final controller =
                    _glucoseController(task.id, result?.glucoseMgDl);
                final mealTag = _mealTags.putIfAbsent(
                  task.id,
                  () => (result?.mealTag ?? 'none'),
                );
                final glucose = double.tryParse(controller.text.trim());
                final insulinProfileId = task.insulinProfileId;
                final profile = insulinProfileId == null
                    ? null
                    : insulinById[insulinProfileId];
                final preview = (profile != null && glucose != null)
                    ? computeRapidDosePreview(
                        mealTag: mealTag,
                        glucoseMgDl: glucose,
                        profile: profile,
                      )
                    : null;

                children.addAll(<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Glucose (mg/dL)',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: mealTag,
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                                value: 'none', child: Text('None')),
                            DropdownMenuItem(
                              value: 'breakfast',
                              child: Text('Breakfast'),
                            ),
                            DropdownMenuItem(
                                value: 'lunch', child: Text('Lunch')),
                            DropdownMenuItem(
                                value: 'dinner', child: Text('Dinner')),
                            DropdownMenuItem(
                                value: 'snack', child: Text('Snack')),
                          ],
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            setState(() {
                              _mealTags[task.id] = value;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Meal',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (preview != null)
                    Text(
                      [
                        'Preview dose: base ${preview.base}u',
                        'sliding ${preview.sliding}u',
                        'total ${preview.total}u',
                      ].join(' | '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (preview != null &&
                      (preview.lowGlucose || preview.highGlucose))
                    Text(
                      preview.lowGlucose
                          ? 'Low glucose safety flag.'
                          : 'High glucose safety flag.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                ]);
              }

              children.add(const SizedBox(height: 12));
              children.add(
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => _submitTask(
                                task: task,
                                status: 'done',
                                dateId: dateId,
                              ),
                      icon: busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: const Text('Done'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => _submitTask(
                                task: task,
                                status: 'skipped',
                                dateId: dateId,
                              ),
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Skip'),
                    ),
                  ],
                ),
              );

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load checklist: $error')),
    );
  }

  String _resultSummary(ChecklistResultModel result) {
    final parts = <String>[
      'Status: ${result.status}',
    ];

    if (result.completedAt != null) {
      parts.add('Completed: ${result.completedAt}');
    }
    if (result.glucoseMgDl != null) {
      parts.add('Glucose: ${result.glucoseMgDl}');
    }
    if (result.totalUnits != null) {
      parts.add('Dose: ${result.totalUnits}u');
    }
    return parts.join(' | ');
  }
}

class _HealthCheckDraft {
  const _HealthCheckDraft({
    required this.checkedAt,
    this.weightKg,
    this.temperatureC,
    this.bloodPressureSystolic,
    this.bloodPressureDiastolic,
    this.pulseBpm,
    this.spo2Pct,
    this.notes,
  });

  final DateTime checkedAt;
  final num? weightKg;
  final num? temperatureC;
  final num? bloodPressureSystolic;
  final num? bloodPressureDiastolic;
  final num? pulseBpm;
  final num? spo2Pct;
  final String? notes;
}

class _HealthChecksTab extends ConsumerWidget {
  const _HealthChecksTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userProfileProvider).value?.role;
    final canRecord =
        role == 'admin' || role == 'supervisor' || role == 'nurse';
    final checksAsync = ref.watch(healthChecksProvider(patientId));

    Future<void> createHealthCheck() async {
      final draft = await showDialog<_HealthCheckDraft>(
        context: context,
        builder: (_) => const _HealthCheckDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createHealthCheck(
              patientId: patientId,
              checkedAt: draft.checkedAt,
              weightKg: draft.weightKg,
              temperatureC: draft.temperatureC,
              bloodPressureSystolic: draft.bloodPressureSystolic,
              bloodPressureDiastolic: draft.bloodPressureDiastolic,
              pulseBpm: draft.pulseBpm,
              spo2Pct: draft.spo2Pct,
              notes: draft.notes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Health check recorded.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to record health check: $error')),
        );
      }
    }

    return checksAsync.when(
      data: (checks) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canRecord)
              _TabActionHeader(
                label: 'Regular Health Checks',
                actionLabel: 'Add Health Check',
                onPressed: createHealthCheck,
              ),
            if (checks.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No health checks recorded yet.'),
                ),
              ),
            ...checks.map((check) {
              final bp = check.bloodPressureSystolic != null &&
                      check.bloodPressureDiastolic != null
                  ? '${check.bloodPressureSystolic}/${check.bloodPressureDiastolic}'
                  : '-';
              final checkedAt = _formatIsoDateTime(check.checkedAt);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                checkedAt,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            if (check.recordedByUid != null)
                              Chip(
                                label: Text(
                                  'by ${check.recordedByUid}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            _MetricChip(
                              label: 'Weight',
                              value: check.weightKg == null
                                  ? '-'
                                  : '${check.weightKg} kg',
                            ),
                            _MetricChip(
                              label: 'Temp',
                              value: check.temperatureC == null
                                  ? '-'
                                  : '${check.temperatureC} C',
                            ),
                            _MetricChip(label: 'BP', value: bp),
                            _MetricChip(
                              label: 'Pulse',
                              value: check.pulseBpm == null
                                  ? '-'
                                  : '${check.pulseBpm} bpm',
                            ),
                            _MetricChip(
                              label: 'SpO2',
                              value: check.spo2Pct == null
                                  ? '-'
                                  : '${check.spo2Pct}%',
                            ),
                          ],
                        ),
                        if (check.notes != null &&
                            check.notes!.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 8),
                          Text(
                            check.notes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load health checks: $error')),
    );
  }
}

class _HealthCheckDialog extends StatefulWidget {
  const _HealthCheckDialog();

  @override
  State<_HealthCheckDialog> createState() => _HealthCheckDialogState();
}

class _HealthCheckDialogState extends State<_HealthCheckDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _checkedAt;
  late final TextEditingController _weightController;
  late final TextEditingController _temperatureController;
  late final TextEditingController _systolicController;
  late final TextEditingController _diastolicController;
  late final TextEditingController _pulseController;
  late final TextEditingController _spo2Controller;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    _checkedAt = DateTime.now();
    _weightController = TextEditingController();
    _temperatureController = TextEditingController();
    _systolicController = TextEditingController();
    _diastolicController = TextEditingController();
    _pulseController = TextEditingController();
    _spo2Controller = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _temperatureController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _pulseController.dispose();
    _spo2Controller.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Health Check'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Checked at ${DateFormat('yyyy-MM-dd HH:mm').format(_checkedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.event_outlined),
                      label: const Text('Date'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _selectTime,
                      icon: const Icon(Icons.schedule_outlined),
                      label: const Text('Time'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextFormField(
                        controller: _weightController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Weight (kg)'),
                        validator: (value) => _validateNumber(value, min: 0.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _temperatureController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Temperature (C)'),
                        validator: (value) =>
                            _validateNumber(value, min: 25, max: 45),
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'BP Systolic'),
                        validator: (value) {
                          final diastolic = _diastolicController.text.trim();
                          final raw = (value ?? '').trim();
                          if (raw.isEmpty && diastolic.isEmpty) {
                            return null;
                          }
                          if (raw.isEmpty || diastolic.isEmpty) {
                            return 'Enter both BP values.';
                          }
                          return _validateNumber(raw, min: 40, max: 300);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _diastolicController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'BP Diastolic'),
                        validator: (value) {
                          final systolic = _systolicController.text.trim();
                          final raw = (value ?? '').trim();
                          if (raw.isEmpty && systolic.isEmpty) {
                            return null;
                          }
                          if (raw.isEmpty || systolic.isEmpty) {
                            return 'Enter both BP values.';
                          }
                          return _validateNumber(raw, min: 30, max: 200);
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
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'Pulse (bpm)'),
                        validator: (value) =>
                            _validateNumber(value, min: 20, max: 250),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _spo2Controller,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        decoration:
                            const InputDecoration(labelText: 'SpO2 (%)'),
                        validator: (value) =>
                            _validateNumber(value, min: 40, max: 100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
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
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: 'Select Check Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _checkedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _checkedAt.hour,
        _checkedAt.minute,
      );
    });
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_checkedAt),
      helpText: 'Select Check Time',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _checkedAt = DateTime(
        _checkedAt.year,
        _checkedAt.month,
        _checkedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final weightKg = _readOptionalNum(_weightController.text);
    final temperatureC = _readOptionalNum(_temperatureController.text);
    final bloodPressureSystolic = _readOptionalNum(_systolicController.text);
    final bloodPressureDiastolic = _readOptionalNum(_diastolicController.text);
    final pulseBpm = _readOptionalNum(_pulseController.text);
    final spo2Pct = _readOptionalNum(_spo2Controller.text);

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

    if (weightKg == null &&
        temperatureC == null &&
        bloodPressureSystolic == null &&
        bloodPressureDiastolic == null &&
        pulseBpm == null &&
        spo2Pct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one health metric.')),
      );
      return;
    }

    final notes = _notesController.text.trim();
    Navigator.of(context).pop(
      _HealthCheckDraft(
        checkedAt: _checkedAt,
        weightKg: weightKg,
        temperatureC: temperatureC,
        bloodPressureSystolic: bloodPressureSystolic,
        bloodPressureDiastolic: bloodPressureDiastolic,
        pulseBpm: pulseBpm,
        spo2Pct: spo2Pct,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  num? _readOptionalNum(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return null;
    }
    return num.tryParse(raw);
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
    if (parsed < min || (max != null && parsed > max)) {
      if (max == null) {
        return 'Must be at least $min.';
      }
      return '$min - $max only.';
    }
    return null;
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab({required this.patientId});

  final String patientId;

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    final todayDateId = ref.watch(todayDateIdProvider);
    final reportsAsync = ref.watch(reportsProvider(widget.patientId));
    return reportsAsync.when(
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(child: Text('No reports yet.'));
        }

        final sorted = reports.toList()
          ..sort((left, right) => right.dateId.compareTo(left.dateId));
        final filtered = sorted.where(_isWithinRange).toList();
        if (filtered.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildDateRangeCard(
                context,
                filteredCount: 0,
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No reports found in the selected date range.'),
                ),
              ),
            ],
          );
        }

        final today = filtered.firstWhere(
          (report) => report.dateId == todayDateId,
          orElse: () => filtered.first,
        );

        final currentWeek =
            _ReportTotals.fromReports(filtered.take(7).toList());
        final previousWeek = _ReportTotals.fromReports(
          filtered.length > 7
              ? filtered.skip(7).take(7).toList()
              : <DailyReportModel>[],
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _buildDateRangeCard(
              context,
              filteredCount: filtered.length,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Daily Summary (${today.dateId})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _StatChip(label: 'Done', value: today.done),
                        _StatChip(label: 'Missed', value: today.missed),
                        _StatChip(label: 'Late', value: today.late),
                        _StatChip(label: 'Skipped', value: today.skipped),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Weekly Comparison',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    _WeeklyRow(
                      title: 'Current 7 Days',
                      totals: currentWeek,
                    ),
                    const SizedBox(height: 10),
                    _WeeklyRow(
                      title: 'Previous 7 Days',
                      totals: previousWeek,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Recent Daily Reports (Filtered)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...filtered.take(7).map((report) {
                      final dateLabel = _formatDate(report.dateId);
                      final total = max(
                          1,
                          report.done +
                              report.missed +
                              report.late +
                              report.skipped);
                      final completion = report.done / total;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                                '$dateLabel: done ${report.done}, missed ${report.missed}, '
                                'late ${report.late}, skipped ${report.skipped}'),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(value: completion),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          Center(child: Text('Unable to load reports: $error')),
    );
  }

  Widget _buildDateRangeCard(
    BuildContext context, {
    required int filteredCount,
  }) {
    final startLabel = _startDate == null
        ? 'Start Date'
        : DateFormat('yyyy-MM-dd').format(_startDate!);
    final endLabel = _endDate == null
        ? 'End Date'
        : DateFormat('yyyy-MM-dd').format(_endDate!);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Report Date Range',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _pickStartDate,
                  icon: const Icon(Icons.date_range_outlined),
                  label: Text(startLabel),
                ),
                OutlinedButton.icon(
                  onPressed: _pickEndDate,
                  icon: const Icon(Icons.event_available_outlined),
                  label: Text(endLabel),
                ),
                if (_startDate != null || _endDate != null)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                      });
                    },
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Reports in range: $filteredCount'),
          ],
        ),
      ),
    );
  }

  bool _isWithinRange(DailyReportModel report) {
    final reportDate = _parseDateId(report.dateId);
    if (reportDate == null) {
      return true;
    }

    final start = _startDate == null
        ? null
        : DateTime.utc(_startDate!.year, _startDate!.month, _startDate!.day);
    final end = _endDate == null
        ? null
        : DateTime.utc(_endDate!.year, _endDate!.month, _endDate!.day);

    if (start != null && reportDate.isBefore(start)) {
      return false;
    }
    if (end != null && reportDate.isAfter(end)) {
      return false;
    }
    return true;
  }

  DateTime? _parseDateId(String dateId) {
    return DateTime.tryParse('${dateId}T00:00:00Z');
  }

  Future<void> _pickStartDate() async {
    final initial = _startDate ?? _endDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Start Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _startDate = picked;
      if (_endDate != null && picked.isAfter(_endDate!)) {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate ?? _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select End Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _endDate = picked;
      if (_startDate != null && picked.isBefore(_startDate!)) {
        _startDate = picked;
      }
    });
  }

  String _formatDate(String dateId) {
    final parsed = DateTime.tryParse('${dateId}T00:00:00Z');
    if (parsed == null) {
      return dateId;
    }
    return DateFormat('EEE, MMM d').format(parsed.toLocal());
  }
}

class _AiAssistantTab extends ConsumerStatefulWidget {
  const _AiAssistantTab({required this.patientId});

  final String patientId;

  @override
  ConsumerState<_AiAssistantTab> createState() => _AiAssistantTabState();
}

class _AiAssistantTabState extends ConsumerState<_AiAssistantTab> {
  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessageModel> _messages = <ChatMessageModel>[
    const ChatMessageModel(
      id: 'init',
      fromUser: false,
      text:
          'Ask operational care questions. Clinical diagnosis, prescribing, and dose changes are blocked.',
    ),
  ];
  bool _loading = false;
  String? _selectedDateId;

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _loading) {
      return;
    }

    final dateId = _selectedDateId ?? ref.read(todayDateIdProvider);
    _questionController.clear();

    setState(() {
      _loading = true;
      _messages.add(
        ChatMessageModel(
          id: 'q_${DateTime.now().microsecondsSinceEpoch}',
          fromUser: true,
          text: question,
        ),
      );
    });
    _scrollToBottom();

    try {
      final response = await ref.read(apiClientProvider).askAi(
            patientId: widget.patientId,
            question: question,
            date: dateId,
          );

      final bulletText = response.bullets.isEmpty
          ? ''
          : '\n\n${response.bullets.map((item) => '- $item').join('\n')}';
      final meta = <String>[
        if (response.disclaimer.isNotEmpty)
          'Disclaimer: ${response.disclaimer}',
        if (response.references.isNotEmpty)
          'References: ${response.references.join(', ')}',
        if (response.safetyFlags.isNotEmpty)
          'Safety: ${response.safetyFlags.join(', ')}',
      ];

      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          ChatMessageModel(
            id: 'a_${DateTime.now().microsecondsSinceEpoch}',
            fromUser: false,
            text: '${response.answerText}$bulletText',
            meta: meta,
          ),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          ChatMessageModel(
            id: 'err_${DateTime.now().microsecondsSinceEpoch}',
            fromUser: false,
            text: 'Unable to get AI response: $error',
          ),
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _selectContextDate({required String fallbackDateId}) async {
    final initial = DateTime.tryParse(
          '${(_selectedDateId ?? fallbackDateId)}T00:00:00',
        ) ??
        DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select AI Context Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _selectedDateId = _formatDateId(picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final todayDateId = ref.watch(todayDateIdProvider);
    final contextDateId = _selectedDateId ?? todayDateId;
    final parsedContextDate = DateTime.tryParse('${contextDateId}T00:00:00');
    final contextDateLabel = parsedContextDate == null
        ? contextDateId
        : DateFormat('EEE, MMM d, yyyy').format(parsedContextDate);

    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Text('Context date: $contextDateLabel'),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _selectContextDate(fallbackDateId: contextDateId),
                    icon: const Icon(Icons.event_outlined),
                    label: const Text('Change Date'),
                  ),
                  if (_selectedDateId != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedDateId = null;
                        });
                      },
                      child: const Text('Use Today'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'AI disclaimer: operational support only, no diagnosis/prescription/dose changes.',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return _ChatBubble(message: message);
            },
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _questionController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText:
                          'Ask about workflow, checklist context, or insulin explanation.',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _send,
                  child: const Text('Send'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessageModel message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.fromUser;
    final background = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(message.text),
            if (message.meta.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              ...message.meta.map(
                (line) => Text(
                  line,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReportTotals {
  const _ReportTotals({
    required this.done,
    required this.missed,
    required this.late,
    required this.skipped,
  });

  final int done;
  final int missed;
  final int late;
  final int skipped;

  int get total => done + missed + late + skipped;
  double get completionRate => total == 0 ? 0 : done / total;

  factory _ReportTotals.fromReports(List<DailyReportModel> reports) {
    var done = 0;
    var missed = 0;
    var late = 0;
    var skipped = 0;
    for (final report in reports) {
      done += report.done;
      missed += report.missed;
      late += report.late;
      skipped += report.skipped;
    }
    return _ReportTotals(
        done: done, missed: missed, late: late, skipped: skipped);
  }
}

class _WeeklyRow extends StatelessWidget {
  const _WeeklyRow({
    required this.title,
    required this.totals,
  });

  final String title;
  final _ReportTotals totals;

  @override
  Widget build(BuildContext context) {
    final completionPct = (totals.completionRate * 100).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('$title | $completionPct% completion'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: totals.completionRate),
        const SizedBox(height: 4),
        Text(
          'Done ${totals.done} | Missed ${totals.missed} | '
          'Late ${totals.late} | Skipped ${totals.skipped}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

String _displayGender(String gender) {
  switch (gender.trim().toLowerCase()) {
    case 'male':
      return 'Male';
    case 'female':
      return 'Female';
    case 'other':
      return 'Other';
    case 'prefer_not_to_say':
      return 'Prefer not to say';
    default:
      return gender;
  }
}

String _formatIsoDateTime(String? value) {
  if (value == null || value.trim().isEmpty) {
    return '-';
  }

  final parsed = DateTime.tryParse(value.trim());
  if (parsed == null) {
    return value;
  }
  return DateFormat('EEE, MMM d, yyyy • HH:mm').format(parsed.toLocal());
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' || 'done' => Colors.green.shade700,
      'late' => Colors.orange.shade700,
      'skipped' => Colors.blueGrey.shade700,
      'missed' || 'failed' => Colors.red.shade700,
      _ => Colors.grey.shade700,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('$label: $value'),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
