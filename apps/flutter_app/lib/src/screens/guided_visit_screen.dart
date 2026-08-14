import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app_localizations.dart';
import '../models.dart';
import '../providers.dart';
import '../services/insulin_preview.dart';

class GuidedVisitScreen extends ConsumerStatefulWidget {
  const GuidedVisitScreen({required this.visitId, super.key});

  final String visitId;

  @override
  ConsumerState<GuidedVisitScreen> createState() => _GuidedVisitScreenState();
}

class _GuidedVisitScreenState extends ConsumerState<GuidedVisitScreen> {
  final Map<String, TextEditingController> _glucoseControllers =
      <String, TextEditingController>{};
  final Map<String, String> _mealTags = <String, String>{};
  String? _selectedTaskId;
  String? _busyTaskId;
  bool _finishing = false;

  @override
  void dispose() {
    for (final controller in _glucoseControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final visitAsync = ref.watch(visitProvider(widget.visitId));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l.backToToday,
          onPressed: () => context.go('/today'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Text(l.guidedCare),
      ),
      body: visitAsync.when(
        data: _buildVisit,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: '$error',
          onRetry: () => ref.invalidate(visitProvider(widget.visitId)),
        ),
      ),
    );
  }

  Widget _buildVisit(VisitModel visit) {
    final checklistAsync = ref.watch(
      checklistProvider(
        ChecklistQuery(patientId: visit.patientId, dateId: visit.dateId),
      ),
    );
    final patient = ref.watch(patientProvider(visit.patientId)).value;
    final insulinProfiles =
        ref.watch(insulinProfilesProvider(visit.patientId)).value ??
        const <InsulinProfileModel>[];

    return checklistAsync.when(
      data: (checklist) {
        if (checklist == null || checklist.tasks.isEmpty) {
          return _EmptyVisit(
            visit: visit,
            onOpenPatient: () => context.push('/patient/${visit.patientId}'),
          );
        }

        final resultByTaskId = checklist.resultByTaskId();
        final selectedIndex = _resolveSelectedIndex(
          checklist.tasks,
          visit.currentTaskId,
        );
        final task = checklist.tasks[selectedIndex];
        final result = resultByTaskId[task.id];
        final profileById = <String, InsulinProfileModel>{
          for (final profile in insulinProfiles) profile.id: profile,
        };

        return Column(
          children: <Widget>[
            _VisitHeader(visit: visit, patient: patient, checklist: checklist),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _TaskPosition(
                          current: selectedIndex + 1,
                          total: checklist.tasks.length,
                        ),
                        const SizedBox(height: 10),
                        _GuidedTaskCard(
                          task: task,
                          result: result,
                          busy: _busyTaskId == task.id,
                          glucoseController: task.isInsulinRapid
                              ? _glucoseController(task.id, result?.glucoseMgDl)
                              : null,
                          mealTag: task.isInsulinRapid
                              ? _mealTags.putIfAbsent(
                                  task.id,
                                  () => result?.mealTag ?? 'none',
                                )
                              : null,
                          insulinProfile: task.insulinProfileId == null
                              ? null
                              : profileById[task.insulinProfileId],
                          onMealChanged: (value) {
                            setState(() => _mealTags[task.id] = value);
                          },
                          onInputChanged: () => setState(() {}),
                          onDone: visit.isCompleted
                              ? null
                              : () => _submitDone(visit: visit, task: task),
                          onPatientDeclined: visit.isCompleted
                              ? null
                              : () => _recordException(
                                  visit: visit,
                                  task: task,
                                  outcomeReason: 'patient_declined',
                                ),
                          onUnable: visit.isCompleted
                              ? null
                              : () => _recordException(
                                  visit: visit,
                                  task: task,
                                  outcomeReason: 'unable_to_complete',
                                ),
                          onNeedHelp: visit.isCompleted
                              ? null
                              : () => _recordException(
                                  visit: visit,
                                  task: task,
                                  outcomeReason: 'needs_help',
                                ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: selectedIndex == 0
                                    ? null
                                    : () => _selectTask(
                                        checklist.tasks[selectedIndex - 1],
                                      ),
                                icon: const Icon(Icons.chevron_left_rounded),
                                label: Text(
                                  AppLocalizations.of(context).previousTask,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed:
                                    selectedIndex == checklist.tasks.length - 1
                                    ? null
                                    : () => _selectTask(
                                        checklist.tasks[selectedIndex + 1],
                                      ),
                                icon: const Icon(Icons.chevron_right_rounded),
                                label: Text(
                                  AppLocalizations.of(context).nextTask,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _FinishVisitCard(
                          visit: visit,
                          checklist: checklist,
                          finishing: _finishing,
                          onFinish: visit.isCompleted
                              ? () => context.go('/today')
                              : () => _finishVisit(visit, checklist),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        message: '$error',
        onRetry: () => ref.invalidate(
          checklistProvider(
            ChecklistQuery(patientId: visit.patientId, dateId: visit.dateId),
          ),
        ),
      ),
    );
  }

  int _resolveSelectedIndex(
    List<ChecklistTaskModel> tasks,
    String? currentTaskId,
  ) {
    final requestedId = _selectedTaskId ?? currentTaskId;
    final requestedIndex = tasks.indexWhere(
      (candidate) => candidate.id == requestedId,
    );
    return requestedIndex >= 0 ? requestedIndex : 0;
  }

  void _selectTask(ChecklistTaskModel task) {
    setState(() => _selectedTaskId = task.id);
  }

  TextEditingController _glucoseController(String taskId, num? initialValue) {
    return _glucoseControllers.putIfAbsent(
      taskId,
      () => TextEditingController(text: initialValue?.toString() ?? ''),
    );
  }

  Future<void> _submitDone({
    required VisitModel visit,
    required ChecklistTaskModel task,
  }) async {
    final inputs = <String, dynamic>{};
    if (task.isInsulinRapid) {
      final glucose = double.tryParse(
        _glucoseControllers[task.id]?.text.trim() ?? '',
      );
      if (glucose == null) {
        _showSnack('Enter glucose before completing this insulin task.');
        return;
      }
      inputs['glucoseMgDl'] = glucose;
      inputs['mealTag'] = _mealTags[task.id] ?? 'none';
    }
    await _updateTask(visit: visit, task: task, status: 'done', inputs: inputs);
  }

  Future<void> _recordException({
    required VisitModel visit,
    required ChecklistTaskModel task,
    required String outcomeReason,
  }) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => _OutcomeDialog(outcomeReason: outcomeReason),
    );
    if (note == null) {
      return;
    }
    await _updateTask(
      visit: visit,
      task: task,
      status: outcomeReason == 'patient_declined' ? 'skipped' : 'failed',
      inputs: <String, dynamic>{'outcomeReason': outcomeReason, 'note': note},
    );
  }

  Future<void> _updateTask({
    required VisitModel visit,
    required ChecklistTaskModel task,
    required String status,
    required Map<String, dynamic> inputs,
  }) async {
    if (_busyTaskId != null) {
      return;
    }
    final l = AppLocalizations.of(context);
    setState(() => _busyTaskId = task.id);
    try {
      await ref
          .read(apiClientProvider)
          .updateChecklistTask(
            patientId: visit.patientId,
            date: visit.dateId,
            taskId: task.id,
            status: status,
            inputs: inputs.isEmpty ? null : inputs,
          );
      ref.invalidate(visitProvider(visit.id));
      ref.invalidate(todayVisitsProvider(visit.dateId));
      _advanceAfter(task, visit);
      _showSnack(l.taskUpdated);
    } catch (error) {
      _showSnack('${l.unableToUpdateTask}: $error');
    } finally {
      if (mounted) {
        setState(() => _busyTaskId = null);
      }
    }
  }

  void _advanceAfter(ChecklistTaskModel task, VisitModel visit) {
    final checklist = ref
        .read(
          checklistProvider(
            ChecklistQuery(patientId: visit.patientId, dateId: visit.dateId),
          ),
        )
        .value;
    if (checklist == null) {
      return;
    }
    final index = checklist.tasks.indexWhere((item) => item.id == task.id);
    if (index >= 0 && index + 1 < checklist.tasks.length) {
      setState(() => _selectedTaskId = checklist.tasks[index + 1].id);
    }
  }

  Future<void> _finishVisit(
    VisitModel visit,
    DailyChecklistModel checklist,
  ) async {
    final pending = _pendingTaskCount(checklist);
    if (pending > 0) {
      _showSnack(
        '${AppLocalizations.of(context).pendingTasksRemain} ($pending)',
      );
      return;
    }
    final note = await showDialog<String?>(
      context: context,
      builder: (_) => _VisitCompletionDialog(checklist: checklist),
    );
    if (note == null || !mounted) {
      return;
    }

    setState(() => _finishing = true);
    try {
      await ref
          .read(apiClientProvider)
          .completeVisit(visitId: visit.id, summaryNote: note);
      ref.invalidate(todayVisitsProvider(visit.dateId));
      ref.invalidate(visitProvider(visit.id));
      if (mounted) {
        _showSnack(AppLocalizations.of(context).visitCompleted);
        context.go('/today');
      }
    } catch (error) {
      _showSnack('$error');
    } finally {
      if (mounted) {
        setState(() => _finishing = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _VisitHeader extends StatelessWidget {
  const _VisitHeader({
    required this.visit,
    required this.patient,
    required this.checklist,
  });

  final VisitModel visit;
  final PatientModel? patient;
  final DailyChecklistModel checklist;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final completed = checklist.results
        .where((result) => _isResolved(result.status))
        .length;
    final progress = checklist.tasks.isEmpty
        ? 0.0
        : completed / checklist.tasks.length;
    final warnings = <String>[...?patient?.allergies, ...?patient?.riskFlags];
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            visit.patientName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '$completed/${checklist.tasks.length} ${AppLocalizations.of(context).tasksComplete}',
                          ),
                        ],
                      ),
                    ),
                    if (visit.isCompleted)
                      const Icon(
                        Icons.verified_rounded,
                        color: Color(0xFF067647),
                        size: 30,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                ),
                if (warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.warning_amber_rounded,
                          color: scheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            warnings.join(' • '),
                            style: TextStyle(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskPosition extends StatelessWidget {
  const _TaskPosition({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      '${AppLocalizations.of(context).taskOf} $current / $total',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _GuidedTaskCard extends StatelessWidget {
  const _GuidedTaskCard({
    required this.task,
    required this.result,
    required this.busy,
    required this.glucoseController,
    required this.mealTag,
    required this.insulinProfile,
    required this.onMealChanged,
    required this.onInputChanged,
    required this.onDone,
    required this.onPatientDeclined,
    required this.onUnable,
    required this.onNeedHelp,
  });

  final ChecklistTaskModel task;
  final ChecklistResultModel? result;
  final bool busy;
  final TextEditingController? glucoseController;
  final String? mealTag;
  final InsulinProfileModel? insulinProfile;
  final ValueChanged<String> onMealChanged;
  final VoidCallback onInputChanged;
  final VoidCallback? onDone;
  final VoidCallback? onPatientDeclined;
  final VoidCallback? onUnable;
  final VoidCallback? onNeedHelp;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = result?.status ?? 'pending';
    final resolved = _isResolved(status);
    final preview = _dosePreview();

    return Semantics(
      label: task.title,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _taskIcon(task),
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          task.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (task.scheduledTime != null)
                          Text(
                            task.scheduledTime!,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                      ],
                    ),
                  ),
                  _OutcomeChip(status: status),
                ],
              ),
              if (task.notes != null && task.notes!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.notes!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
              if (task.isInsulinRapid) ...<Widget>[
                const SizedBox(height: 18),
                TextField(
                  controller: glucoseController,
                  enabled: !resolved && !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => onInputChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Glucose (mg/dL)',
                    prefixIcon: Icon(Icons.bloodtype_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: mealTag ?? 'none',
                  decoration: const InputDecoration(
                    labelText: 'Meal context',
                    prefixIcon: Icon(Icons.restaurant_outlined),
                  ),
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
                  onChanged: resolved || busy
                      ? null
                      : (value) {
                          if (value != null) {
                            onMealChanged(value);
                          }
                        },
                ),
                if (preview != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Documented plan preview: ${preview.total} units '
                    '(base ${preview.base}, sliding ${preview.sliding})',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (preview.lowGlucose || preview.highGlucose)
                    Text(
                      preview.lowGlucose
                          ? 'Low glucose safety flag — follow the approved escalation plan.'
                          : 'High glucose safety flag — follow the approved escalation plan.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ],
              if (result?.note != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  '${l.notes}: ${result!.note}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 22),
              if (busy)
                const Center(child: CircularProgressIndicator())
              else if (resolved)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF067647).withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF067647),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusLabel(status),
                          style: const TextStyle(
                            color: Color(0xFF067647),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...<Widget>[
                FilledButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.markDone),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: onPatientDeclined,
                      child: Text(l.patientDeclined),
                    ),
                    OutlinedButton(
                      onPressed: onUnable,
                      child: Text(l.couldNotComplete),
                    ),
                    OutlinedButton.icon(
                      onPressed: onNeedHelp,
                      icon: const Icon(Icons.support_agent_rounded),
                      label: Text(l.needHelp),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  RapidDosePreview? _dosePreview() {
    final glucose = double.tryParse(glucoseController?.text.trim() ?? '');
    if (glucose == null || insulinProfile == null || mealTag == null) {
      return null;
    }
    return computeRapidDosePreview(
      mealTag: mealTag!,
      glucoseMgDl: glucose,
      profile: insulinProfile!,
    );
  }
}

class _OutcomeChip extends StatelessWidget {
  const _OutcomeChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final resolved = _isResolved(status);
    final color = resolved
        ? status == 'done' || status == 'completed'
              ? const Color(0xFF067647)
              : Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FinishVisitCard extends StatelessWidget {
  const _FinishVisitCard({
    required this.visit,
    required this.checklist,
    required this.finishing,
    required this.onFinish,
  });

  final VisitModel visit;
  final DailyChecklistModel checklist;
  final bool finishing;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final pending = _pendingTaskCount(checklist);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              visit.isCompleted ? l.visitSummary : l.reviewAndFinish,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              pending == 0
                  ? '${checklist.tasks.length} ${l.tasksComplete}'
                  : '${l.pendingTasksRemain} ($pending)',
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: finishing ? null : onFinish,
              icon: finishing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      visit.isCompleted
                          ? Icons.arrow_back_rounded
                          : Icons.flag_rounded,
                    ),
              label: Text(visit.isCompleted ? l.backToToday : l.finishVisit),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutcomeDialog extends StatefulWidget {
  const _OutcomeDialog({required this.outcomeReason});

  final String outcomeReason;

  @override
  State<_OutcomeDialog> createState() => _OutcomeDialogState();
}

class _OutcomeDialogState extends State<_OutcomeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final title = switch (widget.outcomeReason) {
      'patient_declined' => l.patientDeclined,
      'needs_help' => l.needHelp,
      _ => l.couldNotComplete,
    };
    return AlertDialog(
      title: Text(title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _noteController,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: l.outcomeNote,
            alignLabelWithHint: true,
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? l.noteRequired : null,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) {
              return;
            }
            Navigator.of(context).pop(_noteController.text.trim());
          },
          child: Text(l.saveOutcome),
        ),
      ],
    );
  }
}

class _VisitCompletionDialog extends StatefulWidget {
  const _VisitCompletionDialog({required this.checklist});

  final DailyChecklistModel checklist;

  @override
  State<_VisitCompletionDialog> createState() => _VisitCompletionDialogState();
}

class _VisitCompletionDialogState extends State<_VisitCompletionDialog> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final results = widget.checklist.results;
    final routine = results
        .where(
          (result) => result.status == 'done' || result.status == 'completed',
        )
        .length;
    final exceptions = results
        .where(
          (result) => result.status == 'skipped' || result.status == 'failed',
        )
        .length;
    return AlertDialog(
      title: Text(l.visitSummary),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              '$routine routine • $exceptions ${l.needsAttention.toLowerCase()}',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: l.optionalSummaryNote,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton.icon(
          onPressed: () =>
              Navigator.of(context).pop(_noteController.text.trim()),
          icon: const Icon(Icons.flag_rounded),
          label: Text(l.finishVisit),
        ),
      ],
    );
  }
}

class _EmptyVisit extends StatelessWidget {
  const _EmptyVisit({required this.visit, required this.onOpenPatient});

  final VisitModel visit;
  final VoidCallback onOpenPatient;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.playlist_add_rounded, size: 44),
                const SizedBox(height: 12),
                Text(
                  l.noTasksForVisit,
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(l.generateChecklistFirst, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: onOpenPatient,
                  icon: const Icon(Icons.person_outline_rounded),
                  label: Text(l.patient),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppLocalizations.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }
}

int _pendingTaskCount(DailyChecklistModel checklist) {
  final resultByTaskId = checklist.resultByTaskId();
  return checklist.tasks.where((task) {
    return !_isResolved(resultByTaskId[task.id]?.status ?? 'pending');
  }).length;
}

bool _isResolved(String status) {
  return const <String>{
    'done',
    'completed',
    'late',
    'skipped',
    'failed',
    'missed',
  }.contains(status.toLowerCase());
}

String _statusLabel(String status) {
  return switch (status.toLowerCase()) {
    'done' || 'completed' => 'Done',
    'late' => 'Completed late',
    'skipped' => 'Patient declined / skipped',
    'failed' => 'Could not complete',
    'missed' => 'Missed',
    _ => 'Pending',
  };
}

IconData _taskIcon(ChecklistTaskModel task) {
  return switch (task.type) {
    'medicine' => Icons.medication_outlined,
    'insulin_rapid' || 'insulin_basal' => Icons.vaccines_outlined,
    'procedure' => Icons.medical_services_outlined,
    'health_check' => Icons.monitor_heart_outlined,
    _ => Icons.checklist_rounded,
  };
}
