import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../core/models.dart';
import '../core/pulse_scheduler.dart';
import '../core/result.dart';
import '../state/app_controller.dart';
import '../twitch/twitch_auth.dart';
import 'theme.dart';
import 'widgets/glass_panel.dart';

Future<void> showSettingsSheet(BuildContext context, AppController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SettingsSheet(controller: controller),
  );
}

final class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

final class _SettingsSheetState extends State<SettingsSheet> {
  late AppPreferences _draft;
  late ThemeProfile _originalTheme;
  final TextEditingController _clientId = TextEditingController();
  final TextEditingController _clientSecret = TextEditingController();
  final TextEditingController _categories = TextEditingController();
  final TextEditingController _languages = TextEditingController();
  final TextEditingController _excludedChannels = TextEditingController();
  DeviceAuthorization? _authorization;
  String _authStatus = 'Not checked';
  bool _pollCancelled = false;
  bool _saving = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.controller.preferences;
    _originalTheme = _draft.theme;
    _categories.text = _draft.discovery.categories.join(', ');
    _languages.text = _draft.discovery.languages.join(', ');
    _excludedChannels.text = _draft.discovery.excludedChannels.join(', ');
    _loadAuthState();
  }

  @override
  void dispose() {
    _pollCancelled = true;
    if (!_saved) widget.controller.previewTheme(_originalTheme);
    _clientId.dispose();
    _clientSecret.dispose();
    _categories.dispose();
    _languages.dispose();
    _excludedChannels.dispose();
    super.dispose();
  }

  Future<void> _loadAuthState() async {
    final credentials = await widget.controller.auth.credentials();
    final token = await widget.controller.auth.tokenState();
    if (!mounted) return;
    setState(() {
      if (credentials != null) _clientId.text = credentials.clientId;
      _authStatus = token == null
          ? 'Not authorized'
          : 'Authorized as ${token.login}';
    });
  }

  Future<void> _installMoonshine() async {
    await widget.controller.installMoonshine();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    return FractionallySizedBox(
      heightFactor: .96,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Material(
          color: tokens.canvas,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 15, 14, 13),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.tune_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Control Center',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Chip(
                      avatar: Icon(
                        Icons.shield_rounded,
                        size: 17,
                        color: tokens.good,
                      ),
                      label: const Text('Encrypted preferences'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const NeonDivider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 120),
                  children: <Widget>[
                    _Section(
                      icon: Icons.palette_rounded,
                      title: 'Appearance',
                      subtitle: 'Futurist glass themes without remote imagery.',
                      child: Column(
                        children: <Widget>[
                          DropdownButtonFormField<ThemeProfile>(
                            initialValue: _draft.theme,
                            decoration: const InputDecoration(
                              labelText: 'Theme',
                              prefixIcon: Icon(Icons.gradient_rounded),
                            ),
                            items: ThemeProfile.values
                                .map(
                                  (ThemeProfile value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_themeName(value)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _previewTheme,
                          ),
                          _Switch(
                            'Show stream titles',
                            'Titles are sanitized text from Twitch; thumbnails remain disabled.',
                            _draft.showStreamTitles,
                            (bool value) => _change(
                              _draft.copyWith(showStreamTitles: value),
                            ),
                          ),
                          _Switch(
                            'Reduce motion',
                            'Stops pulse and spring animations for accessibility and lower GPU use.',
                            _draft.reduceMotion,
                            (bool value) =>
                                _change(_draft.copyWith(reduceMotion: value)),
                          ),
                          _Switch(
                            'Compact density',
                            'Tighter controls for small desktop windows.',
                            _draft.compactDensity,
                            (bool value) =>
                                _change(_draft.copyWith(compactDensity: value)),
                          ),
                          _Switch(
                            'Open stream drawer at boot',
                            'The drawer fully retracts when disabled.',
                            _draft.drawerOpen,
                            (bool value) =>
                                _change(_draft.copyWith(drawerOpen: value)),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.live_tv_rounded,
                      title: 'Playback',
                      subtitle:
                          'Native video, Media Kit, and FFmpeg compatibility paths.',
                      child: Column(
                        children: <Widget>[
                          DropdownButtonFormField<String>(
                            initialValue: _draft.preferredQuality,
                            decoration: const InputDecoration(
                              labelText: 'Preferred quality',
                              prefixIcon: Icon(Icons.high_quality_rounded),
                            ),
                            items:
                                const <String>[
                                      '160p',
                                      '360p',
                                      '480p',
                                      '720p',
                                      '720p60',
                                      '1080p',
                                      '1080p60',
                                      'best',
                                    ]
                                    .map(
                                      (String value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(value),
                                      ),
                                    )
                                    .toList(growable: false),
                            onChanged: (String? value) => _change(
                              _draft.copyWith(
                                preferredQuality:
                                    value ?? _draft.preferredQuality,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<VideoAcceleration>(
                            initialValue: _draft.videoAcceleration,
                            decoration: const InputDecoration(
                              labelText: 'Video acceleration',
                              prefixIcon: Icon(Icons.speed_rounded),
                            ),
                            items: VideoAcceleration.values
                                .map(
                                  (VideoAcceleration value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(switch (value) {
                                      VideoAcceleration.automatic =>
                                        'Automatic (recommended)',
                                      VideoAcceleration.hardwareGpu =>
                                        'Hardware / GPU',
                                      VideoAcceleration.softwareCpu =>
                                        'Software / CPU',
                                    }),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (VideoAcceleration? value) => _change(
                              _draft.copyWith(
                                videoAcceleration:
                                    value ?? _draft.videoAcceleration,
                              ),
                            ),
                          ),
                          if (Platform.isLinux) ...<Widget>[
                            const SizedBox(height: 10),
                            const _LinuxAccelerationStatus(),
                          ],
                          _Switch(
                            'Low latency resolver profile',
                            'Uses a smaller HLS live edge with bounded retry and timeout budgets.',
                            _draft.lowLatency,
                            (bool value) =>
                                _change(_draft.copyWith(lowLatency: value)),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.travel_explore_rounded,
                      title: 'Text-only discovery preferences',
                      subtitle:
                          'Helix supplies candidates; deterministic scoring and optional local Gemma reranking never load thumbnails.',
                      child: Column(
                        children: <Widget>[
                          TextField(
                            controller: _categories,
                            decoration: const InputDecoration(
                              labelText: 'Preferred categories or topics',
                              hintText: 'science, programming, space, makers',
                              prefixIcon: Icon(Icons.category_outlined),
                            ),
                            onChanged: (String value) => _setDiscovery(
                              _draft.discovery.copyWith(
                                categories: _csv(value),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _languages,
                            decoration: const InputDecoration(
                              labelText: 'Languages',
                              hintText: 'en, es',
                              prefixIcon: Icon(Icons.translate_rounded),
                            ),
                            onChanged: (String value) => _setDiscovery(
                              _draft.discovery.copyWith(
                                languages: _csv(value, lower: true),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _excludedChannels,
                            decoration: const InputDecoration(
                              labelText: 'Excluded channels',
                              hintText: 'channel_one, channel_two',
                              prefixIcon: Icon(Icons.block_rounded),
                            ),
                            onChanged: (String value) => _setDiscovery(
                              _draft.discovery.copyWith(
                                excludedChannels: _csv(value, lower: true),
                              ),
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Technical/science preference: ${(_draft.discovery.technicalWeight * 100).round()}%',
                              ),
                              subtitle: Slider(
                                value: _draft.discovery.technicalWeight,
                                min: 0,
                                max: 1,
                                divisions: 10,
                                onChanged: (double value) => _setDiscovery(
                                  _draft.discovery.copyWith(
                                    technicalWeight: value,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          _Switch(
                            'Prefer low-resource streams',
                            'Avoids favoring large viewer counts and pairs well with audio-only playback.',
                            _draft.discovery.preferLowResource,
                            (bool value) => _setDiscovery(
                              _draft.discovery.copyWith(
                                preferLowResource: value,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.key_rounded,
                      title: 'Twitch OAuth',
                      subtitle:
                          'Credentials and tokens are encrypted record-by-record in the local vault.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          TextField(
                            controller: _clientId,
                            decoration: const InputDecoration(
                              labelText: 'Twitch Client ID',
                              prefixIcon: Icon(Icons.badge_rounded),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _clientSecret,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Twitch Client Secret',
                              prefixIcon: Icon(Icons.password_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _saveTwitchApp,
                                  icon: const Icon(Icons.save_rounded),
                                  label: const Text(
                                    'Save encrypted credentials',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _saving
                                      ? null
                                      : _beginAuthorization,
                                  icon: const Icon(Icons.login_rounded),
                                  label: const Text('Authorize device'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.panelElevated,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: tokens.border),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: <Widget>[
                                  Icon(
                                    _authStatus.startsWith('Authorized')
                                        ? Icons.verified_user_rounded
                                        : Icons.info_outline_rounded,
                                    color: _authStatus.startsWith('Authorized')
                                        ? tokens.good
                                        : tokens.warning,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_authStatus)),
                                  if (_authorization != null)
                                    TextButton.icon(
                                      onPressed: _openAuthorization,
                                      icon: const Icon(
                                        Icons.open_in_new_rounded,
                                      ),
                                      label: Text(_authorization!.userCode),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _clearAuthorization,
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text(
                              'Clear encrypted Twitch authorization',
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.closed_caption_rounded,
                      title: 'Closed captions',
                      subtitle:
                          'Independent local Moonshine speech recognition. This does not enable or load Gemma agents.',
                      child: Column(
                        children: <Widget>[
                          _Switch(
                            'Closed captions on/off',
                            widget.controller.speechState.installed
                                ? 'Shows locally transcribed speech over the video. Raw audio is removed after each window.'
                                : 'Install the Moonshine caption model below before enabling.',
                            _draft.ai.closedCaptions,
                            widget.controller.speechState.installed ||
                                    _draft.ai.closedCaptions
                                ? (bool value) => _setAi(
                                    _draft.ai.copyWith(closedCaptions: value),
                                  )
                                : null,
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: widget.controller.busy
                                  ? null
                                  : _installMoonshine,
                              icon: const Icon(Icons.hearing_rounded),
                              label: const Text(
                                'Install Moonshine caption model',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Caption model: ${widget.controller.speechState.message}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.auto_awesome_rounded,
                      title: 'Local Gemma agents',
                      subtitle:
                          'All generated content stays private, is never auto-posted, and remains visibly labeled as AI.',
                      child: Column(
                        children: <Widget>[
                          _Switch(
                            'Gemma AI on/off',
                            'Controls only LLM agents. Closed captions remain independent.',
                            _draft.ai.enabled,
                            (bool value) =>
                                _setAi(_draft.ai.copyWith(enabled: value)),
                          ),
                          _Switch(
                            'Mood coloring',
                            'Batch-labels mood; the theme controls colors, not model output.',
                            _draft.ai.moodColoring,
                            (bool value) =>
                                _setAi(_draft.ai.copyWith(moodColoring: value)),
                          ),
                          DropdownButtonFormField<ProtectiveMode>(
                            initialValue: _draft.ai.protectiveMode,
                            decoration: const InputDecoration(
                              labelText: 'Protective Mirror',
                              prefixIcon: Icon(Icons.health_and_safety_rounded),
                            ),
                            items: ProtectiveMode.values
                                .map(
                                  (ProtectiveMode value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_protectiveName(value)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (ProtectiveMode? value) => _setAi(
                              _draft.ai.copyWith(
                                protectiveMode:
                                    value ?? _draft.ai.protectiveMode,
                              ),
                            ),
                          ),
                          _Switch(
                            'Joke mode',
                            'Private playful commentary with no autonomous chat posting.',
                            _draft.ai.jokeMode,
                            (bool value) =>
                                _setAi(_draft.ai.copyWith(jokeMode: value)),
                          ),
                          _Switch(
                            'Technical companion',
                            'Explains science and technical concepts found in current context.',
                            _draft.ai.technicalCompanion,
                            (bool value) => _setAi(
                              _draft.ai.copyWith(technicalCompanion: value),
                            ),
                          ),
                          _Switch(
                            'Calming response composer',
                            'Offers de-escalation choices without pretending certainty about intent.',
                            _draft.ai.calmingComposer,
                            (bool value) => _setAi(
                              _draft.ai.copyWith(calmingComposer: value),
                            ),
                          ),
                          _Switch(
                            'Speech context',
                            'Uses low-cost Moonshine Tiny locally for occasional AI context; raw audio is removed.',
                            _draft.ai.speechContext,
                            (bool value) => _setAi(
                              _draft.ai.copyWith(speechContext: value),
                            ),
                          ),
                          _Switch(
                            'Store encrypted transcripts',
                            'Keeps caption text as encrypted, expiring SQLite records; raw audio is never retained.',
                            _draft.ai.retainTranscripts,
                            (bool value) => _setAi(
                              _draft.ai.copyWith(retainTranscripts: value),
                            ),
                          ),
                          _Switch(
                            'Encrypted channel memory',
                            'Stores approved derived context per channel; can be deleted independently.',
                            _draft.ai.memoryEnabled,
                            (bool value) => _setAi(
                              _draft.ai.copyWith(memoryEnabled: value),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<AiBackend>(
                            initialValue: _draft.ai.backend,
                            decoration: const InputDecoration(
                              labelText: 'Inference backend',
                              prefixIcon: Icon(Icons.memory_rounded),
                            ),
                            items: AiBackend.values
                                .map(
                                  (AiBackend value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(_backendName(value)),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (AiBackend? value) => _setAi(
                              _draft.ai.copyWith(
                                backend: value ?? _draft.ai.backend,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.folder_rounded),
                              title: const Text('Gemma model file'),
                              subtitle: Text(
                                _draft.ai.modelDirectory.isEmpty
                                    ? 'Default private application model'
                                    : _draft.ai.modelDirectory,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: OutlinedButton.icon(
                                onPressed: widget.controller.busy
                                    ? null
                                    : _chooseGemmaDirectory,
                                icon: const Icon(Icons.folder_open_rounded),
                                label: const Text('Choose'),
                              ),
                            ),
                          ),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.speed_rounded),
                            title: Text('AI loads on demand'),
                            subtitle: Text(
                              'The model is verified after unlock but only loaded when you choose an AI feature.',
                            ),
                          ),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton.tonalIcon(
                                onPressed: _draft.ai.enabled
                                    ? widget.controller.installAndLoadGemma
                                    : null,
                                icon: const Icon(
                                  Icons.download_for_offline_rounded,
                                ),
                                label: const Text(
                                  'Install verified Gemma 4 E2B',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _draft.ai.enabled
                                    ? widget.controller.runAiBatchNow
                                    : null,
                                icon: const Icon(Icons.bolt_rounded),
                                label: const Text('Run batch now'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Gemma: ${widget.controller.gemma.current.message.isEmpty ? (widget.controller.gemma.current.loaded ? 'ready' : 'not loaded') : widget.controller.gemma.current.message}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (widget.controller.speechState.busy)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value:
                                    widget.controller.speechState.progress >
                                            0 &&
                                        widget.controller.speechState.progress <
                                            1
                                    ? widget.controller.speechState.progress
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.psychology_alt_rounded,
                      title: 'AI timing and safety',
                      subtitle:
                          'Batching lowers resource use and reduces snap judgments from isolated messages.',
                      child: Column(
                        children: <Widget>[
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Batch interval: ${_draft.ai.batchMinutes} minutes',
                              ),
                              subtitle: Slider(
                                value: _draft.ai.batchMinutes.toDouble(),
                                min: 5,
                                max: 10,
                                divisions: 5,
                                label: '${_draft.ai.batchMinutes}',
                                onChanged: (double value) => _setAi(
                                  _draft.ai.copyWith(
                                    batchMinutes: value.round(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Protective sensitivity: ${(_draft.ai.safetySensitivity * 100).round()}%',
                              ),
                              subtitle: Slider(
                                value: _draft.ai.safetySensitivity,
                                min: .45,
                                max: .95,
                                divisions: 10,
                                label:
                                    '${(_draft.ai.safetySensitivity * 100).round()}%',
                                onChanged: (double value) => _setAi(
                                  _draft.ai.copyWith(safetySensitivity: value),
                                ),
                              ),
                            ),
                          ),
                          ValueListenableBuilder<PulseSnapshot?>(
                            valueListenable:
                                widget.controller.schedulerTelemetry,
                            builder: (BuildContext context, snapshot, _) {
                              if (snapshot == null)
                                return const SizedBox.shrink();
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.hub_rounded),
                                title: const Text(
                                  'PulseMesh adaptive scheduler',
                                ),
                                subtitle: Text(
                                  '${snapshot.running} running • ${snapshot.queued} queued • '
                                  '${snapshot.credits.round()} resource credits • '
                                  '${snapshot.signals.chatMessagesPerMinute} chat msg/min',
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    _Section(
                      icon: Icons.lock_clock_rounded,
                      title: 'Privacy and lock behavior',
                      subtitle:
                          'The decrypted vault is closed when the app locks.',
                      child: Column(
                        children: <Widget>[
                          DropdownButtonFormField<int>(
                            initialValue: _draft.autoLockMinutes,
                            decoration: const InputDecoration(
                              labelText: 'Auto-lock after inactivity',
                              prefixIcon: Icon(Icons.timer_rounded),
                            ),
                            items: const <int>[0, 5, 10, 20, 30, 60]
                                .map(
                                  (int value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(
                                      value == 0 ? 'Never' : '$value minutes',
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: (int? value) => _change(
                              _draft.copyWith(
                                autoLockMinutes:
                                    value ?? _draft.autoLockMinutes,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: <Widget>[
                              FilledButton.tonalIcon(
                                onPressed: _changePassword,
                                icon: const Icon(Icons.password_rounded),
                                label: const Text('Change boot password'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _rotateDataKey,
                                icon: const Icon(Icons.rotate_right_rounded),
                                label: const Text('Rotate data key'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _clearSelectedChannelMemory,
                                icon: const Icon(Icons.delete_sweep_rounded),
                                label: const Text('Delete channel AI memory'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _showDiagnostics,
                                icon: const Icon(Icons.monitor_heart_rounded),
                                label: const Text('Redacted diagnostics'),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () async {
                                  await widget.controller.lock();
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.lock_rounded),
                                label: const Text('Lock workspace now'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.panel,
                  border: Border(top: BorderSide(color: tokens.border)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.verified_rounded, color: tokens.good),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            'Changes are stored as authenticated encrypted records.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _saveAndClose,
                          icon: const Icon(Icons.done_rounded),
                          label: const Text('Save and close'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _change(AppPreferences value) => setState(() => _draft = value);
  void _previewTheme(ThemeProfile? value) {
    if (value == null) return;
    _change(_draft.copyWith(theme: value));
    widget.controller.previewTheme(value);
  }

  void _setAi(AiFeatureSettings value) => _change(_draft.copyWith(ai: value));
  void _setDiscovery(DiscoveryPreference value) =>
      _change(_draft.copyWith(discovery: value));

  List<String> _csv(String value, {bool lower = false}) => value
      .split(',')
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .map((String item) => lower ? item.toLowerCase() : item)
      .toSet()
      .take(50)
      .toList(growable: false);

  Future<void> _saveAndClose() async {
    await widget.controller.updatePreferences(_draft);
    _saved = true;
    if (mounted) Navigator.pop(context);
  }

  Future<void> _chooseGemmaDirectory() async {
    final path = await _chooseGemmaModelPath();
    if (path == null || !mounted) return;
    // Keep the actual file in preferences so the selection survives restart.
    _setAi(_draft.ai.copyWith(modelDirectory: path));
    await widget.controller.updatePreferences(_draft);
    final result = await widget.controller.configureGemmaModelDirectory(path);
    if (!mounted) return;
    switch (result) {
      case AppSuccess<File>():
        _snack('Gemma model directory saved and SHA-256 verified.');
      case AppError<File>(:final error):
        _snack(
          error.code == 'model_missing'
              ? 'Directory saved. Place ${AppConfig.gemmaModelName} there or use Install.'
              : error.message,
        );
    }
  }

  Future<String?> _chooseGemmaModelPath() async {
    final configured = _draft.ai.modelDirectory.trim();
    final initialDirectory = configured.toLowerCase().endsWith('.litertlm')
        ? Directory(configured).parent.path
        : configured;
    final result = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(
          label: 'LiteRT-LM model',
          extensions: <String>['litertlm'],
        ),
      ],
      initialDirectory: initialDirectory.isEmpty ? null : initialDirectory,
    );
    return result?.path;
  }

  Future<void> _saveTwitchApp() async {
    setState(() => _saving = true);
    try {
      await widget.controller.auth.saveCredentials(
        TwitchAppCredentials(
          clientId: _clientId.text.trim(),
          clientSecret: _clientSecret.text.trim(),
        ),
      );
      if (mounted)
        setState(
          () => _authStatus = 'Credentials encrypted. Generate a device code.',
        );
    } catch (error) {
      if (mounted)
        _snack(
          error is AppFailure
              ? error.message
              : 'Could not save Twitch credentials.',
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _beginAuthorization() async {
    await _saveTwitchApp();
    final result = await widget.controller.auth.beginDeviceAuthorization();
    if (!mounted) return;
    switch (result) {
      case AppSuccess<DeviceAuthorization>(:final value):
        setState(() {
          _authorization = value;
          _authStatus = 'Open Twitch and enter code ${value.userCode}.';
          _pollCancelled = false;
        });
        await _openAuthorization();
        unawaited(_poll(value));
      case AppError<DeviceAuthorization>(:final error):
        _snack(error.message);
    }
  }

  Future<void> _poll(DeviceAuthorization authorization) async {
    final result = await widget.controller.auth.pollDeviceAuthorization(
      authorization,
      cancelled: () => _pollCancelled,
      onStatus: (String value) {
        if (mounted) setState(() => _authStatus = value);
      },
    );
    if (!mounted) return;
    switch (result) {
      case AppSuccess<TwitchTokenState>(:final value):
        setState(() {
          _authStatus = 'Authorized as ${value.login}';
          _authorization = null;
        });
        unawaited(widget.controller.refreshLiveStatuses());
      case AppError<TwitchTokenState>(:final error):
        setState(() => _authStatus = error.message);
    }
  }

  Future<void> _openAuthorization() async {
    final authorization = _authorization;
    if (authorization == null) return;
    await launchUrl(
      authorization.verificationUri,
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _clearAuthorization() async {
    _pollCancelled = true;
    await widget.controller.auth.clearAuthorization();
    if (mounted)
      setState(() {
        _authorization = null;
        _authStatus = 'Not authorized';
      });
  }

  Future<void> _changePassword() async {
    var password = '';
    var confirm = '';
    var remember = false;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) =>
            AlertDialog(
              title: const Text('Change boot password'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      obscureText: true,
                      onChanged: (String value) => password = value,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      obscureText: true,
                      onChanged: (String value) => confirm = value,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: remember,
                      onChanged: (bool value) =>
                          setDialogState(() => remember = value),
                      title: const Text('Remember through OS secure storage'),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Rewrap vault key'),
                ),
              ],
            ),
      ),
    );
    if (accepted != true) return;
    if (password.length < 12 || password != confirm) {
      _snack('Use at least 12 matching characters.');
    } else {
      final result = await widget.controller.vault.changePassword(
        newPassword: password,
        rememberOnDevice: remember,
      );
      if (result is AppSuccess<void>) {
        _snack('Boot password changed by rewrapping the vault key.');
      } else if (result is AppError<void>) {
        _snack(result.error.message);
      }
    }
  }

  Future<void> _rotateDataKey() async {
    final result = await widget.controller.vault.rotateDataKey();
    if (!mounted) return;
    if (result is AppSuccess<int>) {
      _snack('Data-encryption key rotated to version ${result.value}.');
    } else if (result is AppError<int>) {
      _snack(result.error.message);
    }
  }

  Future<void> _clearSelectedChannelMemory() async {
    final channel = widget.controller.selected?.channel;
    if (channel == null) {
      _snack('Select a channel first.');
      return;
    }
    await widget.controller.memory.deleteChannel(channel);
    if (mounted) _snack('Deleted encrypted AI memory for #$channel.');
  }

  Future<void> _showDiagnostics() async {
    final entries = widget.controller.log.entries.reversed
        .take(300)
        .toList(growable: false);
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Row(
          children: <Widget>[
            Icon(Icons.monitor_heart_rounded),
            SizedBox(width: 10),
            Text('Redacted diagnostics'),
          ],
        ),
        content: SizedBox(
          width: 760,
          height: 480,
          child: entries.isEmpty
              ? const Center(child: Text('No diagnostic entries yet.'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (_, int index) {
                    final item = entries[index];
                    return SelectableText(
                      '[${item.time.toIso8601String()}] ${item.level} ${item.message}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: widget.controller.log.clear,
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}

final class _LinuxAccelerationStatus extends StatelessWidget {
  const _LinuxAccelerationStatus();

  @override
  Widget build(BuildContext context) {
    final environment = Platform.environment;
    final gpu = environment['TWITCH_FREEDOM_GPU_AVAILABLE'] == '1';
    final openGl = environment['TWITCH_FREEDOM_OPENGL_AVAILABLE'] == '1';
    final hardwareDecode = environment['TWITCH_FREEDOM_HWDEC_AVAILABLE'] == '1';
    final renderer =
        environment['TWITCH_FREEDOM_RENDERER'] ?? 'platform-default';
    final media = environment['TWITCH_FREEDOM_MEDIA_RENDERER'] ?? 'auto';
    final display =
        environment['TWITCH_FREEDOM_DISPLAY_BACKEND'] ??
        environment['GDK_BACKEND'] ??
        'platform-default';
    final accelerated = gpu && openGl && !renderer.contains('cpu');
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accelerated
              ? colors.primary.withValues(alpha: .45)
              : colors.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              accelerated ? Icons.bolt_rounded : Icons.memory_rounded,
              color: accelerated ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Linux detector: GPU ${gpu ? "ready" : "unavailable"} • '
                'OpenGL ${openGl ? "ready" : "unavailable"} • '
                'video decode ${hardwareDecode ? "ready" : "CPU fallback"}\n'
                'Active UI: $renderer • display: $display • media: $media',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GlassPanel(
      radius: 22,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );
}

final class _Switch extends StatelessWidget {
  const _Switch(this.title, this.subtitle, this.value, this.onChanged);
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}

String _themeName(ThemeProfile value) => switch (value) {
  ThemeProfile.obsidianGlass => 'Obsidian Glass',
  ThemeProfile.auroraViolet => 'Aurora Violet',
  ThemeProfile.solarGraphite => 'Solar Graphite',
  ThemeProfile.arcticSignal => 'Arctic Signal',
  ThemeProfile.oledVoid => 'OLED Void',
  ThemeProfile.highContrast => 'High Contrast',
  ThemeProfile.matrix => 'Matrix',
  ThemeProfile.barbie => 'Barbie',
  ThemeProfile.halo2 => 'Halo 2',
  ThemeProfile.synthwaveSunset => 'Synthwave Sunset',
  ThemeProfile.oceanAbyss => 'Ocean Abyss',
  ThemeProfile.forestTerminal => 'Forest Terminal',
  ThemeProfile.crimsonProtocol => 'Crimson Protocol',
  ThemeProfile.desertDusk => 'Desert Dusk',
  ThemeProfile.lunarIce => 'Lunar Ice',
  ThemeProfile.retroArcade => 'Retro Arcade',
  ThemeProfile.royalAmethyst => 'Royal Amethyst',
  ThemeProfile.copperSteampunk => 'Copper Steampunk',
  ThemeProfile.sakuraNight => 'Sakura Night',
};

String _protectiveName(ProtectiveMode value) => switch (value) {
  ProtectiveMode.raw => 'Raw chat',
  ProtectiveMode.dim => 'Dim potentially harmful messages',
  ProtectiveMode.blur => 'Blur until revealed',
  ProtectiveMode.mirror => 'Protective Mirror paraphrase',
  ProtectiveMode.hideHighConfidence => 'Hide high-confidence abuse',
};

String _backendName(AiBackend value) => switch (value) {
  AiBackend.gpuFirst => 'GPU first, CPU fallback',
  AiBackend.gpuOnly => 'GPU only',
  AiBackend.cpuOnly => 'CPU only',
  AiBackend.npu => 'NPU when supported',
};
