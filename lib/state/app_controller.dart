import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../ai/agent_orchestrator.dart';
import '../ai/ai_models.dart';
import '../ai/gemma_runtime.dart';
import '../ai/memory_store.dart';
import '../ai/speech_context.dart';
import '../chat/irc_client.dart';
import '../core/app_config.dart';
import '../core/boot_pipeline.dart';
import '../core/models.dart';
import '../core/pulse_scheduler.dart';
import '../core/result.dart';
import '../core/secure_log.dart';
import '../playback/playback_controller.dart';
import '../security/vault.dart';
import '../twitch/helix.dart';
import '../twitch/hls_parser.dart';
import '../twitch/stream_resolver.dart';
import '../twitch/twitch_auth.dart';
import '../x/x_api.dart';
import '../x/x_content_lab.dart';
import '../x/x_media_store.dart';
import '../x/x_models.dart';
import '../x/x_oauth.dart';

final class AppController extends ChangeNotifier {
  AppController() {
    vault = VaultRepository(log: log);
    auth = TwitchAuthService(vault: vault, log: log);
    helix = TwitchHelixService(auth: auth, log: log);
    resolver = TwitchStreamResolver(log: log);
    playback = UnifiedPlaybackController(log: log);
    irc = TwitchIrcClient(log: log);
    scheduler = PulseScheduler(log: log)..start();
    bootPipeline = BootPipeline(log: log);
    memory = AiMemoryStore(vault);
    gemma = GemmaRuntime(vault: vault, log: log);
    speech = SpeechContextService(
      playback: playback,
      memory: memory,
      vault: vault,
      log: log,
    );
    agents = AgentOrchestrator(
      runtime: gemma,
      memory: memory,
      log: log,
      scheduler: scheduler,
    );
    xApi = XApiService(log: log);
    xMediaStore = XMediaStore(vault: vault, log: log);
    xOAuth = XOAuthService(log: log);
    xContentLab = XContentLab(gemma);
    playback.addListener(_relay);
    _subscriptions.add(irc.events.listen(_handleChatEvent));
    _subscriptions.add(
      gemma.states.listen((state) {
        if (_disposed) return;
        _refreshSchedulerSignals(modelReady: state.loaded);
        _pulse(shell: true, ai: true);
        notifyListeners();
      }),
    );
    _subscriptions.add(
      speech.states.listen((_) {
        if (_disposed) return;
        _refreshSchedulerSignals();
        _pulse(ai: true);
        notifyListeners();
      }),
    );
    _subscriptions.add(agents.cards.listen(_handleCompanionCard));
    _subscriptions.add(agents.reports.listen(_applyAssessments));
    _subscriptions.add(
      scheduler.snapshots.listen((PulseSnapshot snapshot) {
        if (_disposed) return;
        _schedulerSnapshot = snapshot;
        schedulerTelemetry.value = snapshot;
      }),
    );
  }

  final SecureLog log = SecureLog();
  final ValueNotifier<int> shellRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> navigationRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> chatRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> aiRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> preferencesRevision = ValueNotifier<int>(0);
  final ValueNotifier<int> xRevision = ValueNotifier<int>(0);
  final ValueNotifier<PulseSnapshot?> schedulerTelemetry =
      ValueNotifier<PulseSnapshot?>(null);
  late final VaultRepository vault;
  late final TwitchAuthService auth;
  late final TwitchHelixService helix;
  late final TwitchStreamResolver resolver;
  late final UnifiedPlaybackController playback;
  late final TwitchIrcClient irc;
  late final PulseScheduler scheduler;
  late final BootPipeline bootPipeline;
  late final AiMemoryStore memory;
  late final GemmaRuntime gemma;
  late final SpeechContextService speech;
  late final AgentOrchestrator agents;
  late final XApiService xApi;
  late final XMediaStore xMediaStore;
  late final XOAuthService xOAuth;
  late final XContentLab xContentLab;
  final Uuid _uuid = const Uuid();
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  VaultStatus? _vaultStatus;
  bool _booting = true;
  bool _unlocked = false;
  bool _busy = false;
  String _status = 'Starting secure services…';
  String _error = '';
  AppPreferences _preferences = const AppPreferences();
  List<StreamRecord> _streams = <StreamRecord>[];
  List<DiscoveryStream> _discovery = <DiscoveryStream>[];
  List<ChatMessage> _chat = <ChatMessage>[];
  List<CompanionCard> _companionCards = <CompanionCard>[];
  List<XPost> _xPosts = <XPost>[];
  List<XStoredMedia> _xStoredMedia = <XStoredMedia>[];
  List<XFollow> _xFollows = <XFollow>[];
  final Map<String, XContentScore> _xContentScores = <String, XContentScore>{};
  bool _xContentScanning = false;
  bool _xContentScanCancelled = false;
  int _xContentScanCompleted = 0;
  String _xBearerToken = '';
  String _xHandle = '';
  String _xClientId = '';
  String _xClientSecret = '';
  String _xUserAccessToken = '';
  String _xRefreshToken = '';
  DateTime? _xUserTokenExpiresAt;
  XContentSource _xContentSource = XContentSource.account;
  bool _xAutoRefresh = false;
  bool _xFeedRefreshInFlight = false;
  String? _xFeedNextToken;
  StreamRecord? _selected;
  bool _chatConnected = false;
  String _chatStatus = 'Disconnected';
  String _speechText = '';
  Timer? _autoLock;
  PulseRecurringHandle? _speechRecurring;
  Timer? _chatPersistTimer;
  Timer? _chatSignalTimer;
  Timer? _xRefreshTimer;
  final Map<String, ChatMessage> _pendingChatPersistence =
      <String, ChatMessage>{};
  final Queue<DateTime> _recentChatTimes = Queue<DateTime>();
  final Set<String> _chatIds = <String>{};
  final Queue<String> _chatIdOrder = Queue<String>();
  final Map<String, String> _broadcasterIds = <String, String>{};
  Future<void> _chatPersistenceQueue = Future<void>.value();
  BootStage _bootStage = BootStage.platformPolicy;
  PulseSnapshot? _schedulerSnapshot;
  bool? _relayedPlaybackActive;
  bool? _relayedPlaybackBuffering;
  bool _disposed = false;

  VaultStatus? get vaultStatus => _vaultStatus;
  bool get booting => _booting;
  bool get unlocked => _unlocked;
  bool get busy => _busy;
  String get status => _status;
  String get error => _error;
  AppPreferences get preferences => _preferences;
  // Read-only views avoid copying up to 1,000 chat records on every frame.
  List<StreamRecord> get streams =>
      UnmodifiableListView<StreamRecord>(_streams);
  List<DiscoveryStream> get discovery =>
      UnmodifiableListView<DiscoveryStream>(_discovery);
  List<ChatMessage> get chat => UnmodifiableListView<ChatMessage>(_chat);
  List<CompanionCard> get companionCards =>
      UnmodifiableListView<CompanionCard>(_companionCards);
  List<XPost> get xPosts => UnmodifiableListView<XPost>(_xPosts);
  List<XStoredMedia> get xStoredMedia =>
      UnmodifiableListView<XStoredMedia>(_xStoredMedia);
  List<XFollow> get xFollows => UnmodifiableListView<XFollow>(_xFollows);
  Map<String, XContentScore> get xContentScores =>
      UnmodifiableMapView<String, XContentScore>(_xContentScores);
  bool get xContentScanning => _xContentScanning;
  int get xContentScanCompleted => _xContentScanCompleted;
  bool get xConfigured => _xBearerToken.isNotEmpty;
  String get xHandle => _xHandle;
  XContentSource get xContentSource => _xContentSource;
  bool get xAutoRefresh => _xAutoRefresh;
  bool get xFeedLoadingMore => _xFeedRefreshInFlight;
  bool get xFeedHasMore =>
      _xContentSource == XContentSource.home &&
      _xFeedNextToken != null &&
      _xFeedNextToken!.isNotEmpty;
  bool get xUserConnected => _xUserAccessToken.isNotEmpty;
  String get xClientId => _xClientId;
  bool get xClientSecretConfigured => _xClientSecret.isNotEmpty;
  StreamRecord? get selected => _selected;
  bool get chatConnected => _chatConnected;
  String get chatStatus => _chatStatus;
  String get speechText => _speechText;
  SpeechContextState get speechState => speech.current;
  BootStage get bootStage => _bootStage;
  PulseSnapshot? get schedulerSnapshot => _schedulerSnapshot;

  Future<void> bootstrap() async {
    _booting = true;
    _error = '';
    _pulse(shell: true);
    notifyListeners();
    try {
      await bootPipeline.run(
        <BootStep>[
          BootStep(
            stage: BootStage.platformPolicy,
            action: () async {
              if (Platform.isLinux) {
                final renderer =
                    Platform.environment['TWITCH_FREEDOM_RENDERER'] ??
                    'platform-default';
                final media =
                    Platform.environment['TWITCH_FREEDOM_MEDIA_RENDERER'] ??
                    'auto';
                log.info('Linux workload policy: ui=$renderer, media=$media.');
              }
            },
          ),
          BootStep(
            stage: BootStage.scheduler,
            action: () async {
              scheduler.start();
              _refreshSchedulerSignals();
            },
          ),
          BootStep(
            stage: BootStage.vaultProbe,
            action: () async {
              _vaultStatus = await vault.status();
            },
          ),
        ],
        onStage: (BootStage stage) {
          _bootStage = stage;
          _status = 'Boot stage: ${stage.name}…';
          _pulse(shell: true);
          notifyListeners();
        },
      );
      _booting = false;
      _status = _vaultStatus!.exists
          ? 'Unlock your encrypted workspace.'
          : 'Create your encrypted workspace.';
      _pulse(shell: true);
      notifyListeners();
      if (_vaultStatus!.rememberedUnlockAvailable) {
        _bootStage = BootStage.rememberedUnlock;
        final result = await vault.unlockRemembered();
        if (result is AppSuccess<void>) await _afterUnlock();
      }
    } catch (cause) {
      _booting = false;
      _setError('Secure startup failed: $cause');
    }
  }

  Future<AppResult<void>> createVault(
    String password, {
    required bool remember,
  }) async {
    _setBusy(true, 'Creating encrypted vault…');
    var result = await vault.create(
      password: password,
      rememberOnDevice: remember,
    );
    // Recover vaults committed by older builds that subsequently failed while
    // contacting a locked optional OS keyring. The password still authenticates
    // the complete encrypted vault, so unlock it instead of stranding the user.
    if (result case AppError<void>(
      error: final error,
    ) when error.code == 'vault_exists') {
      result = await vault.unlockWithPassword(password);
    }
    if (result is AppSuccess<void>) {
      _error = '';
      await _afterUnlock();
    }
    if (result is AppError<void>) _setError(result.error.message);
    _setBusy(false);
    return result;
  }

  Future<AppResult<void>> unlock(String password) async {
    _setBusy(true, 'Authenticating encrypted vault…');
    final result = await vault.unlockWithPassword(password);
    if (result is AppSuccess<void>) await _afterUnlock();
    if (result is AppError<void>) _setError(result.error.message);
    _setBusy(false);
    return result;
  }

  Future<void> _afterUnlock() async {
    _unlocked = true;
    scheduler.reopenScope('speech-capture');
    scheduler.reopenScope('agent-batch');
    scheduler.reopenScope('model-autoload');
    _vaultStatus = await vault.status();
    await bootPipeline.run(
      <BootStep>[
        BootStep(stage: BootStage.stateHydration, action: _loadState),
        BootStep(
          stage: BootStage.modelAttestation,
          action: gemma.refreshInstallationState,
        ),
        BootStep(
          stage: BootStage.speechAttestation,
          action: speech.refreshInstallationState,
        ),
      ],
      onStage: (BootStage stage) {
        _bootStage = stage;
        _status = 'Unlock stage: ${stage.name}…';
        _pulse(shell: true);
        notifyListeners();
      },
    );
    _resetAutoLock();
    _refreshSchedulerSignals();
    _bootStage = BootStage.ready;
    _status = 'Local vault unlocked. PulseMesh scheduler ready.';
    _pulse(
      shell: true,
      navigation: true,
      chat: true,
      ai: true,
      preferences: true,
    );
    notifyListeners();
  }

  Future<void> _loadState() async {
    final prefJson = await vault.getJson('preferences', 'main');
    _preferences = prefJson == null
        ? const AppPreferences()
        : AppPreferences.fromJson(prefJson);
    gemma.configureModelDirectory(_preferences.ai.modelDirectory);
    final streamJson = await vault.getAllJson('saved_stream');
    _streams = streamJson.map(StreamRecord.fromJson).toList()
      ..sort(
        (StreamRecord a, StreamRecord b) => (b.lastPlayedAt ?? b.updatedAt)
            .compareTo(a.lastPlayedAt ?? a.updatedAt),
      );
    _selected = _streams.isEmpty ? null : _streams.first;
    if (_selected != null) await _loadChatHistory(_selected!.channel);
    agents.configure(
      channel: _selected?.channel ?? '',
      settings: _preferences.ai,
      initialMessages: _chat,
    );
    final xCredentials = await vault.getJson('x_credentials', 'main');
    _xBearerToken = (xCredentials?['bearerToken'] as String?) ?? '';
    _xHandle = (xCredentials?['lastHandle'] as String?) ?? '';
    _xClientId = (xCredentials?['clientId'] as String?) ?? '';
    _xClientSecret = (xCredentials?['clientSecret'] as String?) ?? '';
    _xUserAccessToken = (xCredentials?['userAccessToken'] as String?) ?? '';
    _xRefreshToken = (xCredentials?['refreshToken'] as String?) ?? '';
    _xUserTokenExpiresAt = DateTime.tryParse(
      (xCredentials?['userTokenExpiresAt'] as String?) ?? '',
    );
    _xStoredMedia = await xMediaStore.list();
    _xFollows =
        (await vault.getAllJson('x_follow'))
            .map(XFollow.fromJson)
            .where((follow) => follow.id.isNotEmpty)
            .toList()
          ..sort((a, b) => a.username.compareTo(b.username));
  }

  Future<void> saveXCredentials({
    required String bearerToken,
    required String handle,
  }) async {
    final token = bearerToken.trim();
    if (token.isNotEmpty) _xBearerToken = token;
    _xHandle = handle.trim().replaceFirst(RegExp(r'^@'), '');
    await vault.putJson('x_credentials', 'main', <String, Object?>{
      'bearerToken': _xBearerToken,
      'lastHandle': _xHandle,
      'clientId': _xClientId,
      'clientSecret': _xClientSecret,
      'userAccessToken': _xUserAccessToken,
      'refreshToken': _xRefreshToken,
      'userTokenExpiresAt': _xUserTokenExpiresAt?.toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    _pulse(x: true);
    notifyListeners();
  }

  Future<void> saveXSettings({
    required String handle,
    String bearerToken = '',
    String clientId = '',
    String clientSecret = '',
  }) async {
    if (clientId.trim().isNotEmpty) _xClientId = clientId.trim();
    if (clientSecret.trim().isNotEmpty) _xClientSecret = clientSecret.trim();
    await saveXCredentials(bearerToken: bearerToken, handle: handle);
    _status = 'X settings saved in the encrypted vault.';
    _pulse(x: true);
    notifyListeners();
  }

  Future<AppResult<List<XPost>>> loadXPosts(String handle) async {
    _setBusy(true, 'Loading X posts through the official API…');
    _xHandle = handle.trim().replaceFirst(RegExp(r'^@'), '');
    final result = await xApi.userPosts(
      handle: _xHandle,
      bearerToken: _xBearerToken,
    );
    if (result case AppSuccess<List<XPost>>(value: final posts)) {
      _xPosts = posts;
      _xContentSource = XContentSource.account;
      await saveXCredentials(bearerToken: '', handle: _xHandle);
    } else if (result case AppError<List<XPost>>(error: final failure)) {
      _setError(failure.message);
    }
    _setBusy(false);
    _pulse(x: true);
    notifyListeners();
    return result;
  }

  Future<AppResult<List<XPost>>> loadXHomeFeed({bool quiet = false}) async {
    if (_xFeedRefreshInFlight) {
      return AppSuccess<List<XPost>>(_xPosts);
    }
    _xFeedRefreshInFlight = true;
    if (!quiet) _setBusy(true, 'Loading your X home feed…');
    try {
      final wasHome = _xContentSource == XContentSource.home;
      final existing = wasHome ? _xPosts : const <XPost>[];
      final sinceId = wasHome ? _newestXPostId(existing) : null;
      final tokenResult = await _validXUserToken();
      final result = await tokenResult.fold<Future<AppResult<XFeedPage>>>(
        success: (token) => xApi.homeFeed(bearerToken: token, sinceId: sinceId),
        failure: (failure) async => AppError<XFeedPage>(failure),
      );
      if (result case AppSuccess<XFeedPage>(value: final page)) {
        _xPosts = _mergeXPosts(page.posts, existing);
        if (!wasHome) _xFeedNextToken = page.nextToken;
        _xContentSource = XContentSource.home;
        _status = page.posts.isEmpty
            ? 'X home feed is current.'
            : 'Added ${page.posts.length} new X post${page.posts.length == 1 ? '' : 's'} securely.';
        if (!_xAutoRefresh) setXAutoRefresh(true);
      } else if (!quiet) {
        if (result case AppError<XFeedPage>(error: final failure)) {
          _setError(failure.message);
        }
      }
      return result.fold<AppResult<List<XPost>>>(
        success: (page) => AppSuccess<List<XPost>>(page.posts),
        failure: AppError<List<XPost>>.new,
      );
    } finally {
      _xFeedRefreshInFlight = false;
      if (!quiet) _setBusy(false);
      _pulse(x: true);
      notifyListeners();
    }
  }

  Future<AppResult<List<XPost>>> loadMoreXHomeFeed() async {
    final nextToken = _xFeedNextToken;
    if (_xFeedRefreshInFlight ||
        _xContentSource != XContentSource.home ||
        nextToken == null ||
        nextToken.isEmpty) {
      return AppSuccess<List<XPost>>(_xPosts);
    }
    _xFeedRefreshInFlight = true;
    _pulse(x: true);
    notifyListeners();
    try {
      final tokenResult = await _validXUserToken();
      final result = await tokenResult.fold<Future<AppResult<XFeedPage>>>(
        success: (token) =>
            xApi.homeFeed(bearerToken: token, paginationToken: nextToken),
        failure: (failure) async => AppError<XFeedPage>(failure),
      );
      if (result case AppSuccess<XFeedPage>(value: final page)) {
        final before = _xPosts.length;
        _xPosts = _mergeXPosts(_xPosts, page.posts);
        _xFeedNextToken = page.nextToken;
        final added = _xPosts.length - before;
        _status = added == 0
            ? 'No more X posts are available right now.'
            : 'Loaded $added older X post${added == 1 ? '' : 's'}.';
        return AppSuccess<List<XPost>>(_xPosts);
      }
      final failure = (result as AppError<XFeedPage>).error;
      _xFeedNextToken = null;
      _setError(failure.message);
      return AppError<List<XPost>>(failure);
    } finally {
      _xFeedRefreshInFlight = false;
      _pulse(x: true);
      notifyListeners();
    }
  }

  Future<AppResult<void>> connectXUser(
    String clientId, {
    String clientSecret = '',
  }) async {
    _setBusy(true, 'Waiting for X authorization…');
    if (clientId.trim().isNotEmpty) _xClientId = clientId.trim();
    if (clientSecret.trim().isNotEmpty) _xClientSecret = clientSecret.trim();
    await saveXCredentials(bearerToken: '', handle: _xHandle);
    final result = await xOAuth.authorize(
      _xClientId,
      clientSecret: _xClientSecret,
    );
    if (result case AppSuccess<XOAuthTokens>(value: final tokens)) {
      _xUserAccessToken = tokens.accessToken;
      _xRefreshToken = tokens.refreshToken;
      _xUserTokenExpiresAt = tokens.expiresAt;
      await saveXCredentials(bearerToken: '', handle: _xHandle);
      _status = 'X user access connected.';
      _setBusy(false);
      _pulse(x: true);
      notifyListeners();
      return const AppSuccess<void>(null);
    }
    final failure = (result as AppError<XOAuthTokens>).error;
    _setError(failure.message);
    _setBusy(false);
    return AppError<void>(failure);
  }

  Future<AppResult<String>> _validXUserToken() async {
    if (_xUserAccessToken.isEmpty) {
      return const AppError<String>(
        AppFailure(
          'x_user_context_required',
          'Connect your X account with OAuth before opening My Feed.',
        ),
      );
    }
    final expires = _xUserTokenExpiresAt;
    if (expires == null ||
        expires.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 2)),
        )) {
      return AppSuccess<String>(_xUserAccessToken);
    }
    if (_xRefreshToken.isEmpty || _xClientId.isEmpty) {
      return const AppError<String>(
        AppFailure('x_user_token_expired', 'Reconnect your X account.'),
      );
    }
    final refreshed = await xOAuth.refresh(
      clientId: _xClientId,
      clientSecret: _xClientSecret,
      refreshToken: _xRefreshToken,
    );
    if (refreshed case AppSuccess<XOAuthTokens>(value: final tokens)) {
      _xUserAccessToken = tokens.accessToken;
      _xRefreshToken = tokens.refreshToken;
      _xUserTokenExpiresAt = tokens.expiresAt;
      await saveXCredentials(bearerToken: '', handle: _xHandle);
      return AppSuccess<String>(_xUserAccessToken);
    }
    return AppError<String>((refreshed as AppError<XOAuthTokens>).error);
  }

  Future<AppResult<List<XPost>>> searchX(String query) async {
    _setBusy(true, 'Searching recent X posts…');
    final result = await xApi.searchRecent(
      query: query,
      bearerToken: _xBearerToken,
    );
    if (result case AppSuccess<List<XPost>>(value: final posts)) {
      _xPosts = posts;
      _xContentSource = XContentSource.search;
      _status = 'X search returned ${posts.length} posts.';
    } else if (result case AppError<List<XPost>>(error: final failure)) {
      _setError(failure.message);
    }
    _setBusy(false);
    _pulse(x: true);
    notifyListeners();
    return result;
  }

  Future<AppResult<List<XFollow>>> syncXFollows() async {
    _setBusy(true, 'Syncing your encrypted offline follows…');
    final token = await _validXUserToken();
    final result = await token.fold<Future<AppResult<List<XFollow>>>>(
      success: (value) async {
        final outgoing = await xApi.following(bearerToken: value);
        if (outgoing case AppError<List<XFollow>>()) return outgoing;
        final incoming = await xApi.followers(bearerToken: value);
        if (incoming case AppError<List<XFollow>>()) return incoming;
        final merged = <String, XFollow>{};
        for (final follow in (outgoing as AppSuccess<List<XFollow>>).value) {
          merged[follow.id] = follow;
        }
        for (final follower in (incoming as AppSuccess<List<XFollow>>).value) {
          final existing = merged[follower.id];
          merged[follower.id] = existing == null
              ? follower
              : existing.copyWith(followsYou: true);
        }
        return AppSuccess<List<XFollow>>(merged.values.toList());
      },
      failure: (failure) async => AppError<List<XFollow>>(failure),
    );
    if (result case AppSuccess<List<XFollow>>(value: final follows)) {
      await vault.deleteType('x_follow');
      await vault.putJsonBatch('x_follow', <String, Map<String, Object?>>{
        for (final follow in follows) follow.id: follow.toJson(),
      });
      await vault.purgeDeletedPages();
      _xFollows = follows..sort((a, b) => a.username.compareTo(b.username));
      _status =
          'Encrypted offline social graph updated: ${follows.length} accounts.';
    } else if (result case AppError<List<XFollow>>(error: final failure)) {
      _setError(failure.message);
    }
    _setBusy(false);
    _pulse(x: true);
    notifyListeners();
    return result;
  }

  Future<AppResult<int>> runXContentScan({
    required int loops,
    required Duration timeLimit,
  }) async {
    if (_xContentScanning) {
      const failure = AppFailure(
        'x_scan_running',
        'A Content Lab scan is already running.',
      );
      _setError(failure.message);
      return const AppError<int>(failure);
    }
    if (!gemma.isReady) {
      const failure = AppFailure(
        'model_not_ready',
        'Install or load Gemma 4 from Content Lab first.',
      );
      _setError(failure.message);
      return const AppError<int>(failure);
    }
    if (_xPosts.isEmpty && xUserConnected) await loadXHomeFeed();
    if (_xPosts.isEmpty) {
      const failure = AppFailure(
        'x_scan_empty',
        'Load My Feed, Account, or Search content first.',
      );
      _setError(failure.message);
      return const AppError<int>(failure);
    }
    final boundedLoops = loops.clamp(1, 20);
    final boundedTime = Duration(seconds: timeLimit.inSeconds.clamp(10, 1800));
    final deadline = DateTime.now().add(boundedTime);
    _xContentScanning = true;
    _xContentScanCancelled = false;
    _xContentScanCompleted = 0;
    _setBusy(true, 'Gemma 4 Content Lab scanning locally…');
    AppFailure? lastFailure;
    try {
      for (var loop = 0; loop < boundedLoops; loop++) {
        if (_xContentScanCancelled || DateTime.now().isAfter(deadline)) break;
        final offset = (loop * 5) % _xPosts.length;
        final batch = <XPost>[
          ..._xPosts.skip(offset).take(5),
          if (_xPosts.length < 5) ..._xPosts.take(5 - _xPosts.length),
        ];
        final scanned = await xContentLab.scan(batch);
        if (scanned case AppSuccess<List<XContentScore>>(value: final scores)) {
          for (final score in scores) _xContentScores[score.postId] = score;
          _xContentScanCompleted++;
          _status = 'Content Lab loop $_xContentScanCompleted complete.';
          _pulse(x: true);
          notifyListeners();
        } else if (scanned case AppError<List<XContentScore>>(
          error: final failure,
        )) {
          lastFailure = failure;
          break;
        }
      }
    } finally {
      _xContentScanning = false;
      _setBusy(false);
      _pulse(x: true);
      notifyListeners();
    }
    if (lastFailure != null) {
      _setError(lastFailure.message);
      return AppError<int>(lastFailure);
    }
    _status =
        'Content Lab finished $_xContentScanCompleted local loop${_xContentScanCompleted == 1 ? '' : 's'}.';
    notifyListeners();
    return AppSuccess<int>(_xContentScanCompleted);
  }

  void stopXContentScan() {
    _xContentScanCancelled = true;
    gemma.cancel();
  }

  void setXAutoRefresh(bool enabled) {
    _xRefreshTimer?.cancel();
    _xRefreshTimer = null;
    _xAutoRefresh = enabled;
    if (enabled) {
      _xRefreshTimer = Timer.periodic(const Duration(minutes: 2), (_) {
        if (_unlocked &&
            _xContentSource == XContentSource.home &&
            !_xFeedRefreshInFlight) {
          unawaited(loadXHomeFeed(quiet: true));
        }
      });
    }
    _pulse(x: true);
    notifyListeners();
  }

  List<XPost> _mergeXPosts(List<XPost> fresh, List<XPost> existing) {
    final seen = <String>{};
    final merged = <XPost>[
      ...fresh,
      ...existing,
    ].where((post) => seen.add(post.id)).toList();
    merged.sort((a, b) {
      final byTime = (b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
      if (byTime != 0) return byTime;
      return _compareXPostIds(b.id, a.id);
    });
    return List<XPost>.unmodifiable(merged);
  }

  String? _newestXPostId(List<XPost> posts) {
    String? newest;
    for (final post in posts) {
      if (!_isXPostId(post.id)) continue;
      if (newest == null || _compareXPostIds(post.id, newest) > 0) {
        newest = post.id;
      }
    }
    return newest;
  }

  bool _isXPostId(String value) =>
      value.isNotEmpty &&
      value.codeUnits.every((unit) => unit >= 48 && unit <= 57);

  int _compareXPostIds(String a, String b) {
    if (a.length != b.length) return a.length.compareTo(b.length);
    return a.compareTo(b);
  }

  Future<AppResult<XStoredMedia>> storeXMedia(XPost post, XMedia media) async {
    final url = media.downloadUrl;
    if (url == null) {
      return const AppError<XStoredMedia>(
        AppFailure(
          'x_media_unavailable',
          'X did not provide a downloadable media variant.',
        ),
      );
    }
    _setBusy(true, 'Encrypting X media as it downloads…');
    final result = await xMediaStore.download(
      url: url,
      postId: post.id,
      mediaKey: media.key,
      contentType: media.contentType,
    );
    if (result case AppSuccess<XStoredMedia>(value: final stored)) {
      _xStoredMedia.insert(0, stored);
      _status = 'Encrypted media stored. No plaintext cache was created.';
    } else if (result case AppError<XStoredMedia>(error: final failure)) {
      _setError(failure.message);
    }
    _setBusy(false);
    _pulse(x: true);
    notifyListeners();
    return result;
  }

  Future<void> deleteXMedia(XStoredMedia media) async {
    await xMediaStore.delete(media);
    _xStoredMedia.removeWhere((item) => item.id == media.id);
    _pulse(x: true);
    notifyListeners();
  }

  Future<AppResult<int>> rotateXMediaKeys() async {
    _setBusy(true, 'Rotating encrypted X media keys…');
    final result = await xMediaStore.rotateAll();
    if (result case AppSuccess<int>(value: final count)) {
      _xStoredMedia = await xMediaStore.list();
      _status = 'Rotated $count encrypted media item${count == 1 ? '' : 's'}.';
    } else if (result case AppError<int>(error: final failure)) {
      _setError(failure.message);
    }
    _setBusy(false);
    _pulse(x: true);
    notifyListeners();
    return result;
  }

  Future<void> clearXCredentials() async {
    setXAutoRefresh(false);
    _xBearerToken = '';
    _xPosts = <XPost>[];
    _xFollows = <XFollow>[];
    _xContentScores.clear();
    _xContentScanning = false;
    _xContentScanCancelled = true;
    _xClientId = '';
    _xClientSecret = '';
    _xUserAccessToken = '';
    _xRefreshToken = '';
    _xUserTokenExpiresAt = null;
    await vault.delete('x_credentials', 'main');
    await vault.purgeDeletedPages();
    _pulse(x: true);
    notifyListeners();
  }

  Future<AppResult<StreamRecord>> addStream(String input) async {
    try {
      final channel = _channelFromInput(input);
      if (channel == null)
        return const AppError<StreamRecord>(
          AppFailure(
            'invalid_stream',
            'Enter a Twitch channel name or HTTPS Twitch URL.',
          ),
        );
      final now = DateTime.now();
      final existing = _streams
          .where((StreamRecord item) => item.channel == channel)
          .firstOrNull;
      final record =
          existing ??
          StreamRecord(
            id: _uuid.v4(),
            channel: channel,
            displayName: channel,
            url: Uri.https('www.twitch.tv', '/$channel'),
            title: '',
            category: '',
            language: '',
            playbackMode: PlaybackMode.video,
            quality: _preferences.preferredQuality,
            volume: 1,
            createdAt: now,
            updatedAt: now,
            playCount: 0,
          );
      if (existing == null) _streams.insert(0, record);
      await vault.putJson('saved_stream', record.id, record.toJson());
      await selectStream(record);
      _pulse(navigation: true);
      notifyListeners();
      return AppSuccess<StreamRecord>(record);
    } catch (cause) {
      return AppError<StreamRecord>(
        AppFailure(
          'stream_save_failed',
          'Could not save that stream.',
          cause: cause,
        ),
      );
    }
  }

  Future<void> selectStream(StreamRecord record) async {
    if (_selected?.channel == record.channel) return;
    _speechRecurring?.cancel();
    _speechRecurring = null;
    scheduler.cancelScope('speech-capture');
    scheduler.reopenScope('speech-capture');
    await irc.disconnect(userRequested: false);
    _selected = record;
    _chat.clear();
    _chatIds.clear();
    _chatIdOrder.clear();
    _recentChatTimes.clear();
    _companionCards.clear();
    _speechText = '';
    await _loadChatHistory(record.channel);
    agents.configure(
      channel: record.channel,
      settings: _preferences.ai,
      initialMessages: _chat,
    );
    _pulse(navigation: true, chat: true, ai: true);
    notifyListeners();
  }

  Future<void> deleteStream(StreamRecord record) async {
    if (_selected?.id == record.id) {
      await stopPlayback();
      await irc.disconnect(userRequested: true);
      _selected = null;
    }
    _streams.removeWhere((StreamRecord item) => item.id == record.id);
    await vault.delete('saved_stream', record.id);
    if (_selected == null && _streams.isNotEmpty) {
      await selectStream(_streams.first);
    } else if (_selected == null) {
      _chat.clear();
      _chatIds.clear();
      _chatIdOrder.clear();
      _recentChatTimes.clear();
      _companionCards.clear();
      _pulse(chat: true, ai: true);
    }
    _pulse(navigation: true);
    notifyListeners();
  }

  Future<AppResult<void>> startPlayback({
    String? quality,
    PlaybackMode? mode,
    bool preferNative = false,
  }) async {
    final record = _selected;
    if (record == null)
      return const AppError<void>(
        AppFailure('stream_missing', 'Add or select a stream first.'),
      );
    _setBusy(true, 'Resolving Twitch HLS variants…');
    final resolved = await resolver.resolve(record.channel);
    final result = await resolved.fold<Future<AppResult<void>>>(
      success: (ResolvedStream value) async {
        final requestedMode = mode ?? record.playbackMode;
        var requestedQuality = requestedMode == PlaybackMode.audioOnly
            ? 'audio_only'
            : (quality ?? record.quality);
        final originalQuality = requestedQuality;
        final constrainVideo =
            requestedMode == PlaybackMode.video &&
            playback.willUseSoftwareOutput(_preferences.videoAcceleration) &&
            !const <String>{'1', 'true', 'yes'}.contains(
              (Platform.environment['TWITCH_FREEDOM_ALLOW_HIGH_RES_SOFTWARE'] ??
                      '')
                  .toLowerCase(),
            );
        if (constrainVideo) {
          requestedQuality = cpuSafePlaybackQuality(requestedQuality);
        }
        final variant = constrainVideo
            ? selectCpuSafeVariant(value.variants, requestedQuality)
            : selectVariant(value.variants, requestedQuality);
        if (variant == null)
          return const AppError<void>(
            AppFailure(
              'quality_unavailable',
              'No compatible stream variant is available.',
            ),
          );
        if (constrainVideo && variant.qualityLabel != originalQuality) {
          _status =
              'CPU-safe playback: $originalQuality capped at ${variant.qualityLabel}.';
          log.info(_status);
          _pulse(shell: true);
        }
        final played = await playback.play(
          channel: record.channel,
          variant: variant,
          volume: record.volume,
          preferNativeBackend: preferNative,
          lowLatency: _preferences.lowLatency,
          acceleration: _preferences.videoAcceleration,
        );
        if (played is AppSuccess<void>) {
          final updated = record.copyWith(
            playbackMode: requestedMode,
            quality: variant.qualityLabel,
            updatedAt: DateTime.now(),
            lastPlayedAt: DateTime.now(),
            playCount: record.playCount + 1,
          );
          _replaceRecord(updated);
          _pulse(navigation: true);
          await vault.putJson('saved_stream', updated.id, updated.toJson());
          unawaited(connectChat(quiet: true));
          _scheduleSpeechCapture();
          _refreshSchedulerSignals(playbackActive: true);
        }
        return played;
      },
      failure: (AppFailure failure) async => AppError<void>(failure),
    );
    if (result is AppError<void>) {
      _setError(result.error.message);
    } else if (_error.isNotEmpty) {
      clearError();
    }
    _setBusy(false);
    return result;
  }

  Future<void> stopPlayback() async {
    _speechRecurring?.cancel();
    _speechRecurring = null;
    await playback.stop();
    _refreshSchedulerSignals(playbackActive: false);
  }

  Future<AppResult<void>> connectChat({bool quiet = false}) async {
    final record = _selected;
    if (record == null)
      return const AppError<void>(
        AppFailure('stream_missing', 'Select a stream first.'),
      );
    final token = await auth.validAccessToken();
    return token.fold(
      success: (String accessToken) async {
        final state = await auth.tokenState();
        if (state == null || state.login.isEmpty)
          return const AppError<void>(
            AppFailure('identity_missing', 'Re-authorize Twitch in Settings.'),
          );
        final connected = await irc.connect(
          channel: record.channel,
          nick: state.login,
          accessToken: accessToken,
        );
        if (!quiet && connected is AppError<void>)
          _setError(connected.error.message);
        return connected;
      },
      failure: (AppFailure failure) async {
        if (!quiet) _setError(failure.message);
        return AppError<void>(failure);
      },
    );
  }

  Future<void> disconnectChat() => irc.disconnect(userRequested: true);

  Future<AppResult<void>> sendChat(String text) async {
    final validation = validateChatDraft(text);
    if (!validation.valid) {
      return AppError<void>(AppFailure('invalid_message', validation.error));
    }
    final record = _selected;
    if (record == null) {
      return const AppError<void>(
        AppFailure('stream_missing', 'Select a stream first.'),
      );
    }
    if (!_chatConnected || irc.channel != record.channel) {
      return const AppError<void>(
        AppFailure(
          'chat_not_connected',
          'Wait for Twitch to confirm the chat-room connection before sending.',
          retryable: true,
        ),
      );
    }
    final tokenState = await auth.tokenState();
    if (tokenState == null || tokenState.login.isEmpty) {
      return const AppError<void>(
        AppFailure('identity_missing', 'Re-authorize Twitch in Settings.'),
      );
    }

    var broadcasterId = _broadcasterIds[record.channel];
    if (broadcasterId == null) {
      final resolved = await helix.resolveUserId(record.channel);
      if (resolved case AppError<String>(:final error)) {
        return AppError<void>(error);
      }
      broadcasterId = (resolved as AppSuccess<String>).value;
      _broadcasterIds[record.channel] = broadcasterId;
    }

    final sent = await helix.sendChat(broadcasterId, validation.text);
    if (sent case AppError<ChatSendReceipt>(:final error)) {
      return AppError<void>(error);
    }
    final receipt = (sent as AppSuccess<ChatSendReceipt>).value;
    _chatStatus = 'Connected to #${record.channel}';
    _appendChatMessage(
      ChatMessage(
        id: receipt.messageId,
        channel: record.channel,
        user: tokenState.login,
        text: validation.text,
        timestamp: DateTime.now(),
        tags: const <String, String>{'source': 'helix-send-receipt'},
        isOwn: true,
      ),
    );
    return const AppSuccess<void>(null);
  }

  Future<AppResult<List<DiscoveryStream>>> searchDiscovery(String query) async {
    _setBusy(true, 'Searching Twitch text metadata…');
    try {
      final results = query.trim().isEmpty
          ? await helix.followedStreams()
          : await helix.searchChannels(query.trim());
      if (results case AppError<List<DiscoveryStream>>(:final error)) {
        _discovery = <DiscoveryStream>[];
        _setError(error.message);
        return AppError<List<DiscoveryStream>>(error);
      }
      var candidates = _filterDiscovery(
        (results as AppSuccess<List<DiscoveryStream>>).value,
      );

      if (_preferences.ai.enabled && gemma.isReady && candidates.length > 1) {
        final reranked = await agents.rerankDiscovery(
          preference: _preferences.discovery,
          candidates: candidates
              .map(
                (DiscoveryStream item) => <String, Object?>{
                  'id': item.id,
                  'channel': item.channel,
                  'title': item.title,
                  'category': item.category,
                  'language': item.language,
                  'viewer_count': item.viewerCount,
                },
              )
              .toList(growable: false),
        );
        if (reranked is AppSuccess<Map<String, String>> &&
            reranked.value.isNotEmpty) {
          final ranks = reranked.value;
          candidates =
              candidates
                  .map((DiscoveryStream item) {
                    final encoded = ranks[item.id];
                    if (encoded == null) return item;
                    final separator = encoded.indexOf('|');
                    final reason = separator < 0
                        ? ''
                        : encoded.substring(separator + 1);
                    return item.copyWith(reason: reason);
                  })
                  .toList(growable: false)
                ..sort((DiscoveryStream a, DiscoveryStream b) {
                  final left = ranks[a.id]?.split('|').first ?? '999';
                  final right = ranks[b.id]?.split('|').first ?? '999';
                  return left.compareTo(right);
                });
        }
      }
      _discovery = candidates;
      notifyListeners();
      return AppSuccess<List<DiscoveryStream>>(candidates);
    } catch (cause) {
      const message = 'Could not load Twitch discovery right now.';
      final failure = AppFailure(
        'discovery_failed',
        message,
        cause: cause,
        retryable: true,
      );
      _discovery = <DiscoveryStream>[];
      _setError(message);
      return AppError<List<DiscoveryStream>>(failure);
    } finally {
      _setBusy(false);
    }
  }

  List<DiscoveryStream> _filterDiscovery(List<DiscoveryStream> input) {
    final preference = _preferences.discovery;
    final excluded = preference.excludedChannels
        .map((String item) => item.trim().toLowerCase())
        .where((String item) => item.isNotEmpty)
        .toSet();
    final categories = preference.categories
        .map((String item) => item.trim().toLowerCase())
        .where((String item) => item.isNotEmpty)
        .toList(growable: false);
    final languages = preference.languages
        .map((String item) => item.trim().toLowerCase())
        .where((String item) => item.isNotEmpty)
        .toSet();
    final filtered = input
        .where((DiscoveryStream item) {
          if (excluded.contains(item.channel.toLowerCase())) return false;
          return languages.isEmpty ||
              item.language.isEmpty ||
              languages.contains(item.language.toLowerCase());
        })
        .toList(growable: false);

    double score(DiscoveryStream item) {
      var value = 0.0;
      final text = '${item.category} ${item.title}'.toLowerCase();
      if (categories.any(text.contains)) value += 5;
      const technical = <String>[
        'science',
        'technology',
        'programming',
        'software',
        'engineering',
        'space',
        'physics',
        'chemistry',
        'biology',
        'mathematics',
        'maker',
      ];
      if (technical.any(text.contains)) value += 4 * preference.technicalWeight;
      if (!preference.preferLowResource)
        value += (item.viewerCount + 1).bitLength / 10;
      if (_streams.any((StreamRecord saved) => saved.channel == item.channel))
        value += 3;
      return value;
    }

    return filtered..sort(
      (DiscoveryStream a, DiscoveryStream b) => score(b).compareTo(score(a)),
    );
  }

  Future<void> updatePreferences(AppPreferences value) async {
    _preferences = value;
    gemma.configureModelDirectory(value.ai.modelDirectory);
    await vault.putJson('preferences', 'main', value.toJson());
    agents.configure(
      channel: _selected?.channel ?? '',
      settings: value.ai,
      initialMessages: _chat,
    );
    _resetAutoLock();
    _scheduleSpeechCapture();
    _pulse(
      shell: true,
      navigation: true,
      chat: true,
      ai: true,
      preferences: true,
    );
    notifyListeners();
  }

  Future<AppResult<void>> installAndLoadGemma() async {
    _setBusy(true, 'Installing verified local model…');
    final install = await gemma.installModel();
    if (install is AppError<File>) {
      _setError(install.error.message);
      _setBusy(false);
      return AppError<void>(install.error);
    }
    final load = await gemma.load(_preferences.ai.backend);
    if (load is AppError<void>) _setError(load.error.message);
    _setBusy(false);
    return load;
  }

  Future<AppResult<void>> loadGemma() async {
    final result = await gemma.load(_preferences.ai.backend);
    if (result case AppError<void>(error: final failure)) {
      _setError(failure.message);
    }
    return result;
  }

  Future<AppResult<File>> configureGemmaModelDirectory(String path) async {
    _setBusy(true, 'Verifying selected Gemma model…');
    gemma.configureModelDirectory(path);
    final result = await gemma.attestConfiguredModel();
    if (result is AppError<File>) _setError(result.error.message);
    _setBusy(false);
    return result;
  }

  /// Persists first-run model configuration only after the vault has unlocked,
  /// then either attests an existing artifact or downloads the pinned one.
  Future<AppResult<void>> provisionFirstBootGemma({
    required String directory,
    required bool download,
  }) async {
    try {
      final resolvedDirectory = directory.trim().isEmpty
          ? await gemma.resolvedModelDirectoryPath()
          : Directory(directory).absolute.path;
      final ai = _preferences.ai.copyWith(
        enabled: true,
        modelDirectory: resolvedDirectory,
        autoLoadModel: false,
      );
      await updatePreferences(_preferences.copyWith(ai: ai));
      if (download) return installAndLoadGemma();
      final configured = await configureGemmaModelDirectory(resolvedDirectory);
      return configured.fold(
        success: (_) => const AppSuccess<void>(null),
        failure: AppError<void>.new,
      );
    } catch (cause) {
      final failure = AppFailure(
        'first_boot_model_setup_failed',
        'The vault was created, but Gemma setup could not be completed.',
        cause: cause,
        retryable: true,
      );
      _setError(failure.message);
      return AppError<void>(failure);
    }
  }

  Future<AppResult<void>> installMoonshine() async {
    _setBusy(true, 'Installing local Moonshine speech pack…');
    final result = await speech.installMoonshine();
    if (result is AppError<void>) _setError(result.error.message);
    _setBusy(false);
    return result;
  }

  Future<AppResult<TranscriptSegment>> captureSpeechContext({
    bool? retainEncryptedText,
  }) async {
    final record = _selected;
    if (record == null)
      return const AppError<TranscriptSegment>(
        AppFailure('stream_missing', 'Start a stream first.'),
      );
    if (!speech.active) {
      final attached = await speech.attachActiveMoonshine();
      if (attached is AppError<void>) {
        return AppError<TranscriptSegment>(attached.error);
      }
    }
    final result = await speech.capture(
      channel: record.channel,
      retainEncryptedText:
          retainEncryptedText ?? _preferences.ai.retainTranscripts,
    );
    if (result is AppSuccess<TranscriptSegment>) {
      _speechText = result.value.text;
      agents.addSpeechContext(_speechText);
      _pulse(ai: true);
      notifyListeners();
    }
    return result;
  }

  Future<AppResult<AiBatchReport>> runAiBatchNow() async {
    return agents.runBatch(userInitiated: true);
  }

  void _applyAssessments(AiBatchReport report) {
    final byId = <String, MessageAssessment>{
      for (final item in report.assessments) item.messageId: item,
    };
    _chat = _chat
        .map((ChatMessage message) {
          final assessment = byId[message.id];
          if (assessment == null) return message;
          return message.copyWith(
            mood: assessment.mood,
            moodConfidence: assessment.moodConfidence,
            harmConfidence: assessment.harmConfidence,
            harmReason: assessment.harmReason,
            softenedText: assessment.softenedText,
          );
        })
        .toList(growable: false);
    _pulse(chat: true);
    notifyListeners();
  }

  Future<void> _loadChatHistory(String channel) async {
    final all = await vault.getAllJson('chat_message');
    _chat = all
        .map(ChatMessage.fromJson)
        .where((ChatMessage item) => item.channel == channel)
        .take(300)
        .toList()
        .reversed
        .toList();
    _chatIds.clear();
    _chatIdOrder.clear();
    for (final message in _chat) {
      if (_chatIds.add(message.id)) _chatIdOrder.addLast(message.id);
    }
  }

  Future<void> _handleChatEvent(ChatEvent event) async {
    if (_disposed) return;
    switch (event) {
      case ChatConnecting(:final channel):
        _chatConnected = false;
        _chatStatus = 'Joining #$channel…';
      case ChatConnected(:final channel):
        _chatConnected = true;
        _chatStatus = 'Connected to #$channel';
      case ChatReconnecting(:final delay, :final reason):
        _chatConnected = false;
        _chatStatus = '$reason Reconnecting in ${delay.inSeconds}s.';
      case ChatDisconnected(:final userRequested):
        _chatConnected = false;
        _chatStatus = userRequested ? 'Disconnected' : 'Connection ended';
      case ChatNotice(:final message):
        _chatStatus = message;
      case ChatMessageReceived(:final message):
        if (message.channel != _selected?.channel) return;
        _appendChatMessage(message);
        return;
    }
    _pulse(shell: true, chat: true);
  }

  bool _appendChatMessage(ChatMessage message) {
    if (!_chatIds.add(message.id)) return false;
    _chatIdOrder.addLast(message.id);
    _chat.add(message);
    if (_chat.length > 1050) {
      final removeCount = _chat.length - 1000;
      _chat.removeRange(0, removeCount);
      for (var index = 0; index < removeCount; index++) {
        if (_chatIdOrder.isNotEmpty) {
          _chatIds.remove(_chatIdOrder.removeFirst());
        }
      }
    }
    _recordChatVelocity(message.timestamp);
    agents.addMessage(message);
    _scheduleChatVelocitySignal();
    _pulse(chat: true);
    _queueChatPersistence(message);
    return true;
  }

  void _handleCompanionCard(CompanionCard card) {
    if (_disposed) return;
    _companionCards.insert(0, card);
    if (_companionCards.length > 60)
      _companionCards.removeRange(60, _companionCards.length);
    _pulse(ai: true);
  }

  void _queueChatPersistence(ChatMessage message) {
    _pendingChatPersistence[message.id] = message;
    _chatPersistTimer ??= Timer(const Duration(milliseconds: 650), () {
      _chatPersistTimer = null;
      unawaited(_flushPendingChatPersistence());
    });
  }

  void _recordChatVelocity(DateTime timestamp) {
    _recentChatTimes.addLast(timestamp);
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    while (_recentChatTimes.isNotEmpty &&
        _recentChatTimes.first.isBefore(cutoff)) {
      _recentChatTimes.removeFirst();
    }
  }

  void _scheduleChatVelocitySignal() {
    _chatSignalTimer ??= Timer(const Duration(seconds: 1), () {
      _chatSignalTimer = null;
      _refreshSchedulerSignals(chatMessagesPerMinute: _recentChatVelocity());
    });
  }

  Future<void> _flushPendingChatPersistence() async {
    _chatPersistTimer?.cancel();
    _chatPersistTimer = null;
    if (_pendingChatPersistence.isEmpty) {
      await _chatPersistenceQueue;
      return;
    }
    final pending = Map<String, ChatMessage>.of(_pendingChatPersistence);
    _pendingChatPersistence.clear();
    _chatPersistenceQueue = _chatPersistenceQueue.then((_) async {
      if (!vault.isUnlocked || pending.isEmpty) return;
      try {
        await vault.putJsonBatch('chat_message', <String, Map<String, Object?>>{
          for (final entry in pending.entries) entry.key: entry.value.toJson(),
        });
      } catch (cause) {
        log.warning('Encrypted chat batch persistence skipped: $cause');
      }
    });
    await _chatPersistenceQueue;
  }

  void _replaceRecord(StreamRecord updated) {
    final index = _streams.indexWhere(
      (StreamRecord item) => item.id == updated.id,
    );
    if (index >= 0) _streams[index] = updated;
    _selected = updated;
  }

  String? _channelFromInput(String input) {
    final clean = input.trim().toLowerCase();
    if (RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(clean)) return clean;
    final uri = Uri.tryParse(clean);
    if (uri == null ||
        uri.scheme != 'https' ||
        !<String>{
          'twitch.tv',
          'www.twitch.tv',
        }.contains(uri.host.toLowerCase()))
      return null;
    final segment = uri.pathSegments
        .where((String item) => item.isNotEmpty)
        .firstOrNull;
    return segment != null && RegExp(r'^[a-z0-9_]{3,25}$').hasMatch(segment)
        ? segment
        : null;
  }

  void userActivity() => _resetAutoLock();

  void _scheduleSpeechCapture() {
    _speechRecurring?.cancel();
    _speechRecurring = null;
    final ai = _preferences.ai;
    final channel = _selected?.channel ?? '';
    if (!_unlocked ||
        !ai.enabled ||
        !(ai.speechContext || ai.closedCaptions) ||
        !playback.playing ||
        channel.isEmpty)
      return;
    _speechRecurring = scheduler.scheduleAdaptiveRecurring(
      key: 'speech-window:$channel',
      scope: 'speech-capture',
      lane: PulseLane.maintenance,
      affinity: 'audio:$channel',
      priority: 32,
      cost: 22,
      requiresVault: true,
      pauseDuringPlayback: false,
      cadence: (PulseSignals signals) {
        // Moonshine consumes fixed five-second windows. Queue the next window
        // at the same cadence so caption mode does not intentionally leave a
        // three-second hole between chunks. Single-flight scheduling and the
        // speech.busy guard prevent overlapping recognizer calls.
        if (ai.closedCaptions) return AppConfig.moonshineWindow;
        final minutes = signals.chatMessagesPerMinute >= 25
            ? 6
            : signals.chatMessagesPerMinute >= 5
            ? 8
            : 10;
        return Duration(minutes: minutes);
      },
      enabledWhen: (_) => playback.playing && !speech.busy,
      action: (_) async {
        final result = await captureSpeechContext(
          retainEncryptedText: ai.retainTranscripts,
        );
        if (result is AppError<TranscriptSegment>) {
          log.warning('Scheduled speech context skipped: ${result.error.code}');
        }
      },
    );
  }

  int _recentChatVelocity() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    while (_recentChatTimes.isNotEmpty &&
        _recentChatTimes.first.isBefore(cutoff)) {
      _recentChatTimes.removeFirst();
    }
    return _recentChatTimes.length;
  }

  void _refreshSchedulerSignals({
    bool? playbackActive,
    bool? modelReady,
    int? chatMessagesPerMinute,
  }) {
    scheduler.updateSignals(
      scheduler.signals.copyWith(
        vaultUnlocked: _unlocked,
        playbackActive: playbackActive ?? playback.playing,
        modelReady: modelReady ?? gemma.isReady,
        chatMessagesPerMinute: chatMessagesPerMinute ?? _recentChatVelocity(),
        resourcePressure: gemma.current.busy || speech.busy
            ? 0.72
            : playback.buffering
            ? 0.5
            : 0.12,
      ),
    );
  }

  void _resetAutoLock() {
    _autoLock?.cancel();
    if (!_unlocked || _preferences.autoLockMinutes <= 0) return;
    _autoLock = Timer(Duration(minutes: _preferences.autoLockMinutes), lock);
  }

  Future<void> lock() async {
    _xRefreshTimer?.cancel();
    _xRefreshTimer = null;
    _speechRecurring?.cancel();
    _speechRecurring = null;
    scheduler.cancelScope('speech-capture');
    scheduler.cancelScope('agent-batch');
    scheduler.cancelScope('model-autoload');
    await _flushPendingChatPersistence();
    await playback.stop();
    await irc.disconnect(userRequested: true);
    await gemma.unload();
    await speech.deactivate();
    await vault.close();
    _unlocked = false;
    _selected = null;
    _streams = <StreamRecord>[];
    _discovery = <DiscoveryStream>[];
    _chat = <ChatMessage>[];
    _chatIds.clear();
    _chatIdOrder.clear();
    _broadcasterIds.clear();
    _companionCards = <CompanionCard>[];
    _xPosts = <XPost>[];
    _xStoredMedia = <XStoredMedia>[];
    _xFollows = <XFollow>[];
    _xContentScores.clear();
    _xContentScanning = false;
    _xContentScanCancelled = true;
    _xBearerToken = '';
    _xHandle = '';
    _xClientId = '';
    _xClientSecret = '';
    _xUserAccessToken = '';
    _xRefreshToken = '';
    _xUserTokenExpiresAt = null;
    _xAutoRefresh = false;
    _xContentSource = XContentSource.account;
    _recentChatTimes.clear();
    _pendingChatPersistence.clear();
    _speechText = '';
    _chatConnected = false;
    _chatStatus = 'Disconnected';
    _preferences = const AppPreferences();
    gemma.configureModelDirectory('');
    _status = 'Vault locked.';
    _vaultStatus = await vault.status();
    _refreshSchedulerSignals(playbackActive: false, modelReady: false);
    _pulse(
      shell: true,
      navigation: true,
      chat: true,
      ai: true,
      preferences: true,
    );
    notifyListeners();
  }

  void clearError() {
    _error = '';
    _pulse(shell: true);
    notifyListeners();
  }

  void _setBusy(bool value, [String? status]) {
    _busy = value;
    if (status != null) _status = status;
    _pulse(shell: true);
    notifyListeners();
  }

  void _setError(String value) {
    _error = value;
    _pulse(shell: true);
    notifyListeners();
  }

  void _relay() {
    if (_disposed) return;
    final active = playback.playing;
    final buffering = playback.buffering;
    if (_relayedPlaybackActive == active &&
        _relayedPlaybackBuffering == buffering) {
      return;
    }
    _relayedPlaybackActive = active;
    _relayedPlaybackBuffering = buffering;
    _refreshSchedulerSignals(playbackActive: active);
  }

  void _pulse({
    bool shell = false,
    bool navigation = false,
    bool chat = false,
    bool ai = false,
    bool preferences = false,
    bool x = false,
  }) {
    if (_disposed) return;
    if (shell) shellRevision.value += 1;
    if (navigation) navigationRevision.value += 1;
    if (chat) chatRevision.value += 1;
    if (ai) aiRevision.value += 1;
    if (preferences) preferencesRevision.value += 1;
    if (x) xRevision.value += 1;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Future<void> _shutdownServices() async {
    await _flushPendingChatPersistence();
    await playback.stop();
    await irc.dispose();
    await agents.close();
    await gemma.close();
    await speech.close();
    await vault.close();
    await scheduler.close();
    playback.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _autoLock?.cancel();
    _speechRecurring?.cancel();
    _chatPersistTimer?.cancel();
    _chatSignalTimer?.cancel();
    _xRefreshTimer?.cancel();
    playback.removeListener(_relay);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    auth.dispose();
    helix.dispose();
    resolver.dispose();
    unawaited(_shutdownServices());
    shellRevision.dispose();
    navigationRevision.dispose();
    chatRevision.dispose();
    aiRevision.dispose();
    preferencesRevision.dispose();
    xRevision.dispose();
    schedulerTelemetry.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
