import 'package:flutter/material.dart';

import '../core/result.dart';
import '../state/app_controller.dart';

Future<void> showAddStreamDialog(
  BuildContext context,
  AppController controller,
) async {
  var entry = '';
  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Row(
        children: <Widget>[
          Icon(Icons.add_to_queue_rounded),
          SizedBox(width: 10),
          Text('Add Twitch stream'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Enter a channel login or an HTTPS twitch.tv URL. Only text metadata is stored; no thumbnails or avatars are requested.',
            ),
            const SizedBox(height: 16),
            TextField(
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (String value) => entry = value,
              onSubmitted: (String value) => Navigator.pop(context, value),
              decoration: const InputDecoration(
                labelText: 'Channel or URL',
                hintText: 'channel_name or https://www.twitch.tv/channel_name',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, entry),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add'),
        ),
      ],
    ),
  );
  if (result == null || result.trim().isEmpty || !context.mounted) return;
  final saved = await controller.addStream(result);
  if (!context.mounted) return;
  switch (saved) {
    case AppSuccess():
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream added to the encrypted drawer.')),
      );
    case AppError(:final error):
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
