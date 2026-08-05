import 'package:flutter/material.dart';

import '../core/app_config.dart';
import 'theme.dart';
import 'widgets/glass_panel.dart';

Future<void> showTutorialSheet(
  BuildContext context,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const TutorialSheet(),
);

final class TutorialSheet extends StatelessWidget {
  const TutorialSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = freedomTokens(context);
    return FractionallySizedBox(
      heightFactor: .96,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        child: Material(
          color: colors.canvas,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 15, 14, 13),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.menu_book_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Setup guide', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
                  ],
                ),
              ),
              const NeonDivider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
                  children: <Widget>[
                    Text('Connect your accounts safely', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    Text('This walkthrough explains which tokens belong where. Twitch Freedom stores credentials in the encrypted vault and never asks for your Twitch password.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45)),
                    const SizedBox(height: 18),
                    _TutorialCard(number: '01', icon: Icons.lock_rounded, title: 'Create the encrypted boot vault', body: 'On the startup screen, create a strong 12+ character boot password. This unlocks the local vault; it is not your Twitch or X password.', screenshot: const _MockScreen(title: 'Create encrypted workspace', lines: <String>['Create boot password', 'Confirm password'], button: 'Create encrypted vault')),
                    _TutorialCard(number: '02', icon: Icons.app_registration_rounded, title: 'Create a Twitch Developer application', body: 'Open the Twitch Developer Console → Applications → Register Your Application. Use any name, choose a category, and add the redirect URL shown in Control Center. Copy the Client ID and Client Secret into the Twitch section—never share the secret.', screenshot: const _MockScreen(title: 'Twitch login', lines: <String>['Twitch Client ID', 'Twitch Client Secret', 'Device authorization'], button: 'Authorize Twitch')),
                    _TutorialCard(number: '03', icon: Icons.chat_bubble_rounded, title: 'Authorize the Twitch bot/chat account', body: 'In Control Center, save the app credentials, choose Authorize Twitch, then enter the official device code at twitch.tv/activate. Approve chat:read and chat:edit only when you want to read or send messages. The app never posts autonomously.', screenshot: const _MockScreen(title: 'Twitch authorization', lines: <String>['Device code: ABCD-EFGH', 'Waiting for approval…'], button: 'Open activation page')),
                    _TutorialCard(number: '04', icon: Icons.alternate_email_rounded, title: 'Add X tokens (optional)', body: 'Create an X developer project/app, then copy its Bearer Token into the X API field in Control Center. Use a read-only token unless you explicitly need publishing. Treat bearer tokens like passwords: do not paste them into chat, screenshots, issues, or logs.', screenshot: const _MockScreen(title: 'X mode', lines: <String>['Bearer token', 'Read-only access'], button: 'Save encrypted token')),
                    _TutorialCard(number: '05', icon: Icons.live_tv_rounded, title: 'Add a channel and test', body: 'Unlock the vault, press +, enter a channel name, and press Play. Open Chat and send a short test only after confirming the account and room. A local echo confirms your client; wait for inbound delivery before troubleshooting.', screenshot: const _MockScreen(title: 'Twitch workspace', lines: <String>['Channel name', 'Quality: 720p', 'Chat: authorized'], button: 'Play stream')),
                    GlassPanel(radius: 18, padding: const EdgeInsets.all(16), child: Row(children: <Widget>[Icon(Icons.shield_rounded, color: colors.good), const SizedBox(width: 12), Expanded(child: Text('Tokens stay encrypted at rest. Lock the app when you are done, and revoke tokens from Twitch/X if you ever suspect exposure.', style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4)))])),
                    const SizedBox(height: 12),
                    Text('Twitch Freedom ${AppConfig.appVersion}', textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.number, required this.icon, required this.title, required this.body, required this.screenshot});
  final String number;
  final IconData icon;
  final String title;
  final String body;
  final Widget screenshot;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: GlassPanel(radius: 20, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[CircleAvatar(radius: 16, child: Text(number, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))), const SizedBox(width: 10), Icon(icon), const SizedBox(width: 8), Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 12),
      Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
      const SizedBox(height: 14),
      screenshot,
    ])),
  );
}

final class _MockScreen extends StatelessWidget {
  const _MockScreen({required this.title, required this.lines, required this.button});
  final String title;
  final List<String> lines;
  final String button;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface.withValues(alpha: .72), borderRadius: BorderRadius.circular(14), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Row(children: <Widget>[const Icon(Icons.circle, size: 8, color: Colors.redAccent), const SizedBox(width: 5), const Icon(Icons.circle, size: 8, color: Colors.amber), const SizedBox(width: 5), const Icon(Icons.circle, size: 8, color: Colors.greenAccent), const Spacer(), Text('Twitch Freedom', style: Theme.of(context).textTheme.labelSmall)]),
      const SizedBox(height: 10),
      Text(title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ...lines.map((line) => Padding(padding: const EdgeInsets.only(bottom: 5), child: InputDecorator(decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()), child: Text(line, style: Theme.of(context).textTheme.bodySmall)))),
      Align(alignment: Alignment.centerRight, child: FilledButton.tonal(onPressed: null, child: Text(button))),
    ]),
  );
}
