import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../core/app_config.dart';
import '../core/result.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'widgets/brand_mark.dart';
import 'widgets/glass_panel.dart';

final class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

final class _UnlockScreenState extends State<UnlockScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _remember = false;
  bool _obscure = true;
  _FirstBootGemmaChoice _gemmaChoice = _FirstBootGemmaChoice.later;
  String _gemmaDirectory = '';

  bool get _creating => widget.controller.vaultStatus?.exists != true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChange);
  }

  void _handleControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChange);
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = freedomTokens(context);
    if (controller.booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: Listener(
        onPointerDown: (_) => controller.userActivity(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const _AuroraBackground(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: Material(
                        type: MaterialType.transparency,
                        child: GlassPanel(
                          radius: 34,
                          padding: const EdgeInsets.fromLTRB(34, 34, 34, 30),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  const BrandMark(size: 48),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          'TWITCH FREEDOM',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 1.1,
                                              ),
                                        ),
                                        Text(
                                          'PRIVATE • LOCAL • TEXT-FIRST',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: tokens.good,
                                                letterSpacing: 1.3,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.shield_rounded,
                                    color: tokens.good,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 34),
                              Text(
                                _creating
                                    ? 'Create your encrypted workspace'
                                    : 'Unlock your encrypted workspace',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 9),
                              Text(
                                _creating
                                    ? 'Your password never leaves this device. It unlocks a random vault key; records are independently authenticated and encrypted.'
                                    : 'Playback, Twitch credentials, preferences, chat history, and local AI memory remain inaccessible until the vault authenticates.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      height: 1.45,
                                    ),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _password,
                                obscureText: _obscure,
                                autofocus: true,
                                textInputAction: _creating
                                    ? TextInputAction.next
                                    : TextInputAction.done,
                                onSubmitted: (_) {
                                  if (!_creating) _submit();
                                },
                                decoration: InputDecoration(
                                  labelText: _creating
                                      ? 'Create boot password'
                                      : 'Boot password',
                                  prefixIcon: const Icon(Icons.key_rounded),
                                  suffixIcon: IconButton(
                                    tooltip: _obscure
                                        ? 'Show password'
                                        : 'Hide password',
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_rounded
                                          : Icons.visibility_off_rounded,
                                    ),
                                  ),
                                ),
                              ),
                              if (_creating) ...<Widget>[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _confirm,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _submit(),
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm password',
                                    prefixIcon: Icon(
                                      Icons.verified_user_rounded,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SwitchListTile.adaptive(
                                  value: _remember,
                                  onChanged: (bool value) =>
                                      setState(() => _remember = value),
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Use this device’s secure credential store',
                                  ),
                                  subtitle: const Text(
                                    'Optional. Fails closed if OS secure storage is unavailable.',
                                  ),
                                  secondary: const Icon(
                                    Icons.fingerprint_rounded,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _FirstBootGemmaCard(
                                  choice: _gemmaChoice,
                                  directory: _gemmaDirectory,
                                  enabled: !controller.busy,
                                  onChoiceChanged:
                                      (_FirstBootGemmaChoice value) =>
                                          setState(() => _gemmaChoice = value),
                                  onChooseExisting: _chooseExistingModelFolder,
                                  onChooseDownloadDirectory:
                                      _chooseDownloadDirectory,
                                ),
                              ],
                              if (controller.error.isNotEmpty) ...<Widget>[
                                const SizedBox(height: 14),
                                Semantics(
                                  liveRegion: true,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: tokens.danger.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: tokens.danger.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(13),
                                      child: Row(
                                        children: <Widget>[
                                          Icon(
                                            Icons.error_outline_rounded,
                                            color: tokens.danger,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(controller.error),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 22),
                              FilledButton.icon(
                                onPressed: controller.busy ? null : _submit,
                                icon: controller.busy
                                    ? const SizedBox.square(
                                        dimension: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _creating
                                            ? Icons.lock_rounded
                                            : Icons.lock_open_rounded,
                                      ),
                                label: Text(
                                  controller.busy
                                      ? controller.status
                                      : _creating
                                      ? 'Create encrypted vault'
                                      : 'Unlock',
                                ),
                              ),
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  Icon(
                                    Icons.wifi_off_rounded,
                                    size: 15,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      'No model, chat, or Twitch service starts before unlock.',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final wasCreating = _creating;
    final password = _password.text;
    if (password.length < 12) {
      _show('Use at least 12 characters for the boot password.');
      return;
    }
    if (wasCreating && password != _confirm.text) {
      _show('The passwords do not match.');
      return;
    }
    if (wasCreating &&
        _gemmaChoice == _FirstBootGemmaChoice.existing &&
        _gemmaDirectory.isEmpty) {
      _show('Choose the folder containing your .litertlm Gemma model.');
      return;
    }
    final result = wasCreating
        ? await widget.controller.createVault(password, remember: _remember)
        : await widget.controller.unlock(password);
    AppResult<void>? provisioning;
    if (wasCreating &&
        result is AppSuccess<void> &&
        _gemmaChoice != _FirstBootGemmaChoice.later) {
      provisioning = await widget.controller.provisionFirstBootGemma(
        directory: _gemmaDirectory,
        download: _gemmaChoice == _FirstBootGemmaChoice.download,
      );
    }
    if (!mounted) return;
    if (result is AppError<void>) _show(result.error.message);
    if (provisioning is AppError<void>) _show(provisioning.error.message);
  }

  Future<void> _chooseExistingModelFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Use model folder',
      initialDirectory: _gemmaDirectory.isEmpty ? null : _gemmaDirectory,
    );
    if (!mounted || path == null) return;
    setState(() {
      _gemmaChoice = _FirstBootGemmaChoice.existing;
      _gemmaDirectory = path;
    });
  }

  Future<void> _chooseDownloadDirectory() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Download here',
      initialDirectory: _gemmaDirectory.isEmpty ? null : _gemmaDirectory,
    );
    if (!mounted || path == null) return;
    setState(() {
      _gemmaChoice = _FirstBootGemmaChoice.download;
      _gemmaDirectory = path;
    });
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _FirstBootGemmaChoice { later, existing, download }

final class _FirstBootGemmaCard extends StatelessWidget {
  const _FirstBootGemmaCard({
    required this.choice,
    required this.directory,
    required this.enabled,
    required this.onChoiceChanged,
    required this.onChooseExisting,
    required this.onChooseDownloadDirectory,
  });

  final _FirstBootGemmaChoice choice;
  final String directory;
  final bool enabled;
  final ValueChanged<_FirstBootGemmaChoice> onChoiceChanged;
  final VoidCallback onChooseExisting;
  final VoidCallback onChooseDownloadDirectory;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    final sizeGiB = AppConfig.gemmaModelExpectedBytes / (1024 * 1024 * 1024);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.panelElevated.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: choice == _FirstBootGemmaChoice.later
              ? tokens.border
              : Theme.of(context).colorScheme.secondary.withValues(alpha: .65),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.memory_rounded,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Set up private Gemma',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${AppConfig.gemmaModelName} • ${sizeGiB.toStringAsFixed(1)} GiB',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.verified_user_outlined, color: tokens.good),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Choose now; setup starts only after the vault unlocks. The folder path and integrity attestation are stored inside the encrypted vault.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                ChoiceChip(
                  selected: choice == _FirstBootGemmaChoice.later,
                  onSelected: enabled
                      ? (_) => onChoiceChanged(_FirstBootGemmaChoice.later)
                      : null,
                  avatar: const Icon(Icons.schedule_rounded, size: 17),
                  label: const Text('Set up later'),
                ),
                ChoiceChip(
                  selected: choice == _FirstBootGemmaChoice.existing,
                  onSelected: enabled ? (_) => onChooseExisting() : null,
                  avatar: const Icon(Icons.folder_open_rounded, size: 17),
                  label: const Text('Use existing'),
                ),
                ChoiceChip(
                  selected: choice == _FirstBootGemmaChoice.download,
                  onSelected: enabled
                      ? (_) => onChoiceChanged(_FirstBootGemmaChoice.download)
                      : null,
                  avatar: const Icon(Icons.download_rounded, size: 17),
                  label: const Text('Download verified'),
                ),
              ],
            ),
            if (choice != _FirstBootGemmaChoice.later) ...<Widget>[
              const SizedBox(height: 11),
              OutlinedButton.icon(
                onPressed: enabled
                    ? choice == _FirstBootGemmaChoice.existing
                          ? onChooseExisting
                          : onChooseDownloadDirectory
                    : null,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: Text(
                  directory.isEmpty
                      ? choice == _FirstBootGemmaChoice.existing
                            ? 'Choose model folder'
                            : 'Choose download folder (optional)'
                      : 'Change folder',
                ),
              ),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    directory.isEmpty
                        ? Icons.lock_outline_rounded
                        : Icons.folder_special_outlined,
                    size: 16,
                    color: tokens.good,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      directory.isEmpty
                          ? 'A private application folder will be created after unlock.'
                          : directory,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _AuroraBackground extends StatelessWidget {
  const _AuroraBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (AppConfig.constrainedLinuxRendering) {
      return ColoredBox(
        color: Color.alphaBlend(
          scheme.primary.withValues(alpha: .045),
          const Color(0xFF02030A),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            const Color(0xFF02030A),
            scheme.primary.withValues(alpha: 0.18),
            const Color(0xFF031019),
            scheme.secondary.withValues(alpha: 0.14),
            const Color(0xFF020205),
          ],
          stops: const <double>[0, .27, .52, .76, 1],
        ),
      ),
    );
  }
}
