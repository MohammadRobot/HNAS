import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../app_localizations.dart';
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
      return Scaffold(
        body: Center(
          child: Builder(
            builder: (ctx) => Text(AppLocalizations.of(ctx).invalidPatientId),
          ),
        ),
      );
    }

    final patientAsync = ref.watch(patientProvider(patientId));

    final l = AppLocalizations.of(context);
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: patientAsync.when(
            data: (patient) => Text(patient?.fullName ?? l.patient),
            loading: () => Text(l.patient),
            error: (_, __) => Text(l.patient),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: l.tabOverview),
              Tab(text: l.tabMedications),
              Tab(text: l.tabProcedures),
              Tab(text: l.tabLabTests),
              Tab(text: l.tabChecklist),
              Tab(text: l.tabHealthChecks),
              Tab(text: l.tabReports),
              Tab(text: l.tabAiAssistant),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _OverviewTab(patientId: patientId),
            _MedicinesTab(patientId: patientId),
            _ProceduresTab(patientId: patientId),
            _LabTestsTab(patientId: patientId),
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
    final l = AppLocalizations.of(context);
    final patientAsync = ref.watch(patientProvider(patientId));
    final todayReportAsync = ref.watch(todayReportProvider(patientId));
    final healthChecksAsync = ref.watch(healthChecksProvider(patientId));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        patientAsync.when(
          data: (patient) {
            if (patient == null) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l.notFound),
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PatientSafetySummary(patient: patient),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(4),
                      icon: const Icon(Icons.checklist_rounded),
                      label: Text(l.todaysChecklist),
                    ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(5),
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: Text(l.recordHealthCheck),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Card(
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
                          label: Text(
                            patient.active ? l.active : l.inactive,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(
                        label: l.timezone, value: patient.timezone ?? '-'),
                    _KeyValue(label: l.agency, value: patient.agencyId ?? '-'),
                    _KeyValue(
                      label: l.riskFlags,
                      value: patient.riskFlags.isEmpty
                          ? l.none
                          : patient.riskFlags.join(', '),
                    ),
                    _KeyValue(
                      label: l.diagnosis,
                      value: patient.diagnosis.isEmpty
                          ? l.none
                          : patient.diagnosis.join(', '),
                    ),
                    _KeyValue(
                      label: l.dateOfBirth,
                      value: patient.dateOfBirth ?? '-',
                    ),
                    _KeyValue(
                      label: l.gender,
                      value: patient.gender == null
                          ? '-'
                          : _displayGender(patient.gender!),
                    ),
                    _KeyValue(
                      label: l.phone,
                      value: patient.phoneNumber ?? '-',
                    ),
                    _KeyValue(
                      label: l.emergencyContact,
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
                      label: l.address,
                      value: patient.address ?? '-',
                    ),
                    _KeyValue(
                      label: l.allergies,
                      value: patient.allergies.isEmpty
                          ? l.none
                          : patient.allergies.join(', '),
                    ),
                    _KeyValue(
                      label: l.notes,
                      value: patient.notes ?? '-',
                    ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const _LoadingCard(),
          error: (error, _) => Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${l.unableToLoadProfile}: $error'),
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

class _PatientSafetySummary extends StatelessWidget {
  const _PatientSafetySummary({required this.patient});

  final PatientModel patient;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final hasWarnings =
        patient.allergies.isNotEmpty || patient.riskFlags.isNotEmpty;
    final color = hasWarnings
        ? const Color(0xFFB42318)
        : const Color(0xFF067647);

    return Semantics(
      label: hasWarnings ? l.safetyAlerts : l.noSafetyAlerts,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              hasWarnings
                  ? Icons.warning_amber_rounded
                  : Icons.verified_user_outlined,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hasWarnings ? l.safetyAlerts : l.noSafetyAlerts,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (patient.allergies.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text('${l.allergies}: ${patient.allergies.join(', ')}'),
                  ],
                  if (patient.riskFlags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text('${l.riskFlags}: ${patient.riskFlags.join(', ')}'),
                  ],
                  if (!hasWarnings) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(l.noSafetyAlertsRecorded),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
    final profilesAsync = ref.watch(insulinProfilesProvider(patientId));

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
              startDate: draft.startDate,
              recurrenceMode: draft.recurrenceMode,
              recurrenceEvery: draft.recurrenceEvery,
              recurrenceUnit: draft.recurrenceUnit,
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
              startDate: draft.startDate,
              recurrenceMode: draft.recurrenceMode,
              recurrenceEvery: draft.recurrenceEvery,
              recurrenceUnit: draft.recurrenceUnit,
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

    if (medicinesAsync.hasError && !medicinesAsync.hasValue) {
      return Center(
        child: Text('Unable to load medicines: ${medicinesAsync.error}'),
      );
    }
    if (profilesAsync.hasError && !profilesAsync.hasValue) {
      return Center(
        child: Text('Unable to load insulin profiles: ${profilesAsync.error}'),
      );
    }
    if ((medicinesAsync.isLoading && !medicinesAsync.hasValue) ||
        (profilesAsync.isLoading && !profilesAsync.hasValue)) {
      return const Center(child: CircularProgressIndicator());
    }

    final medicines = medicinesAsync.value ?? const <MedicineModel>[];
    final profiles = profilesAsync.value ?? const <InsulinProfileModel>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (canManage)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: createMedicine,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add Medicine'),
                  ),
                  OutlinedButton.icon(
                    onPressed: createInsulinProfile,
                    icon: const Icon(Icons.bloodtype_outlined),
                    label: const Text('Add Insulin Profile'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Medicines',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
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
          final recurrence = medicine.recurrenceLabel;
          final startDate = medicine.startDate ?? '-';

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
                    _KeyValue(label: 'Date', value: startDate),
                    _KeyValue(label: 'Alternative', value: recurrence),
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
        const SizedBox(height: 12),
        Text(
          'Insulin Profiles',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
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
                            tooltip: 'Edit insulin profile',
                            onPressed: () => editInsulinProfile(profile),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(
                        label: 'Insulin', value: profile.insulinName ?? '-'),
                    _KeyValue(label: 'Schedule', value: schedule),
                    if (profile.isRapid) ...<Widget>[
                      _KeyValue(label: 'Sliding Scale (mg/dL)', value: scale),
                      _KeyValue(label: 'Meal Base (units)', value: mealBase),
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

class _LabTestDraft {
  const _LabTestDraft({
    required this.testName,
    required this.status,
    this.panel,
    this.scheduleDate,
    this.scheduleTime,
    this.priority,
    this.orderedBy,
    this.notes,
  });

  final String testName;
  final String status;
  final String? panel;
  final String? scheduleDate;
  final String? scheduleTime;
  final String? priority;
  final String? orderedBy;
  final String? notes;
}

class _LabResultDraft {
  const _LabResultDraft({
    required this.resultValue,
    required this.resultAt,
    this.resultUnit,
    this.referenceRange,
    this.interpretation,
    this.resultFlag,
  });

  final String resultValue;
  final DateTime resultAt;
  final String? resultUnit;
  final String? referenceRange;
  final String? interpretation;
  final String? resultFlag;
}

class _LabTestsTab extends ConsumerWidget {
  const _LabTestsTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(userProfileProvider).value?.role;
    final canManage = _canManageLabTests(role);
    final labTestsAsync = ref.watch(labTestsProvider(patientId));

    Future<void> createLabTest() async {
      final draft = await showDialog<_LabTestDraft>(
        context: context,
        builder: (_) => const _LabTestDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createLabTest(
              patientId: patientId,
              testName: draft.testName,
              status: draft.status,
              panel: draft.panel,
              scheduleDate: draft.scheduleDate,
              scheduleTime: draft.scheduleTime,
              priority: draft.priority,
              orderedBy: draft.orderedBy,
              notes: draft.notes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lab test scheduled.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to schedule lab test: $error')),
        );
      }
    }

    Future<void> editLabTest(LabTestModel test) async {
      final draft = await showDialog<_LabTestDraft>(
        context: context,
        builder: (_) => _LabTestDialog(initialValue: test),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).updateLabTest(
              patientId: patientId,
              labTestId: test.id,
              testName: draft.testName,
              panel: draft.panel,
              scheduleDate: draft.scheduleDate,
              scheduleTime: draft.scheduleTime,
              status: draft.status,
              priority: draft.priority,
              orderedBy: draft.orderedBy,
              notes: draft.notes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lab test updated.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to update lab test: $error')),
        );
      }
    }

    Future<void> recordLabResult(LabTestModel test) async {
      final draft = await showDialog<_LabResultDraft>(
        context: context,
        builder: (_) => _LabResultDialog(initialValue: test),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).recordLabTestResult(
              patientId: patientId,
              labTestId: test.id,
              resultValue: draft.resultValue,
              resultUnit: draft.resultUnit,
              referenceRange: draft.referenceRange,
              interpretation: draft.interpretation,
              resultFlag: draft.resultFlag,
              resultAt: draft.resultAt,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lab result saved.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save lab result: $error')),
        );
      }
    }

    return labTestsAsync.when(
      data: (labTests) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (canManage)
              _TabActionHeader(
                label: 'Lab Tests',
                actionLabel: 'Add Lab Test',
                onPressed: createLabTest,
              ),
            if (labTests.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No lab tests scheduled. Add one with schedule date/time and record result later.',
                  ),
                ),
              ),
            ...labTests.map((test) {
              final schedule = _formatLabTestSchedule(test);
              final resultAt = _formatIsoDateTime(test.resultAt);
              final resultSummary = test.resultValue == null
                  ? '-'
                  : [
                      test.resultValue,
                      if (test.resultUnit != null) test.resultUnit,
                    ].whereType<String>().join(' ');

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
                                test.testName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _LabStatusChip(status: test.status),
                            if (canManage)
                              IconButton(
                                tooltip: 'Edit lab test',
                                onPressed: () => editLabTest(test),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _KeyValue(label: 'Panel', value: test.panel ?? '-'),
                        _KeyValue(label: 'Schedule', value: schedule),
                        _KeyValue(
                            label: 'Priority', value: test.priority ?? '-'),
                        _KeyValue(
                            label: 'Ordered By', value: test.orderedBy ?? '-'),
                        _KeyValue(label: 'Result', value: resultSummary),
                        _KeyValue(label: 'Result Date', value: resultAt),
                        _KeyValue(
                          label: 'Reference Range',
                          value: test.referenceRange ?? '-',
                        ),
                        _KeyValue(label: 'Flag', value: test.resultFlag ?? '-'),
                        _KeyValue(
                          label: 'Interpretation',
                          value: test.interpretation ?? '-',
                        ),
                        _KeyValue(label: 'Notes', value: test.notes ?? '-'),
                        if (canManage) ...<Widget>[
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: () => recordLabResult(test),
                            icon: const Icon(Icons.biotech_outlined),
                            label: Text(test.hasResult
                                ? 'Update Result'
                                : 'Record Result'),
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
          Center(child: Text('Unable to load lab tests: $error')),
    );
  }
}

class _LabTestDialog extends StatefulWidget {
  const _LabTestDialog({
    this.initialValue,
  });

  final LabTestModel? initialValue;

  @override
  State<_LabTestDialog> createState() => _LabTestDialogState();
}

class _LabTestDialogState extends State<_LabTestDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _panelController;
  late final TextEditingController _scheduleDateController;
  late final TextEditingController _scheduleTimeController;
  late String _status;
  late String? _priority;
  late final TextEditingController _orderedByController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _nameController = TextEditingController(text: initial?.testName ?? '');
    _panelController = TextEditingController(text: initial?.panel ?? '');
    _scheduleDateController =
        TextEditingController(text: initial?.scheduleDate ?? '');
    _scheduleTimeController =
        TextEditingController(text: initial?.scheduleTime ?? '');
    _status = initial?.status ?? _labTestStatusOptions.first;
    _priority = initial?.priority;
    _orderedByController =
        TextEditingController(text: initial?.orderedBy ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _panelController.dispose();
    _scheduleDateController.dispose();
    _scheduleTimeController.dispose();
    _orderedByController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    return AlertDialog(
      title: Text(isEditing ? 'Edit Lab Test' : 'Add Lab Test'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _nameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Test Name'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Test name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _panelController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Panel (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _scheduleDateController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Date',
                    hintText: 'YYYY-MM-DD',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  onTap: _selectScheduleDate,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Schedule date is required.';
                    }
                    if (!_isValidDateId(value.trim())) {
                      return 'Use YYYY-MM-DD format.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _scheduleTimeController,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Schedule Time (optional)',
                    suffixIcon: Icon(Icons.schedule_outlined),
                  ),
                  onTap: _selectScheduleTime,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                  ),
                  items: _labTestStatusOptions
                      .map(
                        (status) => DropdownMenuItem<String>(
                          value: status,
                          child: Text(_displayLabTestStatus(status)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _status = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _priority,
                  decoration: const InputDecoration(
                    labelText: 'Priority (optional)',
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    ..._labPriorityOptions.map(
                      (priority) => DropdownMenuItem<String?>(
                        value: priority,
                        child: Text(priority),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _priority = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _orderedByController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Ordered By (optional)',
                  ),
                ),
                const SizedBox(height: 10),
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

    final panel = _panelController.text.trim();
    final orderedBy = _orderedByController.text.trim();
    final notes = _notesController.text.trim();
    final scheduleTime = _scheduleTimeController.text.trim();

    Navigator.of(context).pop(
      _LabTestDraft(
        testName: _nameController.text.trim(),
        status: _status,
        panel: panel.isEmpty ? null : panel,
        scheduleDate: _scheduleDateController.text.trim(),
        scheduleTime: scheduleTime.isEmpty ? null : scheduleTime,
        priority: _priority,
        orderedBy: orderedBy.isEmpty ? null : orderedBy,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  Future<void> _selectScheduleDate() async {
    final initial = _scheduleDateController.text.trim().isEmpty
        ? DateTime.now()
        : DateTime.tryParse(
                '${_scheduleDateController.text.trim()}T00:00:00') ??
            DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Schedule Date',
    );
    if (picked == null) {
      return;
    }
    _scheduleDateController.text = _formatDateId(picked);
  }

  Future<void> _selectScheduleTime() async {
    final picked = await _pickScheduleTime(context);
    if (picked == null) {
      return;
    }
    _scheduleTimeController.text = picked;
  }

  bool _isValidDateId(String value) {
    final pattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!pattern.hasMatch(value)) {
      return false;
    }
    return DateTime.tryParse('${value}T00:00:00Z') != null;
  }
}

class _LabResultDialog extends StatefulWidget {
  const _LabResultDialog({
    required this.initialValue,
  });

  final LabTestModel initialValue;

  @override
  State<_LabResultDialog> createState() => _LabResultDialogState();
}

class _LabResultDialogState extends State<_LabResultDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _resultValueController;
  late final TextEditingController _resultUnitController;
  late final TextEditingController _referenceRangeController;
  late final TextEditingController _interpretationController;
  late DateTime _resultAt;
  String? _resultFlag;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _resultValueController =
        TextEditingController(text: initial.resultValue ?? '');
    _resultUnitController =
        TextEditingController(text: initial.resultUnit ?? '');
    _referenceRangeController =
        TextEditingController(text: initial.referenceRange ?? '');
    _interpretationController =
        TextEditingController(text: initial.interpretation ?? '');
    _resultFlag = initial.resultFlag;
    _resultAt = DateTime.tryParse(initial.resultAt ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _resultValueController.dispose();
    _resultUnitController.dispose();
    _referenceRangeController.dispose();
    _interpretationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Lab Result'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _resultValueController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Result Value',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Result value is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _resultUnitController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Result Unit (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _referenceRangeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Reference Range (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _resultFlag,
                  decoration: const InputDecoration(
                    labelText: 'Result Flag (optional)',
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Not set'),
                    ),
                    ..._labResultFlagOptions.map(
                      (flag) => DropdownMenuItem<String?>(
                        value: flag,
                        child: Text(flag),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _resultFlag = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectResultDate,
                        icon: const Icon(Icons.event_outlined),
                        label: Text(_formatDateId(_resultAt)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectResultTime,
                        icon: const Icon(Icons.schedule_outlined),
                        label: Text(_formatTimeOfDay(
                            TimeOfDay.fromDateTime(_resultAt))),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _interpretationController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Interpretation (optional)',
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
          child: const Text('Save Result'),
        ),
      ],
    );
  }

  Future<void> _selectResultDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _resultAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Result Date',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _resultAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _resultAt.hour,
        _resultAt.minute,
      );
    });
  }

  Future<void> _selectResultTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_resultAt),
      helpText: 'Select Result Time',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      _resultAt = DateTime(
        _resultAt.year,
        _resultAt.month,
        _resultAt.day,
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

    final resultUnit = _resultUnitController.text.trim();
    final referenceRange = _referenceRangeController.text.trim();
    final interpretation = _interpretationController.text.trim();

    Navigator.of(context).pop(
      _LabResultDraft(
        resultValue: _resultValueController.text.trim(),
        resultAt: _resultAt,
        resultUnit: resultUnit.isEmpty ? null : resultUnit,
        referenceRange: referenceRange.isEmpty ? null : referenceRange,
        interpretation: interpretation.isEmpty ? null : interpretation,
        resultFlag: _resultFlag,
      ),
    );
  }
}

class _LabStatusChip extends StatelessWidget {
  const _LabStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().toLowerCase();
    final color = switch (normalized) {
      'scheduled' => Colors.blue.shade700,
      'in_progress' => Colors.orange.shade700,
      'completed' => Colors.green.shade700,
      'cancelled' || 'canceled' => Colors.grey.shade700,
      _ => Colors.blueGrey.shade700,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _displayLabTestStatus(normalized),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

bool _canManageRecords(String? role) {
  return role == 'admin' || role == 'supervisor';
}

bool _canManageLabTests(String? role) {
  return role == 'admin' || role == 'supervisor' || role == 'nurse';
}

const List<String> _medicineDoseUnitOptions = <String>[
  'mg',
  'ml',
  'tablet',
  'capsule',
  'units',
];

const List<String> _medicineRecurrenceUnitOptions = <String>[
  'days',
  'weeks',
  'months',
];

const List<String> _procedureFrequencyOptions = <String>[
  'once',
  'daily',
  'weekly',
  'as_needed',
];

const List<String> _labTestStatusOptions = <String>[
  'scheduled',
  'in_progress',
  'completed',
  'cancelled',
];

const List<String> _labPriorityOptions = <String>[
  'routine',
  'urgent',
  'stat',
];

const List<String> _labResultFlagOptions = <String>[
  'normal',
  'low',
  'high',
  'critical',
  'abnormal',
];

const List<String> _healthCheckPlanItemTypes = <String>[
  'blood_pressure',
  'blood_glucose',
  'wounds',
  'other',
];

const List<String> _healthCheckPlanTimingOptions = <String>[
  'before_food',
  'after_food',
  'anytime',
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
    required this.startDate,
    required this.recurrenceMode,
    required this.recurrenceEvery,
    required this.recurrenceUnit,
    required this.active,
    required this.scheduleTimes,
  });

  final String name;
  final String? instructions;
  final num? doseAmount;
  final String? doseUnit;
  final String? startDate;
  final String recurrenceMode;
  final int? recurrenceEvery;
  final String? recurrenceUnit;
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
  late final TextEditingController _recurrenceEveryController;
  late String? _doseUnit;
  late final List<String> _scheduleTimes;
  late String _recurrenceMode;
  late String _recurrenceUnit;
  DateTime? _startDate;
  late bool _active;
  bool _showStartDateValidationError = false;

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
    _recurrenceMode =
        initial?.isIntervalRecurrence == true ? 'interval' : 'daily';
    _recurrenceUnit =
        _normalizeMedicineRecurrenceUnit(initial?.recurrenceUnit) ?? 'days';
    _recurrenceEveryController = TextEditingController(
      text: (initial?.recurrenceEvery ?? 2).toString(),
    );
    _startDate = _parseDateId(initial?.startDate);
    _active = initial?.active ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _instructionsController.dispose();
    _doseAmountController.dispose();
    _recurrenceEveryController.dispose();
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
                _buildStartDateRow(context),
                const SizedBox(height: 8),
                _buildAlternativeEditor(context),
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
    final recurrenceEveryRaw = _recurrenceEveryController.text.trim();
    final recurrenceEvery = int.tryParse(recurrenceEveryRaw);
    final startDate = _startDate == null ? null : _formatDateId(_startDate!);

    if (_recurrenceMode == 'interval' && startDate == null) {
      setState(() {
        _showStartDateValidationError = true;
      });
      return;
    }

    Navigator.of(context).pop(
      _MedicineDraft(
        name: _nameController.text.trim(),
        instructions: instructions.isEmpty ? null : instructions,
        doseAmount: doseRaw.isEmpty ? null : num.tryParse(doseRaw),
        doseUnit: _doseUnit,
        startDate: startDate,
        recurrenceMode: _recurrenceMode,
        recurrenceEvery: _recurrenceMode == 'interval' ? recurrenceEvery : null,
        recurrenceUnit: _recurrenceMode == 'interval' ? _recurrenceUnit : null,
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

  Widget _buildStartDateRow(BuildContext context) {
    final label = _startDate == null
        ? 'Add Starting Date of dose'
        : _formatDateId(_startDate!);

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            'Date',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        TextButton(
          onPressed: _pickStartDate,
          child: Text(label),
        ),
      ],
    );
  }

  Widget _buildAlternativeEditor(BuildContext context) {
    final isDaily = _recurrenceMode == 'daily';
    final isInterval = _recurrenceMode == 'interval';
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Alternative',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  Checkbox(
                    value: isDaily,
                    onChanged: (_) => _setRecurrenceMode('daily'),
                  ),
                  Expanded(
                    child: _RecurrenceLabelChip(
                      label: 'Every day',
                      active: isDaily,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isDaily,
                    onChanged: (value) {
                      _setRecurrenceMode(value ? 'daily' : 'interval');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Checkbox(
                    value: isInterval,
                    onChanged: (_) => _setRecurrenceMode('interval'),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _RecurrenceLabelChip(
                          label: 'Each',
                          active: isInterval,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: <Widget>[
                            SizedBox(
                              width: 82,
                              child: TextFormField(
                                controller: _recurrenceEveryController,
                                enabled: isInterval,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                ),
                                validator: (value) {
                                  if (!isInterval) {
                                    return null;
                                  }
                                  final parsed =
                                      int.tryParse((value ?? '').trim());
                                  if (parsed == null || parsed < 1) {
                                    return '1+';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _recurrenceUnit,
                                decoration: const InputDecoration(
                                  isDense: true,
                                ),
                                items: _medicineRecurrenceUnitOptions
                                    .map(
                                      (unit) => DropdownMenuItem<String>(
                                        value: unit,
                                        child: Text(_toTitleCase(unit)),
                                      ),
                                    )
                                    .toList(),
                                onChanged: isInterval
                                    ? (value) {
                                        if (value == null) {
                                          return;
                                        }
                                        setState(() {
                                          _recurrenceUnit = value;
                                        });
                                      }
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: isInterval,
                    onChanged: (value) {
                      _setRecurrenceMode(value ? 'interval' : 'daily');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if (isInterval && _showStartDateValidationError && _startDate == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Starting date is required when using interval recurrence.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  Future<void> _pickStartDate() async {
    final initial = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Select Starting Date',
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _showStartDateValidationError = false;
    });
  }

  void _setRecurrenceMode(String mode) {
    setState(() {
      _recurrenceMode = mode == 'interval' ? 'interval' : 'daily';
      if (_recurrenceMode == 'daily') {
        _showStartDateValidationError = false;
      }
    });
  }
}

class _RecurrenceLabelChip extends StatelessWidget {
  const _RecurrenceLabelChip({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? scheme.surface : scheme.surface.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Text(label),
    );
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
  static const _noInsulinValue = '__none__';
  static const _customInsulinValue = '__custom__';
  static const _customSlidingScaleValue = '__custom__';
  static const Map<String, List<String>> _insulinOptionsByType =
      <String, List<String>>{
    'rapid': <String>[
      'Humalog',
      'NovoLog',
      'Apidra',
      'Fiasp',
      'Lyumjev',
    ],
    'basal': <String>[
      'Lantus',
      'Levemir',
      'Tresiba',
      'Toujeo',
      'Basaglar',
    ],
  };
  static const Map<String, List<String>> _quickTimesByType =
      <String, List<String>>{
    'rapid': <String>['08:00', '13:00', '19:00'],
    'basal': <String>['08:00', '21:00'],
  };
  static const List<_SlidingScalePreset> _slidingScalePresets =
      <_SlidingScalePreset>[
    _SlidingScalePreset(
      id: 'none',
      label: 'None',
      thresholds: <num>[],
    ),
    _SlidingScalePreset(
      id: 'standard',
      label: 'Standard (150 / 200 / 250)',
      thresholds: <num>[150, 200, 250],
    ),
    _SlidingScalePreset(
      id: 'tight',
      label: 'Tight (140 / 180 / 220 / 260)',
      thresholds: <num>[140, 180, 220, 260],
    ),
    _SlidingScalePreset(
      id: 'gentle',
      label: 'Gentle (160 / 220 / 280)',
      thresholds: <num>[160, 220, 280],
    ),
    _SlidingScalePreset(
      id: _customSlidingScaleValue,
      label: 'Custom',
      thresholds: <num>[],
    ),
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _customInsulinNameController;
  late final TextEditingController _notesController;
  late final TextEditingController _slidingScaleController;
  late final Map<String, TextEditingController> _mealBaseControllers;
  late final List<String> _scheduleTimes;
  late String _type;
  late String _selectedInsulinOption;
  late String _selectedSlidingScalePreset;
  late bool _active;
  late bool _showAdvanced;
  late double _defaultBaseUnitsValue;
  late double _fixedUnitsValue;
  late bool _defaultBaseUnitsTouched;
  late bool _fixedUnitsTouched;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _type = initial?.type == 'basal' ? 'basal' : 'rapid';
    _active = initial?.active ?? true;

    final initialGeneratedLabel = _generatedLabel(
      type: _type,
      insulinName: initial?.insulinName,
    );
    _labelController = TextEditingController(
      text: initial != null && initial.label.trim() != initialGeneratedLabel
          ? initial.label
          : '',
    );
    _selectedInsulinOption = _resolveInitialInsulinOption(initial?.insulinName);
    _customInsulinNameController = TextEditingController(
      text: _selectedInsulinOption == _customInsulinValue
          ? initial?.insulinName ?? ''
          : '',
    );
    _scheduleTimes = List<String>.from(initial?.scheduleTimes ?? <String>[])
      ..sort();
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _selectedSlidingScalePreset =
        _matchSlidingScalePreset(initial?.slidingScaleMgdl ?? const <num>[]);
    _slidingScaleController = TextEditingController(
      text: _selectedSlidingScalePreset == _customSlidingScaleValue
          ? initial?.slidingScaleMgdl.join(', ') ?? ''
          : '',
    );
    _defaultBaseUnitsValue = initial?.defaultBaseUnits?.toDouble() ?? 0;
    _fixedUnitsValue = initial?.fixedUnits?.toDouble() ?? 0;
    _defaultBaseUnitsTouched = initial?.defaultBaseUnits != null;
    _fixedUnitsTouched = initial?.fixedUnits != null;
    _mealBaseControllers = <String, TextEditingController>{
      for (final tag in _mealTags)
        tag: TextEditingController(
          text: initial?.mealBaseUnits[tag]?.toString() ?? '',
        ),
    };
    _showAdvanced = _shouldShowAdvancedInitially(initial);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _customInsulinNameController.dispose();
    _notesController.dispose();
    _slidingScaleController.dispose();
    for (final controller in _mealBaseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;
    final quickTimes = _quickTimesByType[_type] ?? const <String>[];
    return AlertDialog(
      title: Text(isEditing ? 'Edit Insulin Profile' : 'Add Insulin Profile'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                      _syncInsulinSelectionForType();
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _selectedInsulinOption,
                  decoration: const InputDecoration(labelText: 'Insulin'),
                  items: _buildInsulinItems(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _selectedInsulinOption = value;
                    });
                  },
                ),
                if (_selectedInsulinOption == _customInsulinValue) ...<Widget>[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _customInsulinNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Custom insulin name (optional)',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Profile name: ${_resolveLabel()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _ScheduleTimeEditor(
                  label: 'Dose Times',
                  times: _scheduleTimes,
                  onAddTime: _pickAndAddScheduleTime,
                  onRemoveTime: (time) {
                    setState(() {
                      _setScheduleTimes(
                        _scheduleTimes.where((entry) => entry != time),
                      );
                    });
                  },
                ),
                if (quickTimes.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Quick picks',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: quickTimes
                        .map(
                          (time) => FilterChip(
                            label: Text(time),
                            selected: _scheduleTimes.contains(time),
                            onSelected: (_) => _toggleScheduleTime(time),
                          ),
                        )
                        .toList(),
                  ),
                ],
                const SizedBox(height: 10),
                if (_type == 'rapid') ...<Widget>[
                  _DoseSliderField(
                    label: 'Typical meal dose',
                    value: _defaultBaseUnitsValue,
                    max: _doseSliderMax(
                      _defaultBaseUnitsValue,
                      fallback: 20,
                    ),
                    helperText:
                        'Leave at 0 if the dose should come only from meal overrides.',
                    onChanged: (value) {
                      setState(() {
                        _defaultBaseUnitsValue = value;
                        _defaultBaseUnitsTouched = true;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSlidingScalePreset,
                    decoration: const InputDecoration(
                      labelText: 'Sliding scale',
                    ),
                    items: _buildSlidingScaleItems(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _selectedSlidingScalePreset = value;
                      });
                    },
                  ),
                  if (_selectedSlidingScalePreset == _customSlidingScaleValue)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TextFormField(
                        controller: _slidingScaleController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Custom thresholds',
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
                    ),
                ] else ...<Widget>[
                  _DoseSliderField(
                    label: 'Daily dose',
                    value: _fixedUnitsValue,
                    max: _doseSliderMax(_fixedUnitsValue, fallback: 40),
                    helperText:
                        'Leave at 0 if this profile should not use a fixed daily dose.',
                    onChanged: (value) {
                      setState(() {
                        _fixedUnitsValue = value;
                        _fixedUnitsTouched = true;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAdvanced = !_showAdvanced;
                    });
                  },
                  icon: Icon(
                    _showAdvanced ? Icons.expand_less : Icons.tune_outlined,
                  ),
                  label: Text(
                    _showAdvanced
                        ? 'Hide advanced options'
                        : 'Show advanced options',
                  ),
                ),
                if (_showAdvanced) ...<Widget>[
                  TextFormField(
                    controller: _labelController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Custom display name (optional)',
                      hintText: 'Defaults to the insulin name',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_type == 'rapid') ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      'Meal-specific overrides',
                      style: Theme.of(context).textTheme.titleSmall,
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
                            labelText: '${_mealTagLabel(tag)} dose (optional)',
                          ),
                          validator: _optionalNumberValidator,
                        ),
                      );
                    }),
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
                ],
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

    final notes = _notesController.text.trim();

    Navigator.of(context).pop(
      _InsulinProfileDraft(
        type: _type,
        label: _resolveLabel(),
        insulinName: _resolveInsulinName(),
        active: _active,
        scheduleTimes: _scheduleTimes.toList()..sort(),
        slidingScaleMgdl:
            _type == 'rapid' ? _resolveSlidingScaleMgdl() : const <num>[],
        mealBaseUnits: _type == 'rapid' ? mealBaseUnits : const <String, num>{},
        defaultBaseUnits: _type == 'rapid' && _shouldPersistDefaultBaseUnits()
            ? _defaultBaseUnitsValue
            : null,
        fixedUnits: _type == 'basal' && _shouldPersistFixedUnits()
            ? _fixedUnitsValue
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
      _setScheduleTimes(<String>[..._scheduleTimes, pickedTime]);
    });
  }

  List<DropdownMenuItem<String>> _buildInsulinItems() {
    final options = _insulinOptionsByType[_type] ?? const <String>[];
    return <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: _noInsulinValue,
        child: Text('Not set'),
      ),
      ...options.map(
        (value) => DropdownMenuItem<String>(
          value: value,
          child: Text(value),
        ),
      ),
      const DropdownMenuItem<String>(
        value: _customInsulinValue,
        child: Text('Custom'),
      ),
    ];
  }

  List<DropdownMenuItem<String>> _buildSlidingScaleItems() {
    return _slidingScalePresets
        .map(
          (preset) => DropdownMenuItem<String>(
            value: preset.id,
            child: Text(preset.label),
          ),
        )
        .toList();
  }

  String _resolveInitialInsulinOption(String? insulinName) {
    final normalized = insulinName?.trim();
    if (normalized == null || normalized.isEmpty) {
      return _noInsulinValue;
    }
    final options = _insulinOptionsByType[_type] ?? const <String>[];
    if (options.contains(normalized)) {
      return normalized;
    }
    return _customInsulinValue;
  }

  void _syncInsulinSelectionForType() {
    final options = _insulinOptionsByType[_type] ?? const <String>[];
    if (_selectedInsulinOption == _noInsulinValue ||
        _selectedInsulinOption == _customInsulinValue) {
      return;
    }
    if (!options.contains(_selectedInsulinOption)) {
      _selectedInsulinOption = _customInsulinNameController.text.trim().isEmpty
          ? _noInsulinValue
          : _customInsulinValue;
    }
  }

  bool _shouldShowAdvancedInitially(InsulinProfileModel? initial) {
    if (initial == null) {
      return false;
    }

    final generatedLabel = _generatedLabel(
      type: initial.type == 'basal' ? 'basal' : 'rapid',
      insulinName: initial.insulinName,
    );
    return initial.label.trim() != generatedLabel ||
        _selectedInsulinOption == _customInsulinValue ||
        _selectedSlidingScalePreset == _customSlidingScaleValue ||
        initial.mealBaseUnits.isNotEmpty ||
        (initial.notes?.trim().isNotEmpty ?? false);
  }

  void _toggleScheduleTime(String time) {
    setState(() {
      if (_scheduleTimes.contains(time)) {
        _setScheduleTimes(_scheduleTimes.where((entry) => entry != time));
        return;
      }
      _setScheduleTimes(<String>[..._scheduleTimes, time]);
    });
  }

  void _setScheduleTimes(Iterable<String> times) {
    final normalized = <String>{...times}.toList()..sort();
    _scheduleTimes
      ..clear()
      ..addAll(normalized);
  }

  String _matchSlidingScalePreset(List<num> values) {
    final normalized = _normalizeThresholds(values);
    for (final preset in _slidingScalePresets) {
      if (preset.id == _customSlidingScaleValue) {
        continue;
      }
      if (_sameThresholds(normalized, preset.thresholds)) {
        return preset.id;
      }
    }
    return normalized.isEmpty ? 'none' : _customSlidingScaleValue;
  }

  List<num> _normalizeThresholds(List<num> values) {
    return values
        .map((value) => value.toDouble())
        .where((value) => value.isFinite && value >= 0)
        .toSet()
        .toList()
      ..sort();
  }

  bool _sameThresholds(List<num> left, List<num> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index].toDouble() != right[index].toDouble()) {
        return false;
      }
    }
    return true;
  }

  double _doseSliderMax(double current, {required double fallback}) {
    final safeCurrent = current.isFinite ? current : 0;
    return max(fallback, safeCurrent.ceilToDouble() + 10).toDouble();
  }

  String _mealTagLabel(String tag) {
    if (tag == 'none') {
      return 'Other / none';
    }
    return _toTitleCase(tag);
  }

  String? _resolveInsulinName() {
    if (_selectedInsulinOption == _noInsulinValue) {
      return null;
    }
    if (_selectedInsulinOption == _customInsulinValue) {
      final customName = _customInsulinNameController.text.trim();
      return customName.isEmpty ? null : customName;
    }
    return _selectedInsulinOption;
  }

  String _resolveLabel() {
    final customLabel = _labelController.text.trim();
    if (customLabel.isNotEmpty) {
      return customLabel;
    }
    return _generatedLabel(
      type: _type,
      insulinName: _resolveInsulinName(),
    );
  }

  String _generatedLabel({
    required String type,
    String? insulinName,
  }) {
    final normalizedInsulinName = insulinName?.trim();
    if (normalizedInsulinName != null && normalizedInsulinName.isNotEmpty) {
      return normalizedInsulinName;
    }
    return type == 'basal' ? 'Basal Insulin' : 'Rapid Insulin';
  }

  List<num> _resolveSlidingScaleMgdl() {
    if (_selectedSlidingScalePreset == _customSlidingScaleValue) {
      return _parseNumberCsv(_slidingScaleController.text);
    }

    for (final preset in _slidingScalePresets) {
      if (preset.id == _selectedSlidingScalePreset) {
        return List<num>.from(preset.thresholds);
      }
    }

    return const <num>[];
  }

  bool _shouldPersistDefaultBaseUnits() {
    return _defaultBaseUnitsTouched ||
        widget.initialValue?.defaultBaseUnits != null;
  }

  bool _shouldPersistFixedUnits() {
    return _fixedUnitsTouched || widget.initialValue?.fixedUnits != null;
  }
}

class _SlidingScalePreset {
  const _SlidingScalePreset({
    required this.id,
    required this.label,
    required this.thresholds,
  });

  final String id;
  final String label;
  final List<num> thresholds;
}

class _DoseSliderField extends StatelessWidget {
  const _DoseSliderField({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    final boundedMax = max < 1 ? 1.0 : max;
    final boundedValue = value.clamp(0, boundedMax).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Text(
              '${_formatDoseValue(boundedValue)} units',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        Slider(
          value: boundedValue,
          min: 0,
          max: boundedMax,
          divisions: (boundedMax * 2).round(),
          label: '${_formatDoseValue(boundedValue)} units',
          onChanged: onChanged,
        ),
        if (helperText != null)
          Text(
            helperText!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

String _formatDoseValue(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
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

DateTime? _parseDateId(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse('${raw}T00:00:00');
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String? _normalizeMedicineRecurrenceUnit(String? value) {
  final normalized = value?.trim().toLowerCase();
  switch (normalized) {
    case 'day':
    case 'days':
      return 'days';
    case 'week':
    case 'weeks':
      return 'weeks';
    case 'month':
    case 'months':
      return 'months';
    default:
      return null;
  }
}

String _toTitleCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return value;
  }
  return '${trimmed[0].toUpperCase()}${trimmed.substring(1)}';
}

String _healthCheckPlanItemLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'blood_pressure':
      return 'Blood Pressure / الضغط';
    case 'blood_glucose':
      return 'Blood Glucose / السكري';
    case 'wounds':
      return 'Wounds / الجروح';
    case 'other':
      return 'Other / غير ذلك';
    default:
      return _toTitleCase(value.replaceAll('_', ' '));
  }
}

String _defaultHealthCheckPlanLabel(String itemType) {
  switch (itemType.trim().toLowerCase()) {
    case 'blood_pressure':
      return 'Blood Pressure';
    case 'blood_glucose':
      return 'Blood Glucose';
    case 'wounds':
      return 'Wounds';
    case 'other':
      return 'Other';
    default:
      return 'Health Check';
  }
}

String _healthCheckPlanTimingLabel(String value) {
  switch (value.trim().toLowerCase()) {
    case 'before_food':
      return 'Before food';
    case 'after_food':
      return 'After food';
    case 'anytime':
      return 'Any time';
    default:
      return _toTitleCase(value.replaceAll('_', ' '));
  }
}

String _checklistTaskTypeLabel(ChecklistTaskModel task) {
  switch (task.type.trim().toLowerCase()) {
    case 'medicine':
      return 'Medicine';
    case 'procedure':
      return 'Procedure';
    case 'insulin_rapid':
      return 'Rapid insulin';
    case 'insulin_basal':
      return 'Basal insulin';
    case 'health_check':
      return 'Health check';
    default:
      return _toTitleCase(task.type.replaceAll('_', ' '));
  }
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
                    'Type: ${_checklistTaskTypeLabel(task)}',
                    if (task.isHealthCheck && task.healthCheckTiming != null)
                      'Timing: ${_healthCheckPlanTimingLabel(task.healthCheckTiming!)}',
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

class _HealthCheckPlanDraft {
  const _HealthCheckPlanDraft({
    required this.label,
    required this.itemType,
    required this.timing,
    required this.active,
    required this.notes,
  });

  final String label;
  final String itemType;
  final String timing;
  final bool active;
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
    final canManagePlans = _canManageRecords(role);
    final checksAsync = ref.watch(healthChecksProvider(patientId));
    final plansAsync = ref.watch(healthCheckPlansProvider(patientId));

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

    Future<void> createHealthCheckPlan() async {
      final draft = await showDialog<_HealthCheckPlanDraft>(
        context: context,
        builder: (_) => const _HealthCheckPlanDialog(),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).createHealthCheckPlan(
              patientId: patientId,
              label: draft.label,
              itemType: draft.itemType,
              timing: draft.timing,
              active: draft.active,
              notes: draft.notes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily health check added.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to add daily health check: $error')),
        );
      }
    }

    Future<void> editHealthCheckPlan(HealthCheckPlanModel plan) async {
      final draft = await showDialog<_HealthCheckPlanDraft>(
        context: context,
        builder: (_) => _HealthCheckPlanDialog(initialValue: plan),
      );
      if (draft == null) {
        return;
      }

      try {
        await ref.read(apiClientProvider).updateHealthCheckPlan(
              patientId: patientId,
              healthCheckPlanId: plan.id,
              label: draft.label,
              itemType: draft.itemType,
              timing: draft.timing,
              active: draft.active,
              notes: draft.notes,
            );
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Daily health check updated.')),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to update daily health check: $error'),
          ),
        );
      }
    }

    return plansAsync.when(
      data: (plans) {
        return checksAsync.when(
          data: (checks) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (canManagePlans)
                  _TabActionHeader(
                    label: 'Daily Checklist Health Checks',
                    actionLabel: 'Add Daily Check',
                    onPressed: createHealthCheckPlan,
                  ),
                if (plans.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No daily health checks configured for the checklist.',
                      ),
                    ),
                  )
                else
                  ...plans.map((plan) {
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
                                      plan.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                  if (canManagePlans)
                                    IconButton(
                                      tooltip: 'Edit daily health check',
                                      onPressed: () =>
                                          editHealthCheckPlan(plan),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: <Widget>[
                                  Chip(
                                    label: Text(
                                      _healthCheckPlanItemLabel(plan.itemType),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      _healthCheckPlanTimingLabel(plan.timing),
                                    ),
                                  ),
                                  Chip(
                                    label: Text(
                                      plan.active ? 'Active' : 'Inactive',
                                    ),
                                  ),
                                ],
                              ),
                              if (plan.notes != null &&
                                  plan.notes!.trim().isNotEmpty) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  plan.notes!,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                if (canRecord) ...<Widget>[
                  const SizedBox(height: 4),
                  _TabActionHeader(
                    label: 'Regular Health Checks',
                    actionLabel: 'Add Health Check',
                    onPressed: createHealthCheck,
                  ),
                ],
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
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (check.recordedByUid != null)
                                  Chip(
                                    label: Text(
                                      'by ${check.recordedByUid}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
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
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Text('Unable to load daily health checks: $error'),
      ),
    );
  }
}

class _HealthCheckDialog extends StatefulWidget {
  const _HealthCheckDialog();

  @override
  State<_HealthCheckDialog> createState() => _HealthCheckDialogState();
}

class _HealthCheckPlanDialog extends StatefulWidget {
  const _HealthCheckPlanDialog({
    this.initialValue,
  });

  final HealthCheckPlanModel? initialValue;

  @override
  State<_HealthCheckPlanDialog> createState() => _HealthCheckPlanDialogState();
}

class _HealthCheckPlanDialogState extends State<_HealthCheckPlanDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _notesController;
  late String _itemType;
  late String _timing;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _itemType = initial?.itemType ?? _healthCheckPlanItemTypes.first;
    _timing = initial?.timing ?? _healthCheckPlanTimingOptions.first;
    _active = initial?.active ?? true;
    _labelController = TextEditingController(
      text: initial != null &&
              initial.label.trim() != _defaultHealthCheckPlanLabel(_itemType)
          ? initial.label
          : '',
    );
    _notesController = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialValue != null;

    return AlertDialog(
      title: Text(
        isEditing ? 'Edit Daily Health Check' : 'Add Daily Health Check',
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _itemType,
                  decoration:
                      const InputDecoration(labelText: 'Checklist item'),
                  items: _healthCheckPlanItemTypes
                      .map(
                        (itemType) => DropdownMenuItem<String>(
                          value: itemType,
                          child: Text(_healthCheckPlanItemLabel(itemType)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _itemType = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _timing,
                  decoration:
                      const InputDecoration(labelText: 'Checklist timing'),
                  items: _healthCheckPlanTimingOptions
                      .map(
                        (timing) => DropdownMenuItem<String>(
                          value: timing,
                          child: Text(_healthCheckPlanTimingLabel(timing)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setState(() {
                      _timing = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Custom label (optional)',
                    hintText: 'Defaults to the selected checklist item',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checklist label: ${_resolveLabel()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
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

  String _resolveLabel() {
    final customLabel = _labelController.text.trim();
    if (customLabel.isNotEmpty) {
      return customLabel;
    }
    return _defaultHealthCheckPlanLabel(_itemType);
  }

  void _submit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    final notes = _notesController.text.trim();
    Navigator.of(context).pop(
      _HealthCheckPlanDraft(
        label: _resolveLabel(),
        itemType: _itemType,
        timing: _timing,
        active: _active,
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }
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
  bool _isGeneratingReports = false;

  Future<void> _generateReports() async {
    if (_isGeneratingReports) {
      return;
    }

    setState(() {
      _isGeneratingReports = true;
    });

    try {
      final response = await ref.read(apiClientProvider).generatePatientReports(
            patientId: widget.patientId,
            startDate: _startDate == null ? null : _formatDateId(_startDate!),
            endDate: _endDate == null ? null : _formatDateId(_endDate!),
            maxDays: 180,
          );

      final generatedCountRaw = response['generatedCount'];
      final sourceChecklistCountRaw = response['sourceChecklistCount'];
      final generatedCount =
          generatedCountRaw is num ? generatedCountRaw.toInt() : 0;
      final sourceChecklistCount =
          sourceChecklistCountRaw is num ? sourceChecklistCountRaw.toInt() : 0;

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            generatedCount == 0
                ? 'No reports generated. Create/generate checklists first.'
                : 'Generated $generatedCount report day(s) from $sourceChecklistCount checklist(s).',
          ),
        ),
      );

      ref.invalidate(reportsProvider(widget.patientId));
      ref.invalidate(todayReportProvider(widget.patientId));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report generation failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingReports = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayDateId = ref.watch(todayDateIdProvider);
    final reportsAsync = ref.watch(reportsProvider(widget.patientId));
    return reportsAsync.when(
      data: (reports) {
        if (reports.isEmpty) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _buildDateRangeCard(
                context,
                filteredCount: 0,
                onGenerate: _generateReports,
              ),
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No reports yet. Use "Generate Reports" to build daily reports from existing checklists.',
                  ),
                ),
              ),
            ],
          );
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
                onGenerate: _generateReports,
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
              onGenerate: _generateReports,
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
    required VoidCallback onGenerate,
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
                FilledButton.icon(
                  onPressed: _isGeneratingReports ? null : onGenerate,
                  icon: _isGeneratingReports
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.summarize_outlined),
                  label: const Text('Generate Reports'),
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
  static const ChatMessageModel _introMessage = ChatMessageModel(
    id: 'init',
    fromUser: false,
    text:
        'Ask operational care questions. Clinical diagnosis, prescribing, and dose changes are blocked.',
  );

  final TextEditingController _questionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessageModel> _messages = <ChatMessageModel>[_introMessage];
  bool _loading = false;
  bool _historyLoading = false;
  String? _historyError;
  String? _selectedDateId;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadChatHistory);
  }

  @override
  void dispose() {
    _questionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    if (_historyLoading) {
      return;
    }

    setState(() {
      _historyLoading = true;
      _historyError = null;
    });

    try {
      final logs = await ref.read(apiClientProvider).listAiLogs(
            patientId: widget.patientId,
            limit: 80,
          );

      if (!mounted) {
        return;
      }

      final hydratedMessages = <ChatMessageModel>[_introMessage];
      for (final log in logs) {
        if (log.prompt.isNotEmpty) {
          hydratedMessages.add(
            ChatMessageModel(
              id: 'hq_${log.id}',
              fromUser: true,
              text: log.prompt,
            ),
          );
        }

        if (log.response.isNotEmpty || log.bullets.isNotEmpty) {
          hydratedMessages.add(
            ChatMessageModel(
              id: 'ha_${log.id}',
              fromUser: false,
              text: _formatAssistantText(
                answerText: log.response,
                bullets: log.bullets,
              ),
              meta: _buildAssistantMeta(
                disclaimer: log.disclaimer,
                references: log.references,
                safetyFlags: log.safetyFlags,
              ),
            ),
          );
        }
      }

      setState(() {
        _messages
          ..clear()
          ..addAll(hydratedMessages);
      });
      _scrollToBottom();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _historyError = 'Unable to load previous chat history: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _historyLoading = false;
        });
      }
    }
  }

  Future<void> _send() async {
    final question = _questionController.text.trim();
    if (question.isEmpty || _loading || _historyLoading) {
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

      if (!mounted) {
        return;
      }
      setState(() {
        _messages.add(
          ChatMessageModel(
            id: 'a_${DateTime.now().microsecondsSinceEpoch}',
            fromUser: false,
            text: _formatAssistantText(
              answerText: response.answerText,
              bullets: response.bullets,
            ),
            meta: _buildAssistantMeta(
              disclaimer: response.disclaimer,
              references: response.references,
              safetyFlags: response.safetyFlags,
            ),
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

  String _formatAssistantText({
    required String answerText,
    required List<String> bullets,
  }) {
    final bulletText = bullets.isEmpty
        ? ''
        : '\n\n${bullets.map((item) => '- $item').join('\n')}';
    return '$answerText$bulletText';
  }

  List<String> _buildAssistantMeta({
    required String disclaimer,
    required List<String> references,
    required List<String> safetyFlags,
  }) {
    return <String>[
      if (disclaimer.isNotEmpty) 'Disclaimer: $disclaimer',
      if (references.isNotEmpty) 'References: ${references.join(', ')}',
      if (safetyFlags.isNotEmpty) 'Safety: ${safetyFlags.join(', ')}',
    ];
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
              if (_historyError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _historyError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
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
        if (_historyLoading || _loading)
          const LinearProgressIndicator(minHeight: 2),
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
                  onPressed: (_loading || _historyLoading) ? null : _send,
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

String _displayLabTestStatus(String status) {
  switch (status.trim().toLowerCase()) {
    case 'scheduled':
      return 'Scheduled';
    case 'in_progress':
      return 'In Progress';
    case 'completed':
      return 'Completed';
    case 'cancelled':
    case 'canceled':
      return 'Cancelled';
    default:
      return status;
  }
}

String _formatLabTestSchedule(LabTestModel test) {
  if (test.scheduleDate == null || test.scheduleDate!.trim().isEmpty) {
    return '-';
  }

  final parsedDate = DateTime.tryParse('${test.scheduleDate}T00:00:00');
  final datePart = parsedDate == null
      ? test.scheduleDate!
      : DateFormat('EEE, MMM d, yyyy').format(parsedDate);
  final timePart = test.scheduleTime == null || test.scheduleTime!.isEmpty
      ? ''
      : ' at ${test.scheduleTime}';
  return '$datePart$timePart';
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
