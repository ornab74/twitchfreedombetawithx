# Security Model

## Goals

Twitch Freedom protects saved streams, Twitch and X credentials, OAuth tokens, chat transcripts, downloaded X media, preferences, local AI memory, and model attestations against casual offline disclosure and tampering after the application is closed.

## Cryptographic design

- Password KDF: Argon2id, 64 MiB, three iterations, parallelism two, 16-byte random salt.
- KEK: password-derived and never persisted.
- VUK: random 256-bit vault-unlock key, wrapped by the KEK.
- DEKs: versioned random 256-bit record keys wrapped by the VUK.
- Records: AES-256-GCM with a fresh 96-bit nonce.
- Associated data: logical record type, obscured record ID, and key version.
- Logical IDs: HMAC-SHA-256-derived identifiers.
- Password change: rewraps the VUK.
- DEK rotation: inserts a new wrapped DEK, migrates every record, changes the active version, and deletes unreferenced wrapped prior keys within one SQLite transaction. The WAL is then truncated so rotation provides cryptographic erasure of old record keys.
- Remember-on-device: stores only the VUK in OS secure storage and fails closed when authentication fails.

### Windows key storage

- The pinned Windows secure-storage backend uses `CryptProtectData` and
  `CryptUnprotectData` without `CRYPTPROTECT_LOCAL_MACHINE`, binding remembered
  unlock to the current Windows user rather than every user of the machine.
- Legacy Credential Manager compatibility is explicitly disabled. The
  encrypted DPAPI blob lives under the application-support directory and the
  vault database independently retains its Argon2id/wrapped-key/AES-GCM
  hierarchy.
- Remembered unlock is opt-in. Disabling it deletes the DPAPI-protected VUK
  before a password-change commit, so an OS-storage failure cannot silently
  retain unwanted auto-unlock.
- Lock and shutdown wipe reachable application-owned VUK, KEK, DEK, verifier,
  and decrypted-record byte buffers. Dart strings and copies made inside native
  or runtime libraries cannot be guaranteed to be physically overwritten.

### Windows release provenance

- Pull-request and branch packages are unsigned technical artifacts.
- A `v*` Windows tag requires protected PFX and password secrets, imports the
  certificate only into the ephemeral runner's current-user store, signs and
  verifies shipped PE files and the MSI, removes the temporary certificate,
  and hashes the final signed artifacts.
- Release signing fails closed for missing, expired, non-code-signing, or
  unverifiable certificates. Dependency resolution also enforces the committed
  lockfile and the repository's exact package-version baseline.

## Network boundaries

- Twitch URLs must be HTTPS and match a Twitch host allowlist.
- Playback redirects are limited to Twitch/CDN suffixes.
- Manifest and response sizes are bounded.
- Twitch playback signatures, OAuth tokens, secrets, and model prompts are redacted from logs.
- No embedded WebView is required for ordinary operation.
- Device authorization opens the system browser.
- X access uses the official API v2 and stores credentials as an encrypted
  record. No X client secret is embedded in the desktop application.
- X media redirects remain HTTPS and must resolve to exact `pbs.twimg.com` or
  `video.twimg.com` hosts. Media downloads have a 1 GiB ceiling.
- Feed images are memory-only and evicted when removed from the widget tree.
  Inline videos are user-initiated, use no disk cache, and have a 64 MiB RAM
  buffer limit.
- X user authorization uses OAuth 2 PKCE with S256, a fixed IPv4 loopback
  callback, verified state, minimal read scopes, and encrypted token storage.
  Public clients use no secret; confidential clients send the user-supplied,
  encrypted secret only as HTTP Basic authentication to X's token endpoint.
- Automatic home-feed refresh is disabled by default, stops on vault lock, and
  runs no more frequently than every two minutes when enabled.
- Follower/following snapshots are encrypted as independently authenticated
  vault records. Gemma Content Lab receives bounded in-memory post batches,
  runs locally with explicit loop/time limits, and never takes actions on X.

## Encrypted X media

- Media is sealed while streaming in 1 MiB AES-256-GCM chunks with unique
  nonces and container/chunk associated data.
- Each media item has an independent random 256-bit key. That key and metadata
  are stored inside the encrypted SQLite vault; only ciphertext is stored in
  `x-media/`.
- Delete removes the key first, truncates the SQLite WAL, and then removes the
  ciphertext file. On flash storage, physical overwriting cannot be promised;
  deletion relies on cryptographic erasure.
- Rotation writes and authenticates a new-key container before switching the
  encrypted metadata and removing the old container.

## Local AI boundaries

- AI is disabled by default.
- Model installation uses a pinned URL, maximum byte count, and pinned SHA-256.
- Chat text is treated as untrusted quoted data in prompts.
- The model cannot post messages.
- Protective Mirror never replaces the canonical stored chat line.
- Speech audio is ephemeral and deleted after local transcription.
- Derived memory is isolated by channel and expires.

## Out of scope

- A compromised operating system or process with access to unlocked memory.
- Another process already executing as the same Windows user; user-scoped
  DPAPI is an account boundary, not application-process isolation.
- Screen capture, keylogging, or malicious accessibility services.
- Traffic analysis and filesystem metadata such as ciphertext size and timestamps.
- Twitch account compromise.
- X developer account, App, or bearer-token compromise while the vault is open.
- Vulnerabilities in native media/model runtimes.

## Reporting

Do not include OAuth tokens, client secrets, model prompts, chat logs, or vault files in public bug reports. Reproduce using synthetic records and attach redacted diagnostics only.
