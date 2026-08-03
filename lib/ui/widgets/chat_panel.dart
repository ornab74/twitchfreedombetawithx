import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../chat/irc_client.dart';
import '../../core/models.dart';
import '../../core/result.dart';
import '../../state/app_controller.dart';
import '../theme.dart';
import 'glass_panel.dart';

final DateFormat _chatClock = DateFormat.Hm();

final class ChatComposeRequest {
  const ChatComposeRequest(this.sequence, this.text);

  final int sequence;
  final String text;
}

final class ChatPanel extends StatefulWidget {
  const ChatPanel({super.key, required this.controller, this.composeRequests});
  final AppController controller;
  final ValueListenable<ChatComposeRequest>? composeRequests;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

final class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _entry = TextEditingController();
  final FocusNode _entryFocus = FocusNode(debugLabel: 'Twitch chat composer');
  final ScrollController _scroll = ScrollController();
  final Set<String> _revealed = <String>{};
  bool _sending = false;
  bool _scrollScheduled = false;
  bool _draftTouched = false;
  bool _composerFocused = false;
  late int _messageCount;
  late ChatDraftValidation _draft;

  @override
  void initState() {
    super.initState();
    _messageCount = widget.controller.chat.length;
    _draft = validateChatDraft('');
    _entry.addListener(_handleDraftChanged);
    _entryFocus.addListener(_handleComposerFocus);
    widget.composeRequests?.addListener(_handleComposeRequest);
    widget.controller.chatRevision.addListener(_handleChatUpdate);
  }

  void _handleComposerFocus() {
    if (!mounted || _composerFocused == _entryFocus.hasFocus) return;
    setState(() => _composerFocused = _entryFocus.hasFocus);
  }

  void _handleComposeRequest() {
    final request = widget.composeRequests?.value;
    if (request == null) return;
    _entryFocus.requestFocus();
    if (request.text.isEmpty) return;
    final selection = _entry.selection;
    final start = selection.isValid ? selection.start : _entry.text.length;
    final end = selection.isValid ? selection.end : _entry.text.length;
    final next = _entry.text.replaceRange(start, end, request.text);
    _entry.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + request.text.length),
    );
  }

  void _handleDraftChanged() {
    final next = validateChatDraft(_entry.text);
    if (next.text == _draft.text &&
        next.characterCount == _draft.characterCount &&
        next.error == _draft.error) {
      return;
    }
    _draft = next;
    _draftTouched = _entry.text.isNotEmpty;
    if (mounted) setState(() {});
  }

  void _handleChatUpdate() {
    final nextCount = widget.controller.chat.length;
    final wasNearBottom =
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.position.pixels < 140;
    final shouldScroll = nextCount > _messageCount && wasNearBottom;
    _messageCount = nextCount;
    if (mounted) setState(() {});
    if (!shouldScroll || _scrollScheduled) return;
    _scrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollScheduled = false;
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.composeRequests != widget.composeRequests) {
      oldWidget.composeRequests?.removeListener(_handleComposeRequest);
      widget.composeRequests?.addListener(_handleComposeRequest);
    }
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.chatRevision.removeListener(_handleChatUpdate);
    widget.controller.chatRevision.addListener(_handleChatUpdate);
    _messageCount = widget.controller.chat.length;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final messages = controller.chat;
    final tokens = freedomTokens(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _composerFocused ? tokens.glow : Colors.transparent,
          width: 2,
        ),
      ),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.forum_rounded, size: 20),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Chat',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: controller.chatConnected
                          ? tokens.good
                          : Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      controller.chatStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
            const NeonDivider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: controller.chatConnected
                        ? null
                        : controller.connectChat,
                    icon: const Icon(Icons.link_rounded, size: 18),
                    label: const Text('Connect'),
                  ),
                  const SizedBox(width: 7),
                  IconButton.filledTonal(
                    tooltip: 'Disconnect chat',
                    onPressed: controller.chatConnected
                        ? controller.disconnectChat
                        : null,
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: 'Open official Twitch chat popout',
                    onPressed: controller.selected == null
                        ? null
                        : () => launchUrl(
                            Uri.https(
                              'www.twitch.tv',
                              '/popout/${controller.selected!.channel}/chat',
                              <String, String>{'popout': ''},
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              controller.chatConnected
                                  ? Icons.mark_chat_unread_outlined
                                  : Icons.forum_outlined,
                              color: controller.chatConnected
                                  ? tokens.good
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              controller.selected == null
                                  ? 'Select a channel to prepare chat.'
                                  : controller.chatConnected
                                  ? 'Connected to #${controller.selected!.channel}.\nWaiting for live messages…'
                                  : controller.chatStatus.startsWith('Joining')
                                  ? controller.chatStatus
                                  : 'Authorize Twitch in Control Center, then connect.\nNo synthetic messages or demo chat are inserted.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: RepaintBoundary(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          itemCount: messages.length,
                          itemBuilder: (BuildContext context, int index) {
                            final message = messages[index];
                            return RepaintBoundary(
                              child: _ChatMessageCard(
                                message: message,
                                protectiveMode:
                                    controller.preferences.ai.protectiveMode,
                                moodEnabled:
                                    controller.preferences.ai.moodColoring,
                                revealed: _revealed.contains(message.id),
                                onReveal: () =>
                                    setState(() => _revealed.add(message.id)),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _entry,
                          focusNode: _entryFocus,
                          maxLines: 3,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          decoration: InputDecoration(
                            hintText: controller.chatConnected
                                ? 'Send a chat message…'
                                : 'Write a message — connect to send…',
                            errorText: _draftTouched && !_draft.valid
                                ? _draft.error
                                : null,
                          ),
                          onSubmitted: (_) {
                            if (_canSend(controller)) _send();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: controller.chatConnected
                            ? 'Send through Twitch'
                            : 'Connect to Twitch chat first',
                        onPressed: _canSend(controller) ? _send : null,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 5),
                    child: Text(
                      '${_draft.characterCount}/500',
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _draft.characterCount > 500
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canSend(AppController controller) =>
      !_sending && controller.chatConnected && _draft.valid;

  Future<void> _send() async {
    final validation = validateChatDraft(_entry.text);
    if (!validation.valid || _sending || !widget.controller.chatConnected) {
      _draftTouched = true;
      if (mounted) setState(() {});
      return;
    }
    setState(() => _sending = true);
    final result = await widget.controller.sendChat(validation.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (result is AppSuccess<void>) {
      _entry.clear();
    } else if (result is AppError<void>) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.error.message)));
    }
  }

  @override
  void dispose() {
    widget.controller.chatRevision.removeListener(_handleChatUpdate);
    widget.composeRequests?.removeListener(_handleComposeRequest);
    _entry.removeListener(_handleDraftChanged);
    _entryFocus.removeListener(_handleComposerFocus);
    _entryFocus.dispose();
    _entry.dispose();
    _scroll.dispose();
    super.dispose();
  }
}

final class _ChatMessageCard extends StatelessWidget {
  const _ChatMessageCard({
    required this.message,
    required this.protectiveMode,
    required this.moodEnabled,
    required this.revealed,
    required this.onReveal,
  });
  final ChatMessage message;
  final ProtectiveMode protectiveMode;
  final bool moodEnabled;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final harmful = message.potentiallyHarmful;
    final shouldMirror =
        harmful &&
        protectiveMode == ProtectiveMode.mirror &&
        message.softenedText?.isNotEmpty == true &&
        !revealed;
    final shouldHide =
        harmful &&
        protectiveMode == ProtectiveMode.hideHighConfidence &&
        !revealed;
    final shouldBlur =
        harmful && protectiveMode == ProtectiveMode.blur && !revealed;
    final shouldDim =
        harmful && protectiveMode == ProtectiveMode.dim && !revealed;
    final usernameColor = moodEnabled
        ? moodColor(message.mood, Theme.of(context).colorScheme)
        : Theme.of(context).colorScheme.primary;
    final body = Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: harmful
            ? Theme.of(
                context,
              ).colorScheme.errorContainer.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: harmful
            ? Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.error.withValues(alpha: 0.32),
              )
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                _chatClock.format(message.timestamp),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  message.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: usernameColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (message.isModerator)
                const Icon(Icons.shield_outlined, size: 14),
              if (harmful) ...<Widget>[
                const SizedBox(width: 5),
                Icon(
                  Icons.warning_amber_rounded,
                  color: Theme.of(context).colorScheme.error,
                  size: 15,
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          if (shouldMirror) ...<Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.auto_awesome_rounded, size: 15),
                const SizedBox(width: 6),
                Text(
                  'Protective Mirror',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(message.softenedText!),
            TextButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('Reveal original'),
            ),
          ] else if (shouldHide) ...<Widget>[
            Text(
              'A high-confidence harmful message is hidden.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            TextButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('Show original'),
            ),
          ] else if (shouldBlur)
            Text(
              'Message blurred by your protective setting.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            )
          else if (shouldDim)
            Text(
              message.text,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: .35),
              ),
            )
          else
            Text(message.text),
          if (shouldBlur)
            TextButton.icon(
              onPressed: onReveal,
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: const Text('Reveal message'),
            ),
          if (harmful &&
              message.harmReason.isNotEmpty &&
              (revealed || protectiveMode == ProtectiveMode.raw))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'AI caution (${(message.harmConfidence * 100).round()}%): ${message.harmReason}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
    return Semantics(label: 'Chat message from ${message.user}', child: body);
  }
}
