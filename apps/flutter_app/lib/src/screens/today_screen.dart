import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app_localizations.dart';
import '../models.dart';
import '../providers.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final dateId = ref.watch(todayDateIdProvider);
    final visitsAsync = ref.watch(todayVisitsProvider(dateId));

    Future<void> refresh() async {
      ref.invalidate(todayVisitsProvider(dateId));
      await ref.read(todayVisitsProvider(dateId).future);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.todayCare),
        actions: <Widget>[
          IconButton(
            tooltip: l.dashboard,
            onPressed: () => context.go('/dashboard'),
            icon: const Icon(Icons.dashboard_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: l.language,
            icon: const Icon(Icons.language_rounded),
            onSelected: (languageCode) {
              ref.read(localeProvider.notifier).setLocale(Locale(languageCode));
            },
            itemBuilder: (_) => <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'en', child: Text(l.languageEnglish)),
              PopupMenuItem(value: 'ar', child: Text(l.languageArabic)),
            ],
          ),
          IconButton(
            tooltip: l.signOut,
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                context.go('/login');
              }
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: visitsAsync.when(
          data: (visits) => _TodayContent(visits: visits, onRefresh: refresh),
          loading: () =>
              const _ScrollableMessage(child: CircularProgressIndicator()),
          error: (error, _) => _ScrollableMessage(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off_outlined, size: 42),
                const SizedBox(height: 12),
                Text(
                  '${l.unableToLoadVisits}: $error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l.retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayContent extends ConsumerWidget {
  const _TodayContent({required this.visits, required this.onRefresh});

  final List<VisitModel> visits;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final scheduled = visits
        .where((visit) => visit.status == 'scheduled')
        .length;
    final inProgress = visits.where((visit) => visit.isInProgress).length;
    final completed = visits.where((visit) => visit.isCompleted).length;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: <Widget>[
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TodayHero(
                  scheduled: scheduled,
                  inProgress: inProgress,
                  completed: completed,
                ),
                const SizedBox(height: 18),
                if (visits.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.event_available_outlined,
                            size: 44,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.noVisitsToday,
                            style: Theme.of(context).textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l.refresh),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...visits.map(
                    (visit) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _VisitCard(visit: visit),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.scheduled,
    required this.inProgress,
    required this.completed,
  });

  final int scheduled;
  final int inProgress;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primary, scheme.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l.todayCare,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l.todayCareSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HeroStat(label: l.scheduled, value: scheduled),
              _HeroStat(label: l.inProgress, value: inProgress),
              _HeroStat(label: l.completed, value: completed),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _VisitCard extends ConsumerStatefulWidget {
  const _VisitCard({required this.visit});

  final VisitModel visit;

  @override
  ConsumerState<_VisitCard> createState() => _VisitCardState();
}

class _VisitCardState extends ConsumerState<_VisitCard> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final visit = widget.visit;
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final statusColor = visit.isCompleted
        ? const Color(0xFF067647)
        : visit.needsAttention
        ? scheme.error
        : visit.isInProgress
        ? const Color(0xFFB54708)
        : scheme.primary;
    final statusLabel = visit.isCompleted
        ? l.completed
        : visit.isInProgress
        ? l.inProgress
        : l.scheduled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    visit.patientName.isEmpty ? '?' : visit.patientName[0],
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        visit.patientName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        visit.scheduledStart == null
                            ? '${visit.completedTaskCount}/${visit.taskCount} ${l.tasksComplete}'
                            : '${visit.scheduledStart} • ${visit.completedTaskCount}/${visit.taskCount} ${l.tasksComplete}',
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: visit.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
            ),
            if (visit.issueCount > 0) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded, color: scheme.error),
                  const SizedBox(width: 6),
                  Text(
                    '${visit.issueCount} ${l.needsAttention.toLowerCase()}',
                    style: TextStyle(
                      color: scheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _starting ? null : _openVisit,
                  icon: _starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          visit.isCompleted
                              ? Icons.visibility_outlined
                              : visit.isInProgress
                              ? Icons.play_arrow_rounded
                              : Icons.login_rounded,
                        ),
                  label: Text(
                    visit.isCompleted
                        ? l.openVisit
                        : visit.isInProgress
                        ? l.continueVisit
                        : l.startVisit,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/patient/${visit.patientId}'),
                  icon: const Icon(Icons.person_outline_rounded),
                  label: Text(l.patient),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVisit() async {
    final visit = widget.visit;
    setState(() => _starting = true);
    try {
      if (!visit.isCompleted && !visit.isInProgress) {
        await ref.read(apiClientProvider).startVisit(visitId: visit.id);
      }
      ref.invalidate(visitProvider(visit.id));
      ref.invalidate(todayVisitsProvider(visit.dateId));
      if (mounted) {
        context.push('/visit/${visit.id}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }
}

class _ScrollableMessage extends StatelessWidget {
  const _ScrollableMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(28),
      children: <Widget>[
        const SizedBox(height: 120),
        Center(child: child),
      ],
    );
  }
}
