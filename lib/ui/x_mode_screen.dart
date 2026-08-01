import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/result.dart';
import '../state/app_controller.dart';
import '../x/x_models.dart';
import '../x/x_oauth.dart';
import 'widgets/glass_panel.dart';
import 'widgets/x_secure_media.dart';

final class XModeScreen extends StatefulWidget {
  const XModeScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<XModeScreen> createState() => _XModeScreenState();
}

final class _FeedView extends StatelessWidget {
  const _FeedView({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Text(switch (controller.xContentSource) {
              XContentSource.home => 'My feed',
              XContentSource.search => 'Search results',
              XContentSource.account => 'Account posts',
            }, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Text('Auto refresh'),
          const SizedBox(width: 6),
          Switch(
            value: controller.xAutoRefresh,
            onChanged: controller.xContentSource == XContentSource.home
                ? controller.setXAutoRefresh
                : null,
          ),
          IconButton(
            onPressed: controller.xUserConnected
                ? controller.loadXHomeFeed
                : null,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh feed',
          ),
        ],
      ),
      const SizedBox(height: 6),
      Expanded(child: _PostsList(controller: controller)),
    ],
  );
}

final class _ContentCarousel extends StatefulWidget {
  const _ContentCarousel({required this.controller});
  final AppController controller;

  @override
  State<_ContentCarousel> createState() => _ContentCarouselState();
}

final class _ContentCarouselState extends State<_ContentCarousel> {
  final PageController _pages = PageController(viewportFraction: .88);
  Timer? _advance;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _startAdvance();
  }

  void _startAdvance() {
    _advance?.cancel();
    _advance = Timer.periodic(const Duration(seconds: 9), (_) => _next());
  }

  void _setMediaPlaying(bool playing) {
    if (playing) {
      _advance?.cancel();
      _advance = null;
    } else if (_advance == null) {
      _startAdvance();
    }
  }

  void _next() {
    final count = widget.controller.xPosts.length;
    if (!mounted || count < 2 || !_pages.hasClients) return;
    _index = (_index + 1) % count;
    _pages.animateToPage(
      _index,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = widget.controller.xPosts;
    if (posts.isEmpty) {
      return const Center(child: Icon(Icons.view_carousel_outlined, size: 48));
    }
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '${_index + 1} / ${posts.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            IconButton(
              onPressed: () => _pages.previousPage(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
              icon: const Icon(Icons.chevron_left_rounded),
              tooltip: 'Previous',
            ),
            IconButton(
              onPressed: _next,
              icon: const Icon(Icons.chevron_right_rounded),
              tooltip: 'Next',
            ),
          ],
        ),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: posts.length,
            onPageChanged: (value) => setState(() => _index = value),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: GlassPanel(
                padding: const EdgeInsets.all(14),
                child: _CarouselPost(
                  controller: widget.controller,
                  post: posts[index],
                  onPlaybackChanged: _setMediaPlaying,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _advance?.cancel();
    _pages.dispose();
    super.dispose();
  }
}

final class _CarouselPost extends StatelessWidget {
  const _CarouselPost({
    required this.controller,
    required this.post,
    required this.onPlaybackChanged,
  });
  final AppController controller;
  final XPost post;
  final ValueChanged<bool> onPlaybackChanged;

  @override
  Widget build(BuildContext context) {
    final media = post.media.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _AuthorLine(post: post),
        const SizedBox(height: 10),
        if (media != null && media.previewUrl != null)
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: media.type == 'photo'
                  ? XSecureImage(uri: media.previewUrl!)
                  : media.playbackUrl == null
                  ? XSecureImage(uri: media.previewUrl!)
                  : XSecureVideo(
                      uri: media.playbackUrl!,
                      posterUri: media.previewUrl,
                      onPlaybackChanged: onPlaybackChanged,
                    ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(height: 12),
        SelectableText(post.text, maxLines: 6),
        if (media?.downloadUrl != null) ...<Widget>[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => controller.storeXMedia(post, media!),
            icon: const Icon(Icons.lock_rounded),
            label: const Text('Store encrypted'),
          ),
        ],
      ],
    );
  }
}

final class _AuthorLine extends StatelessWidget {
  const _AuthorLine({required this.post});
  final XPost post;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      SizedBox.square(
        dimension: 34,
        child: post.authorAvatarUrl == null
            ? const CircleAvatar(child: Icon(Icons.person_rounded, size: 18))
            : XSecureImage(
                uri: post.authorAvatarUrl!,
                borderRadius: BorderRadius.circular(17),
              ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              post.authorName.isEmpty ? 'X account' : post.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (post.authorUsername.isNotEmpty)
              Text(
                '@${post.authorUsername}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
      ),
    ],
  );
}

final class _XModeScreenState extends State<XModeScreen> {
  late final TextEditingController _handle;
  late final TextEditingController _clientId;
  final TextEditingController _clientSecret = TextEditingController();
  final TextEditingController _token = TextEditingController();
  bool _showToken = false;
  bool _showClientSecret = false;
  final TextEditingController _search = TextEditingController();
  int _view = 0;
  String _language = 'any';
  bool _mediaOnly = false;
  bool _excludeReposts = true;
  bool _excludeReplies = false;
  int _scanLoops = 4;
  int _scanMinutes = 2;
  double _maxNegativity = .55;
  double _minWeirdness = 0;
  bool _memesOnly = false;
  XContentMood _mood = XContentMood.any;
  XContentTopic _topic = XContentTopic.any;
  XContentColor _color = XContentColor.any;
  bool _labWorking = false;
  String _labMessage = '';

  @override
  void initState() {
    super.initState();
    _handle = TextEditingController(text: widget.controller.xHandle);
    _clientId = TextEditingController(text: widget.controller.xClientId);
    if (widget.controller.xUserConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(widget.controller.loadXHomeFeed());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.controller.xRevision,
      builder: (context, _, __) => Column(
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(
                  value: 0,
                  icon: Icon(Icons.home_rounded),
                  label: Text('My feed'),
                ),
                ButtonSegment<int>(
                  value: 5,
                  icon: Icon(Icons.person_search_rounded),
                  label: Text('Account'),
                ),
                ButtonSegment<int>(
                  value: 1,
                  icon: Icon(Icons.manage_search_rounded),
                  label: Text('Search'),
                ),
                ButtonSegment<int>(
                  value: 2,
                  icon: Icon(Icons.view_carousel_rounded),
                  label: Text('Carousel'),
                ),
                ButtonSegment<int>(
                  value: 3,
                  icon: Icon(Icons.enhanced_encryption_rounded),
                  label: Text('Vault'),
                ),
                ButtonSegment<int>(
                  value: 4,
                  icon: Icon(Icons.settings_rounded),
                  label: Text('X Settings'),
                ),
                ButtonSegment<int>(
                  value: 6,
                  icon: Icon(Icons.people_alt_rounded),
                  label: Text('Follows'),
                ),
                ButtonSegment<int>(
                  value: 7,
                  icon: Icon(Icons.auto_awesome_rounded),
                  label: Text('Content Lab'),
                ),
              ],
              selected: <int>{_view},
              onSelectionChanged: (value) => _selectView(value.first),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: switch (_view) {
              0 => _FeedView(controller: widget.controller),
              1 => _searchView(),
              2 => _ContentCarousel(controller: widget.controller),
              3 => _MediaVault(controller: widget.controller),
              5 => _FeedView(controller: widget.controller),
              6 => _followsView(),
              7 => _contentLabView(),
              _ => _settingsView(),
            },
          ),
        ],
      ),
    );
  }

  Widget _settingsView() => GlassPanel(
    padding: const EdgeInsets.all(16),
    child: ListView(
      children: <Widget>[
        Text('X connection', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(
          'Credentials are encrypted in your local vault. Empty secret fields keep their currently saved values.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        _handleField(),
        const SizedBox(height: 12),
        _bearerTokenField(),
        const SizedBox(height: 12),
        _clientIdField(),
        const SizedBox(height: 12),
        _clientSecretField(),
        const SizedBox(height: 12),
        const Text('OAuth callback'),
        const SizedBox(height: 4),
        SelectableText(
          XOAuthService.callbackUri.toString(),
          key: ValueKey<String>('x-oauth-callback'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              key: const ValueKey<String>('x-save-settings'),
              onPressed: _saveSettings,
              icon: const Icon(Icons.save_rounded),
              label: const Text('Save settings'),
            ),
            _oauthButton(),
            OutlinedButton.icon(
              onPressed: _removeCredentials,
              icon: const Icon(Icons.delete_forever_rounded),
              label: const Text('Remove credentials'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'API access: ${widget.controller.xConfigured ? 'configured' : 'not configured'}  •  '
          'My Feed: ${widget.controller.xUserConnected ? 'connected' : 'not connected'}  •  '
          'Client secret: ${widget.controller.xClientSecretConfigured ? 'stored' : 'not stored'}',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    ),
  );

  Widget _followsView() => GlassPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.offline_pin_rounded),
          title: Text(
            '${widget.controller.xFollows.length} offline connections',
          ),
          subtitle: const Text(
            'Encrypted followers and following; sync requires follows.read',
          ),
          trailing: IconButton(
            onPressed: widget.controller.xUserConnected
                ? widget.controller.syncXFollows
                : null,
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync encrypted follows',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: widget.controller.xFollows.isEmpty
              ? const Center(
                  child: Icon(Icons.people_outline_rounded, size: 46),
                )
              : ListView.builder(
                  itemCount: widget.controller.xFollows.length,
                  itemBuilder: (context, index) {
                    final follow = widget.controller.xFollows[index];
                    return ListTile(
                      leading: SizedBox.square(
                        dimension: 38,
                        child: follow.avatarUrl == null
                            ? const CircleAvatar(
                                child: Icon(Icons.person_rounded),
                              )
                            : XSecureImage(
                                uri: follow.avatarUrl!,
                                borderRadius: BorderRadius.circular(19),
                              ),
                      ),
                      title: Text(follow.name),
                      trailing: Text(
                        follow.isFollowing && follow.followsYou
                            ? 'Mutual'
                            : follow.followsYou
                            ? 'Follows you'
                            : 'Following',
                      ),
                      subtitle: Text(
                        '@${follow.username}${follow.description.isEmpty ? '' : '  ${follow.description}'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Widget _contentLabView() {
    final scores = widget.controller.xContentScores;
    final runtime = widget.controller.gemma.current;
    final matches = widget.controller.xPosts
        .where((post) {
          final score = scores[post.id];
          if (score == null || score.negativity > _maxNegativity) return false;
          if (score.weirdness < _minWeirdness) return false;
          if (_memesOnly && score.meme < .55) return false;
          if (_mood != XContentMood.any && score.mood != _mood) return false;
          if (_topic != XContentTopic.any && !score.topics.contains(_topic))
            return false;
          if (_color != XContentColor.any && !score.colors.contains(_color))
            return false;
          return true;
        })
        .toList(growable: false);
    final topicCounts = <XContentTopic, int>{};
    for (final score in scores.values) {
      for (final topic in score.topics) {
        topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
      }
    }
    return GlassPanel(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                runtime.loaded
                    ? Icons.check_circle_rounded
                    : Icons.memory_rounded,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  runtime.loaded
                      ? 'Gemma 4 ready on device'
                      : runtime.installed
                      ? 'Gemma 4 installed but not loaded'
                      : 'Gemma 4 model is not installed',
                ),
              ),
              if (!runtime.loaded)
                FilledButton.tonalIcon(
                  onPressed: _labWorking ? null : _prepareContentLab,
                  icon: Icon(
                    runtime.installed
                        ? Icons.play_arrow_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(
                    runtime.installed ? 'Load model' : 'Install model',
                  ),
                ),
            ],
          ),
          if (_labMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(_labMessage, style: Theme.of(context).textTheme.bodySmall),
          ],
          const Divider(),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              DropdownButton<XContentMood>(
                value: _mood,
                items: _enumItems(XContentMood.values),
                onChanged: (value) =>
                    setState(() => _mood = value ?? XContentMood.any),
              ),
              DropdownButton<XContentTopic>(
                value: _topic,
                items: _enumItems(XContentTopic.values),
                onChanged: (value) =>
                    setState(() => _topic = value ?? XContentTopic.any),
              ),
              DropdownButton<XContentColor>(
                value: _color,
                items: _enumItems(XContentColor.values),
                onChanged: (value) =>
                    setState(() => _color = value ?? XContentColor.any),
              ),
              FilterChip(
                label: const Text('Memes'),
                selected: _memesOnly,
                onSelected: (value) => setState(() => _memesOnly = value),
              ),
              _stepper(
                'Loops',
                _scanLoops,
                1,
                20,
                (value) => _scanLoops = value,
              ),
              _stepper(
                'Minutes',
                _scanMinutes,
                1,
                30,
                (value) => _scanMinutes = value,
              ),
              FilledButton.icon(
                onPressed: _labWorking
                    ? null
                    : widget.controller.xContentScanning
                    ? widget.controller.stopXContentScan
                    : _runContentLab,
                icon: Icon(
                  widget.controller.xContentScanning
                      ? Icons.stop_rounded
                      : Icons.auto_awesome_rounded,
                ),
                label: Text(
                  widget.controller.xContentScanning ? 'Stop' : 'Scan locally',
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Text('Low negativity'),
              Expanded(
                child: Slider(
                  value: _maxNegativity,
                  onChanged: (value) => setState(() => _maxNegativity = value),
                ),
              ),
              const Text('More weird'),
              Expanded(
                child: Slider(
                  value: _minWeirdness,
                  onChanged: (value) => setState(() => _minWeirdness = value),
                ),
              ),
            ],
          ),
          if (topicCounts.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                children: topicCounts.entries
                    .map(
                      (entry) => ActionChip(
                        label: Text('${entry.key.name} ${entry.value}'),
                        onPressed: () => setState(() => _topic = entry.key),
                      ),
                    )
                    .toList(),
              ),
            ),
          const Divider(),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      scores.isEmpty
                          ? 'Load content, then run Gemma 4 locally.'
                          : 'No content matches these filters.',
                    ),
                  )
                : ListView.separated(
                    itemCount: matches.length,
                    separatorBuilder: (_, __) => const Divider(height: 20),
                    itemBuilder: (context, index) {
                      final post = matches[index];
                      final score = scores[post.id]!;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _PostItem(controller: widget.controller, post: post),
                          const SizedBox(height: 6),
                          Text(
                            '${score.mood.name}  •  weird ${(score.weirdness * 100).round()}%  •  '
                            'negative ${(score.negativity * 100).round()}%  •  meme ${(score.meme * 100).round()}%',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          if (score.summary.isNotEmpty) Text(score.summary),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _prepareContentLab() async {
    setState(() {
      _labWorking = true;
      _labMessage = 'Preparing the verified local model…';
    });
    final result = widget.controller.gemma.current.installed
        ? await widget.controller.loadGemma()
        : await widget.controller.installAndLoadGemma();
    if (!mounted) return;
    setState(() {
      _labWorking = false;
      _labMessage = switch (result) {
        AppSuccess<void>() => 'Gemma 4 is ready for private scanning.',
        AppError<void>(error: final failure) => failure.message,
      };
    });
  }

  Future<void> _runContentLab() async {
    setState(() {
      _labMessage = 'Scanning bounded post batches locally…';
    });
    final result = await widget.controller.runXContentScan(
      loops: _scanLoops,
      timeLimit: Duration(minutes: _scanMinutes),
    );
    if (!mounted) return;
    setState(() {
      _labMessage = switch (result) {
        AppSuccess<int>(value: final count) =>
          'Finished $count loop${count == 1 ? '' : 's'}; ${widget.controller.xContentScores.length} posts classified.',
        AppError<int>(error: final failure) => failure.message,
      };
    });
  }

  List<DropdownMenuItem<T>> _enumItems<T extends Enum>(List<T> values) => values
      .map(
        (value) => DropdownMenuItem<T>(value: value, child: Text(value.name)),
      )
      .toList(growable: false);

  Widget _stepper(
    String label,
    int value,
    int min,
    int max,
    ValueChanged<int> update,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text('$label $value'),
      IconButton(
        onPressed: value <= min
            ? null
            : () => setState(() => update(value - 1)),
        icon: const Icon(Icons.remove_rounded),
        tooltip: 'Decrease $label',
      ),
      IconButton(
        onPressed: value >= max
            ? null
            : () => setState(() => update(value + 1)),
        icon: const Icon(Icons.add_rounded),
        tooltip: 'Increase $label',
      ),
    ],
  );

  void _selectView(int view) {
    setState(() => _view = view);
    if (view == 0 && widget.controller.xUserConnected) {
      unawaited(widget.controller.loadXHomeFeed());
    } else if (view == 5 && widget.controller.xConfigured) {
      unawaited(widget.controller.loadXPosts(_handle.text));
    }
  }

  Widget _handleField() {
    final handle = TextField(
      key: const ValueKey<String>('x-handle'),
      controller: _handle,
      maxLength: 16,
      decoration: const InputDecoration(
        labelText: 'Public account handle (Account tab)',
        counterText: '',
        prefixText: '@',
      ),
      onSubmitted: (_) => _saveSettings(),
    );
    return handle;
  }

  Widget _bearerTokenField() => TextField(
    key: const ValueKey<String>('x-bearer-token'),
    controller: _token,
    obscureText: !_showToken,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: 'App-only bearer token (optional)',
      suffixIcon: IconButton(
        onPressed: () => setState(() => _showToken = !_showToken),
        icon: Icon(
          _showToken ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        ),
        tooltip: _showToken ? 'Hide token' : 'Show token',
      ),
    ),
  );

  Widget _clientIdField() => TextField(
    key: const ValueKey<String>('x-oauth-client-id'),
    controller: _clientId,
    autocorrect: false,
    enableSuggestions: false,
    decoration: const InputDecoration(
      labelText: 'OAuth client ID',
      prefixIcon: Icon(Icons.key_rounded),
    ),
  );

  Widget _clientSecretField() => TextField(
    key: const ValueKey<String>('x-oauth-client-secret'),
    controller: _clientSecret,
    obscureText: !_showClientSecret,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: 'OAuth client secret (confidential apps only)',
      prefixIcon: const Icon(Icons.password_rounded),
      suffixIcon: IconButton(
        onPressed: () => setState(() => _showClientSecret = !_showClientSecret),
        icon: Icon(
          _showClientSecret
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
        ),
        tooltip: _showClientSecret ? 'Hide secret' : 'Show secret',
      ),
    ),
  );

  Widget _oauthButton() => FilledButton.tonalIcon(
    onPressed: widget.controller.xUserConnected ? null : () => _connectMyFeed(),
    icon: Icon(
      widget.controller.xUserConnected
          ? Icons.verified_user_rounded
          : Icons.open_in_browser_rounded,
    ),
    label: Text(
      widget.controller.xUserConnected ? 'X user connected' : 'Connect My Feed',
    ),
  );

  Future<void> _saveSettings() async {
    FocusScope.of(context).unfocus();
    await widget.controller.saveXSettings(
      handle: _handle.text,
      bearerToken: _token.text,
      clientId: _clientId.text,
      clientSecret: _clientSecret.text,
    );
    _token.clear();
    _clientSecret.clear();
  }

  Future<void> _connectMyFeed() async {
    await _saveSettings();
    final connected = await widget.controller.connectXUser(_clientId.text);
    if (!mounted || connected is AppError<void>) return;
    setState(() => _view = 0);
    await widget.controller.loadXHomeFeed();
  }

  Future<void> _removeCredentials() async {
    await widget.controller.clearXCredentials();
    _token.clear();
    _clientId.clear();
    _clientSecret.clear();
  }

  Widget _searchView() => GlassPanel(
    padding: const EdgeInsets.all(12),
    child: Column(
      children: <Widget>[
        TextField(
          key: const ValueKey<String>('x-search-query'),
          controller: _search,
          maxLength: 512,
          decoration: InputDecoration(
            labelText: 'Recent X search',
            counterText: '',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: IconButton(
              onPressed: _runSearch,
              icon: const Icon(Icons.arrow_forward_rounded),
              tooltip: 'Search',
            ),
          ),
          onSubmitted: (_) => _runSearch(),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            DropdownButton<String>(
              value: _language,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'any', child: Text('Any language')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'es', child: Text('Spanish')),
                DropdownMenuItem(value: 'fr', child: Text('French')),
                DropdownMenuItem(value: 'de', child: Text('German')),
                DropdownMenuItem(value: 'ja', child: Text('Japanese')),
              ],
              onChanged: (value) => setState(() => _language = value ?? 'any'),
            ),
            FilterChip(
              label: const Text('Media'),
              selected: _mediaOnly,
              onSelected: (value) => setState(() => _mediaOnly = value),
            ),
            FilterChip(
              label: const Text('Hide reposts'),
              selected: _excludeReposts,
              onSelected: (value) => setState(() => _excludeReposts = value),
            ),
            FilterChip(
              label: const Text('Hide replies'),
              selected: _excludeReplies,
              onSelected: (value) => setState(() => _excludeReplies = value),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _PostsList(controller: widget.controller)),
      ],
    ),
  );

  Future<void> _runSearch() async {
    final terms = <String>[_search.text.trim()];
    if (_language != 'any') terms.add('lang:$_language');
    if (_mediaOnly) terms.add('has:media');
    if (_excludeReposts) terms.add('-is:retweet');
    if (_excludeReplies) terms.add('-is:reply');
    await widget.controller.searchX(
      terms.where((term) => term.isNotEmpty).join(' '),
    );
  }

  @override
  void dispose() {
    _handle.dispose();
    _clientId.dispose();
    _clientSecret.dispose();
    _token.dispose();
    _search.dispose();
    super.dispose();
  }
}

final class _PostsList extends StatelessWidget {
  const _PostsList({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        const ListTile(
          leading: Icon(Icons.dynamic_feed_rounded),
          title: Text('X posts'),
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.xPosts.isEmpty
              ? const Center(
                  child: Icon(Icons.alternate_email_rounded, size: 42),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: controller.xPosts.length,
                  separatorBuilder: (_, __) => const Divider(height: 18),
                  itemBuilder: (context, index) {
                    final post = controller.xPosts[index];
                    return _PostItem(controller: controller, post: post);
                  },
                ),
        ),
      ],
    ),
  );
}

final class _PostItem extends StatelessWidget {
  const _PostItem({required this.controller, required this.post});
  final AppController controller;
  final XPost post;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      _AuthorLine(post: post),
      const SizedBox(height: 6),
      Row(
        children: <Widget>[
          Expanded(
            child: Text(
              post.createdAt == null
                  ? post.id
                  : DateFormat.yMMMd().add_jm().format(
                      post.createdAt!.toLocal(),
                    ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          if (post.sensitive)
            const Icon(Icons.visibility_off_rounded, size: 16),
        ],
      ),
      const SizedBox(height: 5),
      SelectableText(post.text),
      if (post.media.firstOrNull case final media?) ...<Widget>[
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: media.type == 'photo' && media.previewUrl != null
                ? XSecureImage(uri: media.previewUrl!)
                : media.playbackUrl != null
                ? XSecureVideo(
                    uri: media.playbackUrl!,
                    posterUri: media.previewUrl,
                  )
                : media.previewUrl != null
                ? XSecureImage(uri: media.previewUrl!)
                : const ColoredBox(color: Colors.black12),
          ),
        ),
      ],
      if (post.media.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: post.media.map((media) {
            final stored = controller.xStoredMedia.any(
              (item) => item.postId == post.id && item.mediaKey == media.key,
            );
            return ActionChip(
              avatar: Icon(
                stored
                    ? Icons.lock_rounded
                    : media.type == 'photo'
                    ? Icons.image_rounded
                    : Icons.movie_rounded,
                size: 17,
              ),
              label: Text(stored ? 'Stored' : 'Encrypt ${media.type}'),
              onPressed: stored || media.downloadUrl == null
                  ? null
                  : () => controller.storeXMedia(post, media),
            );
          }).toList(),
        ),
      ],
    ],
  );
}

final class _MediaVault extends StatelessWidget {
  const _MediaVault({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => GlassPanel(
    padding: EdgeInsets.zero,
    child: Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.enhanced_encryption_rounded),
          title: const Text('Encrypted media'),
          trailing: IconButton(
            onPressed: controller.xStoredMedia.isEmpty
                ? null
                : controller.rotateXMediaKeys,
            icon: const Icon(Icons.key_rounded),
            tooltip: 'Rotate media keys',
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.xStoredMedia.isEmpty
              ? const Center(child: Icon(Icons.lock_outline_rounded, size: 42))
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: controller.xStoredMedia.length,
                  itemBuilder: (context, index) {
                    final media = controller.xStoredMedia[index];
                    return ListTile(
                      leading: Icon(
                        media.contentType == 'video/mp4'
                            ? Icons.movie_rounded
                            : Icons.image_rounded,
                      ),
                      title: Text(
                        media.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${_formatBytes(media.byteLength)}  •  key v${media.keyVersion}',
                      ),
                      trailing: IconButton(
                        onPressed: () => _confirmDelete(context, media),
                        icon: const Icon(Icons.delete_forever_rounded),
                        tooltip: 'Cryptographically erase',
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );

  Future<void> _confirmDelete(BuildContext context, XStoredMedia media) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erase encrypted media?'),
        content: Text(media.filename),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteXMedia(media);
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }
}

extension _FirstOrNullXUi<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
