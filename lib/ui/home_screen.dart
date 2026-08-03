import 'package:flutter/material.dart';

import '../core/app_config.dart';
import '../state/app_controller.dart';
import 'add_stream_dialog.dart';
import 'explore_sheet.dart';
import 'help_sheet.dart';
import 'settings_sheet.dart';
import 'theme.dart';
import 'x_mode_screen.dart';
import 'widgets/ai_companion_panel.dart';
import 'widgets/chat_panel.dart';
import 'widgets/glass_panel.dart';
import 'widgets/player_panel.dart';
import 'widgets/stream_navigation.dart';

final class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

final class _HomeScreenState extends State<HomeScreen> {
  late bool _drawerOpen;
  late ({
    bool compactDensity,
    bool reduceMotion,
    bool drawerOpen,
    bool aiEnabled,
  })
  _layout;
  int _mobileTab = 0;
  bool _xMode = false;

  @override
  void initState() {
    super.initState();
    _drawerOpen = widget.controller.preferences.drawerOpen;
    _layout = _readLayout();
    widget.controller.preferencesRevision.addListener(_handlePreferences);
  }

  ({bool compactDensity, bool reduceMotion, bool drawerOpen, bool aiEnabled})
  _readLayout() => (
    compactDensity: widget.controller.preferences.compactDensity,
    reduceMotion: widget.controller.preferences.reduceMotion,
    drawerOpen: widget.controller.preferences.drawerOpen,
    aiEnabled: widget.controller.preferences.ai.enabled,
  );

  void _handlePreferences() {
    final next = _readLayout();
    if (next == _layout || !mounted) return;
    setState(() {
      _layout = next;
      _drawerOpen = next.drawerOpen;
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.preferencesRevision.removeListener(_handlePreferences);
    widget.controller.preferencesRevision.addListener(_handlePreferences);
    _layout = _readLayout();
    _drawerOpen = _layout.drawerOpen;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Scaffold(
      body: Listener(
        onPointerDown: (_) => controller.userActivity(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const RepaintBoundary(child: _FuturistBackground()),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                // Window managers report a sequence of very small transient
                // surfaces while minimizing, maximizing, or crossing display
                // boundaries. Do not mount the fixed compact shell until a
                // useful body size is available.
                if (constraints.maxWidth < 340 || constraints.maxHeight < 500) {
                  return const _TinyWindowSurface();
                }
                // Avoid forcing the three-column mockup into dimensions where
                // its fixed headers and editors cannot fit. This also removes
                // resize-time RenderFlex churn from short or narrow windows.
                final compact =
                    constraints.maxWidth < 1100 || constraints.maxHeight < 820;
                if (compact) return _buildCompact(context);
                return _buildDesktop(context, constraints);
              },
            ),
            ValueListenableBuilder<int>(
              valueListenable: controller.shellRevision,
              builder: (_, __, ___) => Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (controller.busy) const _BusyOverlay(),
                  if (controller.error.isNotEmpty)
                    _ErrorBanner(controller: controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktop(BuildContext context, BoxConstraints constraints) {
    final controller = widget.controller;
    return Row(
      children: <Widget>[
        ValueListenableBuilder<int>(
          valueListenable: controller.navigationRevision,
          builder: (_, __, ___) => StreamNavigation(
            controller: controller,
            drawerOpen: _drawerOpen,
            onToggleDrawer: _toggleDrawer,
            onExplore: () => showExploreSheet(context, controller),
            onAdd: () => showAddStreamDialog(context, controller),
            onSettings: () => showSettingsSheet(context, controller),
            onHelp: () => showHelpSheet(context, controller),
          ),
        ),
        Expanded(
          child: SafeArea(
            left: false,
            child: Padding(
              padding: EdgeInsets.all(
                controller.preferences.compactDensity ? 10 : 16,
              ),
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<bool>(
                      segments: const <ButtonSegment<bool>>[
                        ButtonSegment<bool>(
                          value: false,
                          icon: Icon(Icons.live_tv_rounded),
                          label: Text('Twitch'),
                        ),
                        ButtonSegment<bool>(
                          value: true,
                          icon: Icon(Icons.alternate_email_rounded),
                          label: Text('X mode'),
                        ),
                      ],
                      selected: <bool>{_xMode},
                      onSelectionChanged: (value) =>
                          setState(() => _xMode = value.first),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_xMode)
                    Expanded(child: XModeScreen(controller: controller))
                  else ...<Widget>[
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Expanded(
                            flex: constraints.maxWidth > 1400 ? 7 : 6,
                            child: Column(
                              children: <Widget>[
                                Expanded(
                                  flex: controller.preferences.ai.enabled
                                      ? 7
                                      : 1,
                                  child: RepaintBoundary(
                                    child: PlayerPanel(controller: controller),
                                  ),
                                ),
                                if (controller.preferences.ai.enabled) ...[
                                  const SizedBox(height: 14),
                                  Expanded(
                                    flex: 3,
                                    child: RepaintBoundary(
                                      child: AiCompanionPanel(
                                        controller: controller,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: constraints.maxWidth > 1400 ? 3 : 4,
                            child: RepaintBoundary(
                              child: ChatPanel(controller: controller),
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
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final controller = widget.controller;
    final aiEnabled = controller.preferences.ai.enabled;
    final pages = aiEnabled ? const <int>[0, 1, 2, 3] : const <int>[0, 1, 3];
    final selectedPage = pages.contains(_mobileTab) ? _mobileTab : 0;
    // IndexedStack lays out every hidden child on each constraint change.
    // Mount only the selected heavyweight surface so video frames do not also
    // trigger hidden chat and AI layout work on compact windows.
    final page = switch (selectedPage) {
      0 => PlayerPanel(controller: controller),
      1 => ChatPanel(controller: controller),
      2 => AiCompanionPanel(controller: controller),
      _ => XModeScreen(controller: controller),
    };
    return SafeArea(
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
              children: <Widget>[
                IconButton.filledTonal(
                  onPressed: () => _showMobileStreams(context),
                  icon: const Icon(Icons.view_stream_rounded),
                  tooltip: 'Saved streams',
                ),
                const SizedBox(width: 7),
                IconButton.filled(
                  onPressed: () => showExploreSheet(context, controller),
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Explore',
                ),
                const Spacer(),
                IconButton.filledTonal(
                  onPressed: () => showAddStreamDialog(context, controller),
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add stream',
                ),
                const SizedBox(width: 7),
                IconButton.filledTonal(
                  onPressed: () => showHelpSheet(context, controller),
                  icon: const Icon(Icons.help_outline_rounded),
                  tooltip: 'Help',
                ),
                const SizedBox(width: 7),
                IconButton.filledTonal(
                  onPressed: () => showSettingsSheet(context, controller),
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Control Center',
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: RepaintBoundary(child: page),
            ),
          ),
          NavigationBar(
            selectedIndex: pages.indexOf(selectedPage),
            onDestinationSelected: (int value) =>
                setState(() => _mobileTab = pages[value]),
            destinations: <NavigationDestination>[
              const NavigationDestination(
                icon: Icon(Icons.live_tv_rounded),
                label: 'Player',
              ),
              const NavigationDestination(
                icon: Icon(Icons.forum_rounded),
                label: 'Chat',
              ),
              if (aiEnabled)
                const NavigationDestination(
                  icon: Icon(Icons.auto_awesome_rounded),
                  label: 'AI',
                ),
              const NavigationDestination(
                icon: Icon(Icons.alternate_email_rounded),
                label: 'X',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showMobileStreams(BuildContext context) async {
    final controller = widget.controller;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        final tokens = freedomTokens(context);
        return FractionallySizedBox(
          heightFactor: .82,
          child: Material(
            color: tokens.canvas,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Saved streams',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const NeonDivider(),
                Expanded(
                  child: controller.streams.isEmpty
                      ? const Center(child: Text('No saved streams yet.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: controller.streams.length,
                          itemBuilder: (_, int index) {
                            final stream = controller.streams[index];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(
                                    stream.displayName.isEmpty
                                        ? '?'
                                        : stream.displayName[0].toUpperCase(),
                                  ),
                                ),
                                title: Text(stream.displayName),
                                subtitle:
                                    controller.preferences.showStreamTitles &&
                                        stream.title.isNotEmpty
                                    ? Text(
                                        stream.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : Text(
                                        '${stream.quality} • ${stream.playCount} plays',
                                      ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  onPressed: () async {
                                    await controller.selectStream(stream);
                                    if (context.mounted) Navigator.pop(context);
                                    await controller.startPlayback();
                                  },
                                ),
                                onTap: () async {
                                  await controller.selectAndPlayStream(stream);
                                  if (context.mounted) Navigator.pop(context);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleDrawer() {
    setState(() => _drawerOpen = !_drawerOpen);
    widget.controller.updatePreferences(
      widget.controller.preferences.copyWith(drawerOpen: _drawerOpen),
    );
  }

  @override
  void dispose() {
    widget.controller.preferencesRevision.removeListener(_handlePreferences);
    super.dispose();
  }
}

final class _TinyWindowSurface extends StatelessWidget {
  const _TinyWindowSurface();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Colors.black,
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Resize Twitch Freedom to continue',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ),
    ),
  );
}

final class _FuturistBackground extends StatelessWidget {
  const _FuturistBackground();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canvas = Theme.of(context).scaffoldBackgroundColor;
    if (AppConfig.constrainedLinuxRendering) {
      return ColoredBox(
        color: Color.alphaBlend(scheme.primary.withValues(alpha: .035), canvas),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(-.7, -.8),
          radius: 1.7,
          colors: <Color>[
            scheme.primary.withValues(alpha: .13),
            canvas,
            scheme.secondary.withValues(alpha: .055),
          ],
          stops: const <double>[0, .56, 1],
        ),
      ),
    );
  }
}

final class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();
  @override
  Widget build(BuildContext context) => Positioned(
    top: 8,
    left: 0,
    right: 0,
    child: IgnorePointer(
      child: Center(
        child: Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SizedBox(width: 160, child: LinearProgressIndicator()),
          ),
        ),
      ),
    ),
  );
}

final class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    return Positioned(
      left: 90,
      right: 24,
      bottom: 22,
      child: Material(
        color: tokens.danger.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: const Icon(Icons.error_outline_rounded, color: Colors.white),
          title: Text(
            controller.error,
            style: const TextStyle(color: Colors.white),
          ),
          trailing: IconButton(
            onPressed: controller.clearError,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
