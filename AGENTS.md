# Twitch Freedom Codex guidance

## Dart and Flutter MCP

- The shared Codex configuration registers the `dart` MCP server from the
  Flutter SDK. Use its tools for analysis, tests, app logs, widget inspection,
  and debug UI automation.
- For automated Linux UI checks, call `launch_app` with device `linux` and add
  `--dart-define=ENABLE_FLUTTER_DRIVER=true` to its `args` array.
- After `launch_app`, call `dtd` with command `connect` and the returned
  `dtdUri` before using `widget_inspector` or `flutter_driver_command`.
- Read the real widget tree before selecting a widget. Do not guess tap or text
  finders.
- The Flutter Driver extension is test-only. Never enable it in profile or
  release runs.
- Use `/home/user/naza/venv/bin/python` directly for auxiliary Python
  diagnostics. The Dart MCP server itself does not depend on Python.
- Chat automation must use a user-approved test account and room. Confirm
  connection readiness, outbound receipt/local echo, and inbound delivery; do
  not send a message to a live room without explicit approval.
