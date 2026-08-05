import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_config.dart';
import '../state/app_controller.dart';
import 'theme.dart';
import 'tutorial_screen.dart';
import 'widgets/glass_panel.dart';

Future<void> showHelpSheet(BuildContext context, AppController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HelpSheet(controller: controller),
  );
}

final class HelpSheet extends StatelessWidget {
  const HelpSheet({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = freedomTokens(context);
    return FractionallySizedBox(
      heightFactor: .92,
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
                    const Icon(Icons.help_center_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Help, privacy, and installation',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 32),
                  children: <Widget>[
                    const _HelpHero(),
                    const SizedBox(height: 14),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_rounded),
                        title: const Text('Account & token setup tutorial'),
                        subtitle: const Text('Twitch app, chat bot authorization, X bearer token, and first stream.'),
                        trailing: const Icon(Icons.arrow_forward_rounded),
                        onTap: () => showTutorialSheet(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _HelpSection(
                      icon: Icons.rocket_launch_rounded,
                      title: 'Quick start',
                      children: const <Widget>[
                        _Step(
                          number: 1,
                          title: 'Unlock the vault',
                          body:
                              'Create a strong boot password. Twitch credentials, settings, chat history, and AI memory are encrypted only after unlock.',
                        ),
                        _Step(
                          number: 2,
                          title: 'Add a text-only channel',
                          body:
                              'Press + and enter a channel name or HTTPS Twitch URL. No preview image, avatar, emote, or remote font is loaded.',
                        ),
                        _Step(
                          number: 3,
                          title: 'Choose playback',
                          body:
                              'Select video or audio-only, choose a quality, and press Play. The Dart resolver requests Twitch HLS variants and keeps tokens out of logs.',
                        ),
                        _Step(
                          number: 4,
                          title: 'Authorize chat',
                          body:
                              'Open Control Center, save your Twitch Developer app credentials, and complete the official device-code flow.',
                        ),
                        _Step(
                          number: 5,
                          title: 'Enable local AI explicitly',
                          body:
                              'Every Gemma agent is opt-in. Protective Mirror always labels generated text and keeps the original revealable.',
                        ),
                      ],
                    ),
                    _HelpSection(
                      icon: Icons.computer_rounded,
                      title: 'Current platform',
                      children: <Widget>[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.devices_rounded),
                          title: Text(_platformName()),
                          subtitle: Text(_platformInstructions()),
                        ),
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.movie_filter_rounded),
                          title: Text('Playback backends'),
                          subtitle: Text(
                            'Native video_player where supported, Media Kit cross-platform fallback, and FFmpeg Kit for diagnostics, compatibility processing, and ephemeral speech audio extraction.',
                          ),
                        ),
                      ],
                    ),
                    _HelpSection(
                      icon: Icons.install_desktop_rounded,
                      title: 'Build and install',
                      children: const <Widget>[
                        _Command(
                          label: 'Bootstrap platform folders',
                          command:
                              'flutter create --platforms=android,ios,linux,macos,windows .',
                        ),
                        _Command(
                          label: 'Resolve packages',
                          command: 'flutter pub get',
                        ),
                        _Command(
                          label: 'Validate',
                          command: 'flutter analyze && flutter test',
                        ),
                        _Command(
                          label: 'Windows',
                          command: 'flutter build windows --release',
                        ),
                        _Command(
                          label: 'macOS',
                          command: 'flutter build macos --release',
                        ),
                        _Command(
                          label: 'Linux',
                          command: 'flutter build linux --release',
                        ),
                        _Command(
                          label: 'Android',
                          command:
                              'flutter build apk --release --target-platform android-arm64',
                        ),
                      ],
                    ),
                    _HelpSection(
                      icon: Icons.health_and_safety_rounded,
                      title: 'Protective Mirror',
                      children: const <Widget>[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.auto_fix_high_rounded),
                          title: Text('Never impersonates the sender'),
                          subtitle: Text(
                            'A softened line is visibly marked as AI-generated. Reveal Original remains available unless the user explicitly hides it.',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.fact_check_rounded),
                          title: Text('Uncertain by design'),
                          subtitle: Text(
                            'The safety agent reports “potentially harmful pattern” with confidence rather than declaring intent or making permanent accusations.',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.send_rounded),
                          title: Text('No autonomous posting'),
                          subtitle: Text(
                            'Jokes, calming drafts, and technical notes are private suggestions. Only the user can send a Twitch chat message.',
                          ),
                        ),
                      ],
                    ),
                    _HelpSection(
                      icon: Icons.security_rounded,
                      title: 'Security boundaries',
                      children: const <Widget>[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.vpn_key_rounded),
                          title: Text('Password hierarchy'),
                          subtitle: Text(
                            'Argon2id derives a key-encryption key, which unwraps a random vault key and versioned data keys. Records use AES-256-GCM with authenticated metadata.',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.verified_rounded),
                          title: Text('Verified model installation'),
                          subtitle: Text(
                            'The Gemma artifact is downloaded to a temporary path, incrementally hashed, and atomically promoted only when the pinned SHA-256 matches.',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.mic_off_rounded),
                          title: Text('Ephemeral speech capture'),
                          subtitle: Text(
                            'Raw audio is captured locally for a short window, transcribed on-device, and removed. Transcript retention is independently controlled.',
                          ),
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.visibility_off_rounded),
                          title: Text('Redacted diagnostics'),
                          subtitle: Text(
                            'OAuth tokens, playback signatures, client secrets, and raw prompts are excluded or redacted from logs.',
                          ),
                        ),
                      ],
                    ),
                    _HelpSection(
                      icon: Icons.link_rounded,
                      title: 'Project resources',
                      children: <Widget>[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            OutlinedButton.icon(
                              onPressed: () => _open(
                                Uri.parse(
                                  'https://github.com/ornab74/twitchfreedom',
                                ),
                              ),
                              icon: const Icon(Icons.code_rounded),
                              label: const Text('Original project'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _open(
                                Uri.parse('https://dev.twitch.tv/console/apps'),
                              ),
                              icon: const Icon(Icons.app_registration_rounded),
                              label: const Text('Twitch Developer Console'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _open(
                                Uri.parse(
                                  'https://github.com/streamlink/streamlink',
                                ),
                              ),
                              icon: const Icon(Icons.account_tree_rounded),
                              label: const Text('Streamlink attribution'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      'Resolver profile ${AppConfig.resolverProfileVersion} • App ${AppConfig.appVersion}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(Uri uri) async =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static String _platformName() {
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }

  static String _platformInstructions() {
    if (Platform.isWindows)
      return 'Windows uses Media Kit/FFmpeg compatibility playback. GitHub Actions produces a signed-ready x64 bundle and checksums.';
    if (Platform.isMacOS)
      return 'macOS uses AVPlayer through video_player when compatible and can fall back to Media Kit. Notarization secrets belong only in protected release jobs.';
    if (Platform.isLinux)
      return 'Linux uses Media Kit and a system-FFmpeg adapter for speech extraction. Install FFmpeg from your distribution package manager.';
    if (Platform.isAndroid)
      return 'Android uses ExoPlayer through video_player, FFmpeg Kit for local audio extraction, and arm64 LiteRT-LM for Gemma.';
    if (Platform.isIOS)
      return 'iOS uses AVPlayer, FFmpeg Kit, and the local LiteRT-LM runtime. Microphone permission is not needed because speech context comes from playback audio processing.';
    return 'Consult docs/build-all-platforms.md for capability gates.';
  }
}

final class _HelpHero extends StatelessWidget {
  const _HelpHero();
  @override
  Widget build(BuildContext context) => GlassPanel(
    radius: 24,
    padding: const EdgeInsets.all(20),
    child: Row(
      children: <Widget>[
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Icon(
            Icons.shield_moon_rounded,
            size: 31,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'A browser-light Twitch workspace',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 5),
              const Text(
                'Text-first discovery, local playback, encrypted state, and optional on-device AI—with no ads SDK, cloud assistant, remote thumbnails, or autonomous bot posting.',
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
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
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

final class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});
  final int number;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CircleAvatar(radius: 16, child: Text('$number')),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

final class _Command extends StatelessWidget {
  const _Command({required this.label, required this.command});
  final String label;
  final String command;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              child: SelectableText(
                command,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
