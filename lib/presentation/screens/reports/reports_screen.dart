import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/utils/date_x.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/task.dart';
import '../../../domain/services/stats_calculator.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

enum ReportPeriod { week, month, custom }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportPeriod _period = ReportPeriod.week;
  DateTimeRange? _custom;
  bool _busy = false;

  (DateTime, DateTime) _range() {
    final now = DateTime.now();
    switch (_period) {
      case ReportPeriod.week:
        final s = startOfWeek(now);
        return (s, s.add(const Duration(days: 7)));
      case ReportPeriod.month:
        return (DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 1));
      case ReportPeriod.custom:
        final r = _custom ?? DateTimeRange(start: now.subtract(const Duration(days: 29)), end: now);
        return (dateOnly(r.start), dateOnly(r.end).add(const Duration(days: 1)));
    }
  }

  Future<void> _export(List<Task> all, PeriodReport r, PeriodReport prev, {required bool pdf}) async {
    setState(() => _busy = true);
    final ar = context.isAr;
    await guard(context, () async {
      final svc = ref.read(exportServiceProvider);
      final user = ref.read(sessionProvider)!;
      final file = pdf
          ? await svc.reportPdf(report: r, previous: prev, userName: user.name, ar: ar)
          : await svc.reportExcel(report: r, previous: prev, allTasks: all, ar: ar);
      if (!mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: Text(ctx.tr('export_saved')), subtitle: Text(file.path, maxLines: 2)),
            ListTile(leading: const Icon(Icons.share_rounded), title: Text(ctx.tr('share')), onTap: () => Navigator.pop(ctx, 'share')),
            if (pdf) ListTile(leading: const Icon(Icons.print_rounded), title: Text(ctx.tr('print_preview')), onTap: () => Navigator.pop(ctx, 'print')),
          ]),
        ),
      );
      if (action == 'share') {
        if (!mounted) return;
        await shareOrSaveFile(context, file, subject: ar ? 'تقرير CMD Tasks' : 'CMD Tasks report');
      } else if (action == 'print') {
        final bytes = await file.readAsBytes();
        try {
          await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'tasks_pro_report');
        } catch (_) {
          // No print service on this machine: open the PDF in the default viewer.
          await OpenFilex.open(file.path);
        }
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(allTasksProvider);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('reports'))),
      body: AsyncView<List<Task>>(
        value: all,
        builder: (tasks) {
          final now = DateTime.now();
          final (from, to) = _range();
          final len = to.difference(from);
          final r = StatsCalculator.period(tasks, from, to, now);
          final prev = StatsCalculator.period(tasks, from.subtract(len), from, now);
          final change = StatsCalculator.change(r.completed, prev.completed);
          final avg = r.avgCompletionTime;
          final cs = Theme.of(context).colorScheme;
          final byPriority = {for (final p in TaskPriority.values) p: r.completedTasks.where((t) => t.priority == p).length};

          Widget kpi(String label, String value, IconData icon, Color color, {String? sub}) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(icon, color: color),
                    const SizedBox(height: 8),
                    Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
              );

          String avgText() {
            if (avg == null) return '—';
            if (avg.inDays >= 1) return context.trf('dur_dh', {'d': avg.inDays, 'h': avg.inHours % 24});
            return context.trf('dur_hm', {'h': avg.inHours, 'm': avg.inMinutes % 60});
          }

          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 40), children: [
            SegmentedButton<ReportPeriod>(
              showSelectedIcon: false,
              segments: [for (final p in ReportPeriod.values) ButtonSegment(value: p, label: Text(context.tr('period_${p.name}')))],
              selected: {_period},
              onSelectionChanged: (s) async {
                if (s.first == ReportPeriod.custom) {
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 5),
                    lastDate: DateTime(now.year + 1),
                    initialDateRange: _custom,
                  );
                  if (picked == null) return;
                  _custom = picked;
                }
                setState(() => _period = s.first);
              },
            ),
            const SizedBox(height: 8),
            Text('${fmtDate(context, from)} → ${fmtDate(context, to.subtract(const Duration(days: 1)))}',
                textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 3 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: [
                kpi(context.tr('completed_tasks'), '${r.completed}', Icons.check_circle_rounded, Colors.green,
                    sub: change == null ? null : '${change >= 0 ? '▲' : '▼'} ${change.abs().round()}% ${context.tr('vs_previous')}'),
                kpi(context.tr('stat_overdue'), '${r.overdue}', Icons.warning_amber_rounded, cs.error),
                kpi(context.tr('avg_completion'), avgText(), Icons.timer_rounded, Colors.indigo),
                kpi(context.tr('productivity_rate'), '${(r.productivityRate * 100).round()}%', Icons.trending_up_rounded, Colors.teal),
                kpi(context.tr('best_day'), r.bestWeekday == null ? '—' : DateFormat('EEEE', context.lang).format(DateTime(2024, 1, r.bestWeekday!)),
                    Icons.emoji_events_rounded, Colors.amber.shade700),
                kpi(context.tr('created'), '${r.created}', Icons.add_task_rounded, cs.primary),
              ],
            ),
            SectionHeader(context.tr('comparison')),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _compareRow(context, context.tr('completed_tasks'), r.completed, prev.completed),
                  _compareRow(context, context.tr('created'), r.created, prev.created),
                  _compareRow(context, context.tr('productivity_rate'), (r.productivityRate * 100).round(), (prev.productivityRate * 100).round(), suffix: '%'),
                ]),
              ),
            ),
            SectionHeader(context.tr('daily_completion')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                child: SizedBox(
                  height: 200,
                  child: LineChart(LineChartData(
                    minY: 0,
                    gridData: const FlGridData(drawVerticalLine: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 26, interval: 1,
                          getTitlesWidget: (v, m) => v % 1 == 0 ? Text('${v.toInt()}', style: const TextStyle(fontSize: 10)) : const SizedBox())),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        interval: (r.completedPerDay.length / 6).ceilToDouble().clamp(1, 100),
                        getTitlesWidget: (v, m) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(DateFormat('d/M').format(from.add(Duration(days: v.toInt()))), style: const TextStyle(fontSize: 10)),
                        ),
                      )),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: [for (var i = 0; i < r.completedPerDay.length; i++) FlSpot(i.toDouble(), r.completedPerDay[i].toDouble())],
                        isCurved: true,
                        preventCurveOverShooting: true,
                        color: cs.primary,
                        barWidth: 3,
                        dotData: FlDotData(show: r.completedPerDay.length <= 31),
                        belowBarData: BarAreaData(show: true, color: cs.primary.withValues(alpha: 0.12)),
                      ),
                    ],
                  )),
                ),
              ),
            ),
            SectionHeader(context.tr('by_weekday')),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: SizedBox(
                  height: 170,
                  child: BarChart(BarChartData(
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, m) => Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(DateFormat(context.isAr ? 'EEEEE' : 'E', context.lang).format(DateTime(2024, 1, v.toInt())), style: const TextStyle(fontSize: 11)),
                        ),
                      )),
                    ),
                    barGroups: [
                      for (final wd in [6, 7, 1, 2, 3, 4, 5])
                        BarChartGroupData(x: wd, barRods: [
                          BarChartRodData(
                            toY: r.completedByWeekday[wd]!.toDouble(),
                            width: 18,
                            color: wd == r.bestWeekday ? Colors.amber.shade700 : cs.primary.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ]),
                    ],
                  )),
                ),
              ),
            ),
            if (r.completed > 0) ...[
              SectionHeader(context.tr('by_priority')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: PieChart(PieChartData(centerSpaceRadius: 28, sectionsSpace: 2, sections: [
                        for (final e in byPriority.entries)
                          if (e.value > 0)
                            PieChartSectionData(value: e.value.toDouble(), color: priorityColor(e.key), radius: 30, title: '${e.value}',
                                titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ])),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(children: [
                        for (final e in byPriority.entries)
                          Row(children: [
                            Icon(Icons.flag_rounded, color: priorityColor(e.key), size: 16),
                            const SizedBox(width: 6),
                            Expanded(child: Text(priorityLabel(context, e.key))),
                            Text('${e.value}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                      ]),
                    ),
                  ]),
                ),
              ),
              SectionHeader(context.tr(_period == ReportPeriod.month ? 'month_achievements' : 'week_achievements')),
              Card(
                child: Column(children: [
                  for (final t in r.completedTasks.reversed.take(15))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.check_circle_rounded, color: Colors.green),
                      title: Text(t.title),
                      subtitle: Text(fmtDateTime(context, t.completedAt!)),
                    ),
                ]),
              ),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : () => _export(tasks, r, prev, pdf: true),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _export(tasks, r, prev, pdf: false),
                  icon: const Icon(Icons.table_chart_rounded),
                  label: const Text('Excel'),
                ),
              ),
            ]),
            if (_busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          ]);
        },
      ),
    );
  }

  Widget _compareRow(BuildContext context, String label, int now, int before, {String suffix = ''}) {
    final ch = StatsCalculator.change(now, before);
    final up = now >= before;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text('$before$suffix', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Icon(context.isAr ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded, size: 16),
        Text('$now$suffix', style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(ch == null ? '—' : '${up ? '+' : ''}${ch.round()}%',
              textAlign: TextAlign.end, style: TextStyle(color: up ? Colors.green : Colors.red, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}
