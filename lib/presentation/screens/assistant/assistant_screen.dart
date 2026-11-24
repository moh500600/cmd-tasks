import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/platform/platform_support.dart';

import '../../../core/l10n/l10n.dart';
import '../../../domain/assistant/assistant_engine.dart';
import '../../../domain/entities/enums.dart';
import '../../../domain/entities/project.dart';
import '../../../domain/entities/task.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

class _Msg {
  final String text;
  final bool fromUser;
  final AssistantAction? action;
  bool applied = false;
  _Msg(this.text, this.fromUser, [this.action]);
}

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Msg>[];
  final _speech = SpeechToText();
  bool _listening = false;
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() => _messages.add(_Msg(context.tr('assistant_welcome'), false)));
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    if (PlatformSupport.speechToText) _speech.cancel();
    super.dispose();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 200, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() {
      _messages.add(_Msg(text, true));
      _thinking = true;
    });
    _toEnd();
    try {
      final tasks = await ref.read(allTasksProvider.future);
      final reply = await ref.read(assistantEngineProvider).respond(
            text,
            AssistantContext(tasks: tasks, now: DateTime.now(), languageCode: ref.read(settingsProvider).languageCode),
          );
      setState(() => _messages.add(_Msg(reply.text, false, reply.action)));
    } catch (e) {
      if (mounted) setState(() => _messages.add(_Msg(errorText(context, e), false)));
    } finally {
      if (mounted) setState(() => _thinking = false);
      _toEnd();
    }
  }

  Future<void> _toggleMic() async {
    // Voice input uses the phone's speech engine; the desktop build is text-only.
    if (!PlatformSupport.speechToText) {
      showSnack(context, context.tr('speech_desktop_unavailable'), error: true);
      return;
    }
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (s) {
        if ((s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (e) {
        if (mounted) {
          setState(() => _listening = false);
          showSnack(context, context.tr('speech_error'), error: true);
        }
      },
    );
    if (!ok) {
      if (mounted) showSnack(context, context.tr('speech_unavailable'), error: true);
      return;
    }
    final ar = ref.read(settingsProvider).languageCode == 'ar';
    final locales = await _speech.locales();
    String? localeId;
    for (final l in locales) {
      if (l.localeId.toLowerCase().startsWith(ar ? 'ar' : 'en')) {
        localeId = l.localeId;
        if (!ar || l.localeId.contains('SA') || l.localeId.contains('YE')) break;
      }
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (r) {
        setState(() => _input.text = r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          setState(() => _listening = false);
          _send();
        }
      },
      listenOptions: SpeechListenOptions(localeId: localeId, partialResults: true, listenFor: const Duration(seconds: 30), pauseFor: const Duration(seconds: 3)),
    );
  }

  Future<void> _apply(_Msg m) async {
    final a = m.action!;
    final actions = ref.read(actionsProvider);
    final uid = actions.uid;
    final now = DateTime.now();
    final ok = await guard(context, () async {
      switch (a) {
        case CreateTasksAction(:final tasks):
          for (final p in tasks) {
            await actions.saveTask(Task(
              userId: uid,
              title: p.title,
              dueDate: p.dueDate,
              priority: p.priority ?? TaskPriority.medium,
              tags: p.tags.map((n) => Tag(name: n)).toList(),
              reminderMinutes: p.reminderMinutes ?? (p.dueDate != null ? ref.read(settingsProvider).defaultReminderMinutes : null),
              createdAt: now,
              updatedAt: now,
            ));
          }
        case CreateProjectAction(:final projectName, :final subtasks):
          final project = await actions.saveProject(Project(userId: uid, name: projectName, iconCode: Icons.folder_rounded.codePoint, createdAt: now));
          for (final s in subtasks) {
            await actions.saveTask(Task(userId: uid, projectId: project.id, title: s, createdAt: now, updatedAt: now));
          }
        case ApplyPrioritiesAction(:final suggestions):
          for (final e in suggestions.entries) {
            await actions.setPriority(e.key, e.value);
          }
        case ApplyPlanAction(:final plan):
          for (final item in plan) {
            final fresh = await ref.read(taskRepositoryProvider).getById(uid, item.task.id!);
            if (fresh == null) continue;
            var t = fresh.copyWith(startDate: item.start);
            // Overdue or undated tasks get rescheduled into today's slot.
            if (t.dueDate == null || t.dueDate!.isBefore(item.start)) {
              t = t.copyWith(dueDate: item.end, reminderMinutes: t.reminderMinutes ?? 0);
            }
            await actions.saveTask(t);
          }
      }
    }, successKey: 'assistant_applied');
    if (ok) setState(() => m.applied = true);
  }

  String _actionLabel(AssistantAction a) => switch (a) {
        CreateTasksAction(:final tasks) => tasks.length == 1 ? context.tr('add_task') : context.trf('add_n_tasks', {'n': tasks.length}),
        CreateProjectAction() => context.tr('create_project_tasks'),
        ApplyPrioritiesAction() => context.tr('apply_priorities'),
        ApplyPlanAction() => context.tr('apply_plan'),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final suggestions = [
      context.tr('sugg_plan'),
      context.tr('sugg_summary'),
      context.tr('sugg_overdue'),
      context.tr('sugg_priorities'),
      context.tr('sugg_productivity'),
      context.tr('sugg_best_time'),
      context.tr('sugg_create'),
      context.tr('sugg_split'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.auto_awesome_rounded),
          const SizedBox(width: 8),
          Text(context.tr('assistant')),
        ]),
        actions: [
          IconButton(
            tooltip: context.tr('help'),
            icon: const Icon(Icons.help_outline_rounded),
            onPressed: () => _send(context.isAr ? 'مساعدة' : 'help'),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length + (_thinking ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _messages.length) {
                return const Align(alignment: AlignmentDirectional.centerStart, child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
              }
              final m = _messages[i];
              return Align(
                alignment: m.fromUser ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: m.fromUser ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadiusDirectional.only(
                      topStart: const Radius.circular(18),
                      topEnd: const Radius.circular(18),
                      bottomStart: Radius.circular(m.fromUser ? 18 : 4),
                      bottomEnd: Radius.circular(m.fromUser ? 4 : 18),
                    ).resolve(Directionality.of(context)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SelectableText(m.text, style: TextStyle(color: m.fromUser ? cs.onPrimary : cs.onSurface, fontSize: 15, height: 1.5)),
                    if (m.action != null) ...[
                      const SizedBox(height: 10),
                      m.applied
                          ? Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18),
                              const SizedBox(width: 4),
                              Text(context.tr('done'), style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w700)),
                            ])
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: () => _apply(m),
                              icon: const Icon(Icons.check_rounded, size: 18),
                              label: Text(_actionLabel(m.action!)),
                            ),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final s in suggestions)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ActionChip(
                    label: Text(s.split('\n').first),
                    onPressed: () {
                      if (s.contains('\n') || s.endsWith(':') || s.endsWith(' ')) {
                        _input.text = s;
                      } else {
                        _send(s);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(hintText: context.tr(_listening ? 'listening' : 'assistant_hint')),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: context.tr('speak'),
                onPressed: _toggleMic,
                icon: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: _listening ? Colors.red : null),
              ),
              const SizedBox(width: 4),
              IconButton.filled(onPressed: _thinking ? null : () => _send(), icon: const Icon(Icons.send_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
