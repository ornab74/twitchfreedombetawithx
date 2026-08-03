import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models.dart';
import '../core/result.dart';
import '../state/app_controller.dart';
import '../twitch/helix.dart';
import 'theme.dart';
import 'widgets/glass_panel.dart';

Future<void> showExploreSheet(BuildContext context, AppController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ExploreSheet(controller: controller),
  );
}

final class ExploreSheet extends StatefulWidget {
  const ExploreSheet({super.key, required this.controller});
  final AppController controller;

  @override
  State<ExploreSheet> createState() => _ExploreSheetState();
}

final class _ExploreSheetState extends State<ExploreSheet> {
  final TextEditingController _search = TextEditingController();
  String _activeQuery = '';
  String _requestError = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run(''));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = freedomTokens(context);
    return FractionallySizedBox(
      widthFactor: .96,
      heightFactor: .96,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Material(
          color: tokens.canvas,
          child: AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, _) => Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 14, 14),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 42,
                        height: 5,
                        decoration: BoxDecoration(
                          color: tokens.border,
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      const SizedBox(width: 18),
                      const Icon(Icons.travel_explore_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Explore live text metadata',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const _PrivacyBadge(),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const NeonDivider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _search,
                          autofocus: false,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _run,
                          decoration: const InputDecoration(
                            labelText: 'Search live channels or topics',
                            hintText: 'science, programming, music…',
                            prefixIcon: Icon(Icons.search_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: controller.busy
                            ? null
                            : () => _run(_search.text),
                        icon: const Icon(Icons.radar_rounded),
                        label: const Text('Search'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: controller.busy ? null : () => _run(''),
                        icon: const Icon(Icons.people_alt_rounded),
                        label: const Text('Followed'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      children:
                          <String>[
                                'Software Development',
                                'Science & Technology',
                                'Just Chatting',
                                'Music',
                                'Makers & Crafting',
                              ]
                              .map(
                                (String topic) => ActionChip(
                                  label: Text(topic),
                                  avatar: const Icon(
                                    Icons.tag_rounded,
                                    size: 16,
                                  ),
                                  onPressed: () {
                                    _search.text = topic;
                                    _run(topic);
                                  },
                                ),
                              )
                              .toList(growable: false),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: controller.busy && controller.discovery.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : controller.discovery.isEmpty
                      ? _EmptyExplore(
                          query: _activeQuery,
                          error: _requestError,
                          onRetry: () => _run(_activeQuery),
                        )
                      : Scrollbar(
                          child: ListView.separated(
                            primary: true,
                            padding: const EdgeInsets.fromLTRB(22, 6, 22, 30),
                            itemCount: controller.discovery.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) =>
                                _DiscoveryCard(
                                  item: controller.discovery[index],
                                  thumbnail: controller.thumbnailFor(
                                    controller.discovery[index].channel,
                                  ),
                                  onAdd: () =>
                                      _add(controller.discovery[index]),
                                  onPlay: () =>
                                      _play(controller.discovery[index]),
                                ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _run(String value) async {
    if (!mounted) return;
    setState(() {
      _activeQuery = value.trim();
      _requestError = '';
    });
    final result = await widget.controller.searchDiscovery(value);
    if (!mounted) return;
    setState(() {
      _requestError = switch (result) {
        AppError<List<DiscoveryStream>>(:final error) => error.message,
        _ => '',
      };
    });
  }

  Future<void> _add(DiscoveryStream item) async {
    final result = await widget.controller.addStream(item.channel);
    if (!mounted) return;
    if (result is AppSuccess) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Added ${item.displayName}.')));
    } else if (result is AppError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text((result as AppError).error.message)),
      );
    }
  }

  Future<void> _play(DiscoveryStream item) async {
    final added = await widget.controller.addStream(item.channel);
    if (added is AppSuccess) {
      await widget.controller.startPlayback();
      if (mounted) Navigator.pop(context);
    } else if (added case AppError<StreamRecord>(:final error) when mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

final class _PrivacyBadge extends StatelessWidget {
  const _PrivacyBadge();
  @override
  Widget build(BuildContext context) => const Chip(
    avatar: Icon(Icons.image_not_supported_rounded, size: 16),
    label: Text('No thumbnails'),
  );
}

final class _EmptyExplore extends StatelessWidget {
  const _EmptyExplore({
    required this.query,
    required this.error,
    required this.onRetry,
  });
  final String query;
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.manage_search_rounded,
            size: 54,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            error.isNotEmpty
                ? error
                : query.isEmpty
                ? 'Authorize Twitch to load followed streams'
                : 'No matching live text records',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 7),
          if (error.isNotEmpty) ...<Widget>[
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
            const SizedBox(height: 10),
          ],
          Text(
            'Previews are accepted only from Twitch CDN over HTTPS, size and signature checked, encrypted locally, and expired automatically.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

final class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({
    required this.item,
    required this.thumbnail,
    required this.onAdd,
    required this.onPlay,
  });
  final DiscoveryStream item;
  final Uint8List? thumbnail;
  final VoidCallback onAdd;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(20),
      child: GlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 96,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(15),
              ),
              child: thumbnail != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(15),
                      child: Image.memory(
                        thumbnail!,
                        fit: BoxFit.cover,
                        width: 96,
                        height: 54,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.live_tv_rounded),
                      ),
                    )
                  : Text(
                      item.displayName.isEmpty
                          ? '?'
                          : item.displayName.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          item.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: tokens.danger,
                        ),
                      ),
                      const SizedBox(width: 5),
                      const Text(
                        'LIVE',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  if (item.title.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      if (item.category.isNotEmpty)
                        _MetaChip(Icons.category_rounded, item.category),
                      if (item.language.isNotEmpty)
                        _MetaChip(
                          Icons.translate_rounded,
                          item.language.toUpperCase(),
                        ),
                      if (item.viewerCount > 0)
                        _MetaChip(
                          Icons.visibility_rounded,
                          NumberFormat.compact().format(item.viewerCount),
                        ),
                      _MetaChip(
                        Icons.schedule_rounded,
                        DateFormat.Hm().format(item.startedAt.toLocal()),
                      ),
                    ],
                  ),
                  if (item.reason.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.reason,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens.good),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                const SizedBox(height: 6),
                IconButton(
                  tooltip: 'Save channel',
                  onPressed: onAdd,
                  icon: const Icon(Icons.bookmark_add_outlined),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _MetaChip extends StatelessWidget {
  const _MetaChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(
        icon,
        size: 14,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}
