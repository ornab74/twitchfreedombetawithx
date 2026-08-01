# Local mpv hot-restart safety patch

Upstream package: `media_kit 1.2.6` (MIT).

In debug mode, media_kit preserves mpv handles across a Flutter hot restart so
the new isolate can terminate handles left by the old isolate. The old handle's
wakeup hook points to a Dart `NativeCallable` owned by the old isolate. Sending
the `quit` command before detaching that hook can make mpv invoke a callback
after Dart has deleted it, aborting the Linux process with:

`Callback invoked after it has been deleted.`

The recovery loop now calls `mpv_set_wakeup_callback(ctx, nullptr, nullptr)`
before sending `quit`. This mirrors normal player disposal and changes only the
debug hot-restart cleanup path.

Remove the override only after an upstream release provides equivalent callback
detachment and passes hot restart during active Linux software-video playback.
