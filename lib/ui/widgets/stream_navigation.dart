import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'brand_mark.dart';
import 'glass_panel.dart';

final class StreamNavigation extends StatelessWidget {
  const StreamNavigation({
    super.key,
    required this.controller,
    required this.drawerOpen,
    required this.onToggleDrawer,
    required this.onExplore,
    required this.onAdd,
    required this.onSettings,
    required this.onHelp,
  });

  final AppController controller;
  final bool drawerOpen;
  final VoidCallback onToggleDrawer;
  final VoidCallback onExplore;
  final VoidCallback onAdd;
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    return Row(
      children: <Widget>[
        Container(
          width: 70,
          decoration: BoxDecoration(
            color: tokens.panel,
            border: Border(right: BorderSide(color: tokens.border)),
          ),
          child: SafeArea(
            child: Column(
              children: <Widget>[
                const SizedBox(height: 14),
                Tooltip(
                  message: drawerOpen
                      ? 'Hide saved streams'
                      : 'Show saved streams',
                  child: IconButton.filledTonal(
                    onPressed: onToggleDrawer,
                    icon: const BrandMark(size: 28),
                  ),
                ),
                const SizedBox(height: 12),
                _RailButton(
                  icon: Icons.search_rounded,
                  label: 'Explore streams',
                  onPressed: onExplore,
                  primary: true,
                ),
                const SizedBox(height: 8),
                _RailButton(
                  icon: drawerOpen
                      ? Icons.keyboard_double_arrow_left_rounded
                      : Icons.keyboard_double_arrow_right_rounded,
                  label: drawerOpen
                      ? 'Collapse stream drawer'
                      : 'Open stream drawer',
                  onPressed: onToggleDrawer,
                ),
                const Spacer(),
                _RailButton(
                  icon: Icons.add_rounded,
                  label: 'Add stream',
                  onPressed: onAdd,
                  primary: true,
                ),
                const SizedBox(height: 8),
                _RailButton(
                  icon: Icons.tune_rounded,
                  label: 'Control center',
                  onPressed: onSettings,
                ),
                const SizedBox(height: 8),
                _RailButton(
                  icon: Icons.help_outline_rounded,
                  label: 'Help and installation',
                  onPressed: onHelp,
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        AnimatedContainer(
          duration: controller.preferences.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: drawerOpen ? 248 : 0,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              minWidth: 248,
              maxWidth: 248,
              child: SizedBox(
                width: 248,
                child: _StreamDrawer(controller: controller),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: primary
          ? IconButton.filled(onPressed: onPressed, icon: Icon(icon))
          : IconButton.filledTonal(onPressed: onPressed, icon: Icon(icon)),
    );
  }
}

final class _StreamDrawer extends StatelessWidget {
  const _StreamDrawer({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    final streams = controller.streams;
    return Container(
      color: tokens.canvas,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Saved streams',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${streams.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const NeonDivider(),
          const SizedBox(height: 12),
          Expanded(
            child: streams.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No saved channels.\nUse + to add one, or Search to explore text-only stream listings.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: ListView.separated(
                      primary: true,
                      itemCount: streams.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final stream = streams[index];
                        return _StreamTile(
                          stream: stream,
                          selected: controller.selected?.id == stream.id,
                          showTitle: controller.preferences.showStreamTitles,
                          onTap: () => controller.selectAndPlayStream(stream),
                          onPlay: () async {
                            await controller.selectStream(stream);
                            await controller.startPlayback();
                          },
                          onDelete: () => controller.deleteStream(stream),
                        );
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          Text(
            'TWITCH FREEDOM',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 3,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

final class _StreamTile extends StatelessWidget {
  const _StreamTile({
    required this.stream,
    required this.selected,
    required this.showTitle,
    required this.onTap,
    required this.onPlay,
    required this.onDelete,
  });
  final StreamRecord stream;
  final bool selected;
  final bool showTitle;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = freedomTokens(context);
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : tokens.panelElevated,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: stream.online == true
                          ? tokens.good
                          : stream.online == false
                          ? tokens.danger
                          : scheme.outline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      stream.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Stream actions',
                    onSelected: (String value) {
                      if (value == 'play') onPlay();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const <PopupMenuEntry<String>>[
                      PopupMenuItem(value: 'play', child: Text('Play')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                    icon: const Icon(Icons.more_horiz_rounded, size: 19),
                  ),
                ],
              ),
              if (showTitle && stream.title.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  stream.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 7),
              Text(
                '${stream.quality}  •  ${stream.playCount} plays',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
