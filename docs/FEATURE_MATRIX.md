# Feature matrix

| Area | Included behavior |
|---|---|
| Interface | Responsive desktop/mobile layouts, retractable stream drawer, large player surface, chat, local-AI companion, text-only Explore, settings/control center, help, six themes, reduced motion, title visibility, keyboard semantics |
| Privacy | No remote thumbnails, avatars, emotes, ads SDK, embedded browser, cloud AI, synthetic chat, or automatic Twitch posting |
| Vault | Boot password, optional OS remembered unlock, Argon2id KEK, wrapped VUK and versioned DEKs, AES-256-GCM records, HMAC-obscured IDs, password rewrap, atomic DEK rotation, auto-lock |
| Twitch | Device-code OAuth, token validation/refresh, followed-stream discovery, text search, channel metadata, official chat send, IRC TLS with PING/PONG/RECONNECT/backoff |
| Resolver | Playback-access-token GraphQL request, trusted Usher URL, bounded HLS fetch, manual validated redirects, safe M3U8 master parsing, audio/30/60 FPS selection |
| Playback | Media Kit default, native `video_player` option on Apple/Android, bounded desktop system-FFmpeg audio tap, quality/volume/pause/recovery |
| Gemma | Revision/digest-pinned verified installer, LiteRT-LM Gemma 4 model registration, CPU/GPU/NPU preferences, serialized role agents, cancellation, candidate-only reranking |
| Speech | Optional Moonshine-Tiny install, five-second PCM windows, local transcription, raw-file overwrite/delete, optional encrypted derived transcript retention |
| AI chat | Batched mood labels, caution scores, Protective Mirror with original reveal, dim/blur/hide modes, private jokes, technical companion, calming options, summaries |
| Memory | Per-channel encrypted summaries and optional transcripts, TTL handling, no cross-channel prompt mixing |
| Engineering | Unit/integration tests, source security scanner, bootstrap/configuration scripts, pinned CI actions, checksums, unsigned multi-platform artifact builds |
