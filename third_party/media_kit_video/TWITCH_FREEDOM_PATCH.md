# Local Linux software-video performance patch

Upstream package: `media_kit_video 2.0.1` (MIT).

Twitch Freedom uses this path dependency to keep CPU-rendered video responsive
under Crostini. The upstream mpv update callback schedules a GTK idle source for
every decoded frame. Under a slow llvmpipe compositor, multiple stale callbacks
can accumulate and delay pointer, keyboard, and Flutter paint work.

`software_frame_pending` coalesces that work to one queued or rendering
callback. Notifications received during conversion are dropped so GTK resize
and Flutter presentation cannot be starved by a queued successor. Worker tasks
hold a safe object reference, resize messages release their native values, and
initial pixel-buffer callbacks always return valid dimensions. The software
buffer is bounded to 720p.

Software conversion runs on a serialized GLib worker instead of GTK's UI
thread. Front and render buffers are swapped only after a complete mpv frame,
and completed dimensions travel with that front buffer. The software texture
uses reusable OpenGL storage: it allocates with `glTexImage2D` only when its
dimensions change and uploads steady-state frames with `glTexSubImage2D`.
The front buffer stays locked during that upload, preventing mpv from recycling
memory while Flutter is reading it. The raster callback uses a non-blocking
try-lock; if mpv is converting the next frame, Flutter reuses the last uploaded
texture instead of stalling the entire UI behind video work.

The upstream Dart implementation did not apply
`VideoControllerConfiguration.scale` on Linux. VideoParams dimensions are now
scaled before `VideoOutputManager.SetSize`, reducing a 1080p CPU texture from
1920x1080 to 960x540 for Twitch Freedom's 0.5 fallback scale. Fixed dimensions
still take precedence until `setSize(null)` restores scaled source dimensions.

Remove the override only after an upstream release provides equivalent frame
coalescing, stable-buffer uploads, and passes repeated 1500×930 ↔ 1920×1090
resize/fullscreen stress testing under Sommelier.
