import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/entities/enums.dart';
import '../../domain/entities/task.dart';
import '../../domain/services/stats_calculator.dart';
import 'file_storage_service.dart';

/// Builds PDF / Excel reports and data exports, saved under app documents.
class ExportService {
  final FileStorageService storage;
  ExportService(this.storage);

  static String prio(TaskPriority p, bool ar) => switch (p) {
        TaskPriority.low => ar ? 'منخفضة' : 'Low',
        TaskPriority.medium => ar ? 'متوسطة' : 'Medium',
        TaskPriority.high => ar ? 'عالية' : 'High',
        TaskPriority.urgent => ar ? 'عاجلة' : 'Urgent',
      };

  static String status(TaskStatus s, bool ar) => switch (s) {
        TaskStatus.todo => ar ? 'لم تبدأ' : 'Not started',
        TaskStatus.inProgress => ar ? 'قيد التنفيذ' : 'In progress',
        TaskStatus.completed => ar ? 'مكتملة' : 'Completed',
        TaskStatus.postponed => ar ? 'مؤجلة' : 'Postponed',
      };

  String _stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<File> reportPdf({
    required PeriodReport report,
    required PeriodReport previous,
    required String userName,
    required bool ar,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final df = DateFormat('yyyy/MM/dd', ar ? 'ar' : 'en');
    final dtf = DateFormat('yyyy/MM/dd HH:mm', ar ? 'ar' : 'en');
    String t(String a, String e) => ar ? a : e;
    final change = StatsCalculator.change(report.completed, previous.completed);
    final best = report.bestWeekday;
    final avg = report.avgCompletionTime;
    String avgText() {
      if (avg == null) return '—';
      if (avg.inDays >= 1) return t('${avg.inDays} يوم ${avg.inHours % 24} ساعة', '${avg.inDays}d ${avg.inHours % 24}h');
      return t('${avg.inHours} ساعة ${avg.inMinutes % 60} دقيقة', '${avg.inHours}h ${avg.inMinutes % 60}m');
    }

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    final accent = PdfColor.fromInt(0xFF5B5BD6);
    pw.Widget kv(String k, String v) => pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700), textDirection: dir),
            pw.SizedBox(height: 4),
            pw.Text(v, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: accent), textDirection: dir),
          ]),
        );

    final maxDay = report.completedPerDay.fold<int>(1, (a, b) => b > a ? b : a);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: dir,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text(t('CMD Tasks — تقرير الإنتاجية', 'CMD Tasks — Productivity report'),
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: accent), textDirection: dir),
        pw.SizedBox(height: 4),
        pw.Text('$userName • ${df.format(report.from)} → ${df.format(report.to.subtract(const Duration(days: 1)))}',
            textDirection: dir, style: const pw.TextStyle(color: PdfColors.grey700)),
        pw.Divider(),
        pw.GridView(crossAxisCount: 3, childAspectRatio: 0.45, crossAxisSpacing: 8, mainAxisSpacing: 8, children: [
          kv(t('المهام المنجزة', 'Completed'), '${report.completed}'),
          kv(t('المهام المتأخرة', 'Overdue'), '${report.overdue}'),
          kv(t('مهام جديدة', 'Created'), '${report.created}'),
          kv(t('معدل الإنتاجية', 'Productivity rate'), '${(report.productivityRate * 100).round()}%'),
          kv(t('متوسط وقت الإنجاز', 'Avg completion time'), avgText()),
          kv(t('أفضل يوم', 'Best day'), best == null ? '—' : DateFormat('EEEE', ar ? 'ar' : 'en').format(DateTime(2024, 1, best))),
        ]),
        pw.SizedBox(height: 12),
        pw.Text(
            t('مقارنة بالفترة السابقة: ${previous.completed} ← ${report.completed}${change == null ? '' : ' (${change >= 0 ? '+' : ''}${change.round()}%)'}',
                'Compared with previous period: ${previous.completed} → ${report.completed}${change == null ? '' : ' (${change >= 0 ? '+' : ''}${change.round()}%)'}'),
            textDirection: dir),
        pw.SizedBox(height: 14),
        pw.Text(t('الإنجاز اليومي', 'Completed per day'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textDirection: dir),
        pw.SizedBox(height: 6),
        pw.Container(
          height: 90,
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (final v in report.completedPerDay)
                pw.Expanded(
                  child: pw.Container(
                    margin: const pw.EdgeInsets.symmetric(horizontal: 1),
                    height: 4 + 80 * v / maxDay,
                    color: v == 0 ? PdfColors.grey200 : accent,
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Text(t('المهام المنجزة', 'Completed tasks'),
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textDirection: dir),
        pw.SizedBox(height: 6),
        if (report.completedTasks.isEmpty)
          pw.Text(t('لا توجد مهام منجزة في هذه الفترة', 'No tasks completed in this period'), textDirection: dir)
        else
          pw.TableHelper.fromTextArray(
            headerDirection: dir,
            cellAlignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: accent),
            headers: [t('المهمة', 'Task'), t('المشروع', 'Project'), t('الأولوية', 'Priority'), t('أنجزت في', 'Completed at')],
            data: [
              for (final x in report.completedTasks)
                [x.title, x.projectName ?? '—', prio(x.priority, ar), dtf.format(x.completedAt!)],
            ],
          ),
      ],
    ));
    return storage.writeExport('tasks_pro_report_${_stamp()}.pdf', await doc.save());
  }

  Future<File> reportExcel({
    required PeriodReport report,
    required PeriodReport previous,
    required List<Task> allTasks,
    required bool ar,
  }) async {
    String t(String a, String e) => ar ? a : e;
    final book = xl.Excel.createExcel();
    final summaryName = t('الملخص', 'Summary');
    book.rename(book.getDefaultSheet()!, summaryName);
    final s = book[summaryName];
    s.isRTL = ar;
    final df = DateFormat('yyyy-MM-dd');
    xl.CellValue tx(String v) => xl.TextCellValue(v);
    xl.CellValue n(num v) => v is int ? xl.IntCellValue(v) : xl.DoubleCellValue(v.toDouble());
    s.appendRow([tx(t('الفترة', 'Period')), tx('${df.format(report.from)} → ${df.format(report.to.subtract(const Duration(days: 1)))}')]);
    s.appendRow([tx(t('المهام المنجزة', 'Completed')), n(report.completed)]);
    s.appendRow([tx(t('المنجزة في الفترة السابقة', 'Completed (previous period)')), n(previous.completed)]);
    s.appendRow([tx(t('المهام المتأخرة', 'Overdue')), n(report.overdue)]);
    s.appendRow([tx(t('مهام جديدة', 'Created')), n(report.created)]);
    s.appendRow([tx(t('معدل الإنتاجية %', 'Productivity rate %')), n((report.productivityRate * 100).round())]);
    s.appendRow([tx(t('متوسط وقت الإنجاز (ساعات)', 'Avg completion time (hours)')),
      n(report.avgCompletionTime == null ? 0 : (report.avgCompletionTime!.inMinutes / 60).toStringAsFixed(1).toDouble())]);
    s.appendRow([]);
    s.appendRow([tx(t('اليوم', 'Day')), tx(t('منجزة', 'Completed'))]);
    for (var i = 0; i < report.completedPerDay.length; i++) {
      s.appendRow([tx(df.format(report.from.add(Duration(days: i)))), n(report.completedPerDay[i])]);
    }
    _tasksSheet(book, t('المهام', 'Tasks'), allTasks, ar);
    final bytes = book.encode();
    if (bytes == null) throw StateError('excel encode failed');
    return storage.writeExport('tasks_pro_report_${_stamp()}.xlsx', bytes);
  }

  void _tasksSheet(xl.Excel book, String name, List<Task> tasks, bool ar) {
    String t(String a, String e) => ar ? a : e;
    final sh = book[name];
    sh.isRTL = ar;
    final dtf = DateFormat('yyyy-MM-dd HH:mm');
    sh.appendRow([
      t('العنوان', 'Title'), t('الوصف', 'Description'), t('المشروع', 'Project'), t('الأولوية', 'Priority'),
      t('الحالة', 'Status'), t('الإنجاز %', 'Progress %'), t('البداية', 'Start'), t('الموعد النهائي', 'Due'),
      t('أنجزت في', 'Completed at'), t('الوسوم', 'Tags'), t('المهام الفرعية', 'Subtasks'), t('مؤرشفة', 'Archived'),
    ].map((e) => xl.TextCellValue(e)).toList());
    for (final x in tasks) {
      sh.appendRow([
        xl.TextCellValue(x.title),
        xl.TextCellValue(x.description),
        xl.TextCellValue(x.projectName ?? ''),
        xl.TextCellValue(prio(x.priority, ar)),
        xl.TextCellValue(status(x.status, ar)),
        xl.IntCellValue(x.effectiveProgress),
        xl.TextCellValue(x.startDate == null ? '' : dtf.format(x.startDate!)),
        xl.TextCellValue(x.dueDate == null ? '' : dtf.format(x.dueDate!)),
        xl.TextCellValue(x.completedAt == null ? '' : dtf.format(x.completedAt!)),
        xl.TextCellValue(x.tags.map((g) => g.name).join(', ')),
        xl.TextCellValue(x.subtasks.map((s) => '${s.done ? '✓' : '○'} ${s.title}').join(' | ')),
        xl.TextCellValue(x.archived ? t('نعم', 'Yes') : ''),
      ]);
    }
  }

  Future<File> tasksExcel(List<Task> tasks, bool ar) async {
    final book = xl.Excel.createExcel();
    final name = ar ? 'المهام' : 'Tasks';
    book.rename(book.getDefaultSheet()!, name);
    _tasksSheet(book, name, tasks, ar);
    final bytes = book.encode();
    if (bytes == null) throw StateError('excel encode failed');
    return storage.writeExport('tasks_pro_tasks_${_stamp()}.xlsx', bytes);
  }

  Future<File> backupJson(Map<String, dynamic> data) => storage.writeExport(
      'tasks_pro_backup_${_stamp()}.json', utf8.encode(const JsonEncoder.withIndent(' ').convert(data)));
}

extension on String {
  double toDouble() => double.parse(this);
}
