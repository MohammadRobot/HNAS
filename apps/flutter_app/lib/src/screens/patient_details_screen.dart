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
      length: 7,
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
                    _KeyValue(label: 'Timezone', value: patient.timezone ?? '-'),
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
    final medicinesAsync = ref.watch(medicinesProvider(patientId));
    return medicinesAsync.when(
      data: (medicines) {
        if (medicines.isEmpty) {
          return const Center(child: Text('No medicines.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: medicines.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final medicine = medicines[index];
            final dose = medicine.doseAmount != null
                ? '${medicine.doseAmount} ${medicine.doseUnit ?? ''}'.trim()
                : '-';
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      medicine.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(label: 'Dose', value: dose),
                    _KeyValue(
                      label: 'Instructions',
                      value: medicine.instructions ?? '-',
                    ),
                    _KeyValue(label: 'Status', value: medicine.active ? 'Active' : 'Inactive'),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load medicines: $error')),
    );
  }
}

class _ProceduresTab extends ConsumerWidget {
  const _ProceduresTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proceduresAsync = ref.watch(proceduresProvider(patientId));
    return proceduresAsync.when(
      data: (procedures) {
        if (procedures.isEmpty) {
          return const Center(child: Text('No procedures.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: procedures.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final procedure = procedures[index];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      procedure.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(label: 'Frequency', value: procedure.frequency ?? '-'),
                    _KeyValue(
                      label: 'Instructions',
                      value: procedure.instructions ?? '-',
                    ),
                    _KeyValue(label: 'Status', value: procedure.active ? 'Active' : 'Inactive'),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load procedures: $error')),
    );
  }
}

class _InsulinTab extends ConsumerWidget {
  const _InsulinTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profilesAsync = ref.watch(insulinProfilesProvider(patientId));
    return profilesAsync.when(
      data: (profiles) {
        if (profiles.isEmpty) {
          return const Center(child: Text('No insulin profiles.'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: profiles.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final profile = profiles[index];
            final typeLabel = profile.isRapid ? 'Rapid' : 'Basal';
            final scale = profile.slidingScaleMgdl.isEmpty
                ? '-'
                : profile.slidingScaleMgdl.join(', ');
            final mealBase = profile.mealBaseUnits.isEmpty
                ? '-'
                : profile.mealBaseUnits.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join(', ');

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
                            profile.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text(typeLabel)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _KeyValue(label: 'Insulin', value: profile.insulinName ?? '-'),
                    if (profile.isRapid) ...<Widget>[
                      _KeyValue(label: 'Sliding Scale (mg/dL)', value: scale),
                      _KeyValue(label: 'Meal Base (units)', value: mealBase),
                      _KeyValue(
                        label: 'Default Base Units',
                        value: profile.defaultBaseUnits?.toString() ?? '-',
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load insulin profiles: $error')),
    );
  }
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

  @override
  Widget build(BuildContext context) {
    final dateId = ref.watch(todayDateIdProvider);
    final checklistAsync = ref.watch(
      checklistProvider(
        ChecklistQuery(patientId: widget.patientId, dateId: dateId),
      ),
    );
    final insulinProfilesAsync = ref.watch(insulinProfilesProvider(widget.patientId));

    return checklistAsync.when(
      data: (checklist) {
        if (checklist == null || checklist.tasks.isEmpty) {
          return const Center(
            child: Text('No checklist generated for today yet.'),
          );
        }

        final resultByTask = checklist.resultByTaskId();
        final insulinById = <String, InsulinProfileModel>{
          for (final profile in insulinProfilesAsync.value ?? <InsulinProfileModel>[])
            profile.id: profile,
        };

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: checklist.tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final task = checklist.tasks[index];
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
                  if (task.scheduledTime != null) 'Time: ${task.scheduledTime}',
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
              final controller = _glucoseController(task.id, result?.glucoseMgDl);
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
                        value: mealTag,
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem(value: 'none', child: Text('None')),
                          DropdownMenuItem(
                            value: 'breakfast',
                            child: Text('Breakfast'),
                          ),
                          DropdownMenuItem(value: 'lunch', child: Text('Lunch')),
                          DropdownMenuItem(value: 'dinner', child: Text('Dinner')),
                          DropdownMenuItem(value: 'snack', child: Text('Snack')),
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
                if (preview != null && (preview.lowGlucose || preview.highGlucose))
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

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Unable to load checklist: $error')),
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

class _ReportsTab extends ConsumerWidget {
  const _ReportsTab({required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todayDateId = ref.watch(todayDateIdProvider);
    final reportsAsync = ref.watch(reportsProvider(patientId));
    return reportsAsync.when(
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(child: Text('No reports yet.'));
        }

        final sorted = reports.toList()
          ..sort((left, right) => right.dateId.compareTo(left.dateId));
        final today = sorted.firstWhere(
          (report) => report.dateId == todayDateId,
          orElse: () => sorted.first,
        );

        final currentWeek = _ReportTotals.fromReports(sorted.take(7).toList());
        final previousWeek = _ReportTotals.fromReports(
          sorted.length > 7 ? sorted.skip(7).take(7).toList() : <DailyReportModel>[],
        );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
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
                      'Recent Daily Reports',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    ...sorted.take(7).map((report) {
                      final dateLabel = _formatDate(report.dateId);
                      final total = max(1, report.done + report.missed + report.late + report.skipped);
                      final completion = report.done / total;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('$dateLabel: done ${report.done}, missed ${report.missed}, '
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
      error: (error, _) => Center(child: Text('Unable to load reports: $error')),
    );
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
      text: 'Ask operational care questions. Clinical diagnosis, prescribing, and dose changes are blocked.',
    ),
  ];
  bool _loading = false;

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

    final dateId = ref.read(todayDateIdProvider);
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
        if (response.disclaimer.isNotEmpty) 'Disclaimer: ${response.disclaimer}',
        if (response.references.isNotEmpty) 'References: ${response.references.join(', ')}',
        if (response.safetyFlags.isNotEmpty) 'Safety: ${response.safetyFlags.join(', ')}',
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceVariant,
          child: const Text(
            'AI disclaimer: operational support only, no diagnosis/prescription/dose changes.',
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
                      hintText: 'Ask about workflow, checklist context, or insulin explanation.',
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
        : Theme.of(context).colorScheme.surfaceVariant;

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
    return _ReportTotals(done: done, missed: missed, late: late, skipped: skipped);
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
        color: color.withOpacity(0.12),
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
        color: Theme.of(context).colorScheme.surfaceVariant,
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
