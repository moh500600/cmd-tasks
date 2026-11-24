import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/services/stats_calculator.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/task_tile.dart';
import '../tasks/section_tasks_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final stats = ref.watch(dashboardProvider);
    final h = DateTime.now().hour;
    final greet = context.tr(h < 12 ? 'good_morning' : (h < 18 ? 'good_afternoon' : 'good_evening'));
    return RefreshIndicator(
      onRefresh: () async => ref.read(revisionProvider.notifier).bump(),
      child: AsyncView<DashboardStats>(
        value: stats,
        builder: (s) => LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 900 ? 6 : (c.maxWidth > 600 ? 3 : 2);
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
            Text('$greet${context.isAr ? '، ' : ', '}${user?.name ?? ''} 👋',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(DateFormat('EEEE d MMMM yyyy', context.lang).format(DateTime.now()),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: cols,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: [
                _StatCard(context.tr('stat_total'), s.total, Icons.list_alt_rounded, const Color(0xFF5B5BD6), TaskSection.all),
                _StatCard(context.tr('stat_completed'), s.completed, Icons.check_circle_rounded, const Color(0xFF16A34A), TaskSection.completed),
                _StatCard(context.tr('stat_in_progress'), s.inProgress, Icons.autorenew_rounded, const Color(0xFF3B82F6), null, status: TaskStatus.inProgress),
                _StatCard(context.tr('stat_overdue'), s.overdue, Icons.warning_amber_rounded, const Color(0xFFEF4444), TaskSection.overdue),
                _StatCard(context.tr('stat_not_started'), s.notStarted, Icons.radio_button_unchecked_rounded, const Color(0xFF94A3B8), null, status: TaskStatus.todo),
                _StatCard(context.tr('stat_high_priority'), s.highPriority, Icons.local_fire_department_rounded, const Color(0xFFF59E0B), null, highPriority: true),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Gauge(context.tr('stat_daily_rate'), s.dailyRate, const Color(0xFF14B8A6))),
              const SizedBox(width: 10),
              Expanded(child: _Gauge(context.tr('stat_weekly_rate'), s.weeklyRate, const Color(0xFF8B5CF6))),
            ]),
            SectionHeader(context.tr('productivity_chart')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                child: Column(children: [
                  SizedBox(height: 190, child: _ProductivityChart(stats: s)),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Legend(color: const Color(0xFF16A34A), text: context.tr('completed')),
                    const SizedBox(width: 16),
                    _Legend(color: const Color(0xFF5B5BD6).withValues(alpha: 0.35), text: context.tr('created')),
                  ]),
                ]),
              ),
            ),
            SectionHeader(context.tr('upcoming_tasks'),
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SectionTasksScreen(section: TaskSection.upcoming))),
                  child: Text(context.tr('see_all')),
                )),
            if (s.upcoming.isEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(context.tr('no_upcoming'), textAlign: TextAlign.center)))
            else
              for (final t in s.upcoming) TaskTile(task: t),
          ]);
        }),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final TaskSection? section;
  final TaskStatus? status;
  final bool highPriority;
  const _StatCard(this.label, this.value, this.icon, this.color, this.section, {this.status, this.highPriority = false});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SectionTasksScreen(section: section, status: status, highPriority: highPriority, title: label)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: value.toDouble()),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => Text('${v.round()}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
                ),
              ]),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _Gauge extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Gauge(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(
              width: 62,
              height: 62,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, _) => Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(value: v, strokeWidth: 7, color: color, backgroundColor: color.withValues(alpha: 0.15), strokeCap: StrokeCap.round),
                  ),
                  Text('${(v * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
      );
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend({required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12)),
      ]);
}

class _ProductivityChart extends StatelessWidget {
  final DashboardStats stats;
  const _ProductivityChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final maxY = [...stats.completedLast7Days, ...stats.createdLast7Days].fold<int>(2, (a, b) => b > a ? b : a);
    return BarChart(
      BarChartData(
        maxY: maxY + 1,
        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: (maxY / 4).ceilToDouble().clamp(1, 100)),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: (maxY / 4).ceilToDouble().clamp(1, 100),
              getTitlesWidget: (v, meta) => Text('${v.toInt()}', style: const TextStyle(fontSize: 10)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final d = today.subtract(Duration(days: 6 - v.toInt()));
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(DateFormat(context.isAr ? 'EEEEE' : 'E', context.lang).format(d), style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < 7; i++)
            BarChartGroupData(x: i, barsSpace: 3, barRods: [
              BarChartRodData(toY: stats.completedLast7Days[i].toDouble(), color: const Color(0xFF16A34A), width: 9, borderRadius: BorderRadius.circular(4)),
              BarChartRodData(toY: stats.createdLast7Days[i].toDouble(), color: const Color(0xFF5B5BD6).withValues(alpha: 0.35), width: 9, borderRadius: BorderRadius.circular(4)),
            ]),
        ],
      ),
      duration: const Duration(milliseconds: 500),
    );
  }
}
