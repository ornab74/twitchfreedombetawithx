import 'dart:async';

import 'package:flutter/material.dart';

import '../../ai/ai_models.dart';
import '../../core/models.dart';
import '../../core/result.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'glass_panel.dart';
import 'pulse_ring.dart';

final class AiCompanionPanel extends StatefulWidget {
  const AiCompanionPanel({
    super.key,
    required this.controller,
    this.popOut = false,
  });
  final AppController controller;
  final bool popOut;

  @override
  State<AiCompanionPanel> createState() => _AiCompanionPanelState();
}

final class _AiCompanionPanelState extends State<AiCompanionPanel> {
  final TextEditingController _question = TextEditingController();
  bool _working = false;

  @override
  void initState() {
    super.initState();
    widget.controller.aiRevision.addListener(_handleAiUpdate);
  }

  void _handleAiUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant AiCompanionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.aiRevision.removeListener(_handleAiUpdate);
    widget.controller.aiRevision.addListener(_handleAiUpdate);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final ai = controller.preferences.ai;
    final runtime = controller.gemma.current;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final shortPanel = !widget.popOut && constraints.maxHeight < 300;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: shortPanel
                    ? const EdgeInsets.fromLTRB(12, 4, 12, 3)
                    : const EdgeInsets.fromLTRB(16, 14, 16, 11),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Local AI Companion',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: widget.popOut
                          ? 'Close AI workspace'
                          : 'Pop out AI workspace',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.popOut
                          ? () => Navigator.of(context).pop()
                          : _openPopOut,
                      icon: Icon(
                        widget.popOut
                            ? Icons.close_fullscreen_rounded
                            : Icons.open_in_new_rounded,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 4),
                    PulseRing(
                      active: runtime.busy,
                      reduceMotion: controller.preferences.reduceMotion,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      runtime.loaded
                          ? 'Model ready'
                          : runtime.installed
                          ? 'Installed'
                          : 'Not installed',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const NeonDivider(),
              if (!shortPanel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  // A single horizontal rail prevents this compact desktop panel
                  // from gaining a second Wrap run during a window resize. That
                  // transient extra row was the source of the 17 px RenderFlex
                  // overflow seen immediately before the Linux surface crash.
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    primary: false,
                    child: Row(
                      children: <Widget>[
                        _ModeChip(
                          icon: Icons.palette_outlined,
                          label: 'Mood',
                          active: ai.moodColoring,
                        ),
                        const SizedBox(width: 7),
                        _ModeChip(
                          icon: Icons.shield_outlined,
                          label: 'Mirror',
                          active: ai.protectiveMode != ProtectiveMode.raw,
                        ),
                        const SizedBox(width: 7),
                        _ModeChip(
                          icon: Icons.sentiment_very_satisfied_rounded,
                          label: 'Jokes',
                          active: ai.jokeMode,
                        ),
                        const SizedBox(width: 7),
                        _ModeChip(
                          icon: Icons.science_outlined,
                          label: 'Tech',
                          active: ai.technicalCompanion,
                        ),
                        const SizedBox(width: 7),
                        _ModeChip(
                          icon: Icons.spa_outlined,
                          label: 'Calm',
                          active: ai.calmingComposer,
                        ),
                        const SizedBox(width: 7),
                        _ModeChip(
                          icon: Icons.hearing_rounded,
                          label: 'Speech',
                          active: ai.speechContext,
                        ),
                      ],
                    ),
                  ),
                ),
              if (!ai.enabled)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Local AI is disabled. Every AI feature is opt-in from Control Center. Raw Twitch chat remains available without the model.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                )
              else ...<Widget>[
                if (!shortPanel || !runtime.loaded)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        if (!runtime.installed)
                          FilledButton.tonalIcon(
                            onPressed: _working ? null : _install,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Install verified Gemma 4 E2B'),
                          )
                        else if (!runtime.loaded)
                          FilledButton.tonalIcon(
                            onPressed: _working ? null : _load,
                            icon: const Icon(Icons.memory_rounded),
                            label: const Text('Load model'),
                          )
                        else
                          FilledButton.tonalIcon(
                            onPressed: _working ? null : _runBatch,
                            icon: const Icon(Icons.bolt_rounded),
                            label: const Text('Analyze current batch'),
                          ),
                        const SizedBox(width: 8),
                        if (ai.speechContext && (!shortPanel || runtime.loaded))
                          OutlinedButton.icon(
                            onPressed: _working || !runtime.loaded
                                ? null
                                : _captureSpeech,
                            icon: const Icon(Icons.graphic_eq_rounded),
                            label: const Text('Capture 5s context'),
                          ),
                        const Spacer(),
                        if (runtime.busy)
                          IconButton.filledTonal(
                            tooltip: 'Cancel local generation',
                            onPressed: controller.gemma.cancel,
                            icon: const Icon(Icons.stop_circle_outlined),
                          ),
                      ],
                    ),
                  ),
                if (runtime.busy || runtime.progress > 0 && !runtime.installed)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 10, 13, 0),
                    child: LinearProgressIndicator(
                      value: runtime.progress > 0 && runtime.progress < 1
                          ? runtime.progress
                          : null,
                    ),
                  ),
                Expanded(
                  child: controller.companionCards.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              runtime.loaded
                                  ? 'Companion results appear after a private batch analysis. Nothing is posted to Twitch automatically.'
                                  : runtime.message.isEmpty
                                  ? 'Install and load the local model to begin.'
                                  : runtime.message,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: controller.companionCards.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, int index) => _CompanionCardView(
                            card: controller.companionCards[index],
                          ),
                        ),
                ),
                if (!shortPanel || runtime.loaded)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      shortPanel ? 6 : 12,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _question,
                            minLines: 1,
                            maxLines: 1,
                            textInputAction: TextInputAction.send,
                            decoration: const InputDecoration(
                              hintText:
                                  'Ask about a technical topic from the stream…',
                            ),
                            onSubmitted: (_) => _ask(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _working || !runtime.loaded ? null : _ask,
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _install() async {
    setState(() => _working = true);
    final result = await widget.controller.installAndLoadGemma();
    if (mounted) {
      setState(() => _working = false);
      _showFailure(result);
    }
  }

  Future<void> _openPopOut() => showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .48),
    builder: (BuildContext dialogContext) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        insetPadding: const EdgeInsets.all(24),
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width.clamp(520, 1040).toDouble(),
          height: size.height.clamp(540, 820).toDouble(),
          child: RepaintBoundary(
            child: AiCompanionPanel(
              controller: widget.controller,
              popOut: true,
            ),
          ),
        ),
      );
    },
  );

  Future<void> _load() async {
    setState(() => _working = true);
    final result = await widget.controller.loadGemma();
    if (mounted) {
      setState(() => _working = false);
      _showFailure(result);
    }
  }

  Future<void> _runBatch() async {
    setState(() => _working = true);
    final result = await widget.controller.runAiBatchNow();
    if (mounted) {
      setState(() => _working = false);
      _showFailure(result);
    }
  }

  Future<void> _captureSpeech() async {
    setState(() => _working = true);
    AppResult<dynamic> result;
    var attached = await widget.controller.speech.attachActiveMoonshine();
    if (attached is AppError<void>) {
      attached = await widget.controller.installMoonshine();
    }
    result = attached;
    if (attached is AppSuccess<void>)
      result = await widget.controller.captureSpeechContext();
    if (mounted) {
      setState(() => _working = false);
      _showFailure(result);
    }
  }

  Future<void> _ask() async {
    final text = _question.text.trim();
    if (text.isEmpty) return;
    setState(() => _working = true);
    final result = await widget.controller.agents.answerTechnicalQuestion(
      text,
      widget.controller.chat.reversed.take(80).toList().reversed.toList(),
    );
    if (mounted) {
      setState(() => _working = false);
      if (result is AppSuccess<String>) {
        widget.controller.agents.addSpeechContext(widget.controller.speechText);
        _question.clear();
      } else {
        _showFailure(result);
      }
    }
  }

  void _showFailure(AppResult<dynamic> result) {
    if (result is AppError<dynamic>)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error.message)));
  }

  @override
  void dispose() {
    widget.controller.aiRevision.removeListener(_handleAiUpdate);
    _question.dispose();
    super.dispose();
  }
}

final class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.icon,
    required this.label,
    required this.active,
  });
  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        icon,
        size: 16,
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      label: Text(label),
      backgroundColor: active
          ? Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      side: BorderSide(
        color: active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
            : freedomTokens(context).border,
      ),
    );
  }
}

final class _CompanionCardView extends StatelessWidget {
  const _CompanionCardView({required this.card});
  final CompanionCard card;

  @override
  Widget build(BuildContext context) {
    final icon = switch (card.role) {
      AgentRole.safety => Icons.shield_outlined,
      AgentRole.joke => Icons.sentiment_very_satisfied_rounded,
      AgentRole.technical => Icons.science_outlined,
      AgentRole.calming => Icons.spa_outlined,
      AgentRole.discovery => Icons.search_rounded,
      AgentRole.summary => Icons.summarize_outlined,
      AgentRole.mood => Icons.palette_outlined,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: freedomTokens(context).panelElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: freedomTokens(context).border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              size: 19,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    card.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  SelectableText(
                    card.body,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
