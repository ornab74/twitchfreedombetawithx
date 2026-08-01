

https://github.com/user-attachments/assets/02d51c6e-7179-4090-a43f-2e450480a2d1

# TwitchX Freedom

Twitch Freedom is a private, local-first Twitch player built with Flutter. It
plays streams, connects to Twitch chat, and can optionally run speech-to-text
and a local Gemma assistant on your own device.

There are no ads, thumbnails, emotes, cloud AI services, or demo channels in
the app. You choose what to enable.

## What it does

- Plays Twitch video or audio-only streams.
- Lets you choose stream quality and CPU or GPU video acceleration.
- Reads Twitch chat and can send messages after you connect your account.
- Stores settings, chat memory, and optional transcripts as encrypted records
  in a local SQLite vault.
- Supports optional local Gemma 4 E2B AI features.
- Supports optional local Moonshine Tiny speech-to-text and closed captions.
- Reads public X posts through the official X API in a separate X mode.
- Downloads X media directly into authenticated, encrypted local containers.

AI and transcript storage are off until you enable them.

## Guide map

- [System requirements](#system-requirements)
- [Install and run](#install-and-run)
- [Create and unlock the vault](#create-and-unlock-the-vault)
- [Configure Twitch](#configure-twitch)
- [Use Twitch playback and chat](#use-twitch-playback-and-chat)
- [Configure X](#configure-x)
- [Use every X mode](#use-every-x-mode)
- [Set up Gemma 4](#set-up-gemma-4)
- [Use Content Lab](#use-content-lab)
- [Encrypted storage and deletion](#encrypted-storage-and-deletion)
- [Troubleshooting](#troubleshooting)
 

## Feature reference

| Area | Feature | How to use it |
| --- | --- | --- |
| Vault | Password unlock | Create or unlock the workspace before any credentials or private records are available. |
| Vault | Remembered unlock | Enable at vault creation to use the OS keyring as an optional local unlock wrapper. |
| Twitch | Saved streams | Add a channel name or Twitch URL, then select it from navigation. |
| Twitch | Discovery | Authorize Twitch and use followed streams or channel search. |
| Twitch | Video/audio | Select playback mode, quality, acceleration, and low-latency preference before Play. |
| Twitch | Chat | Authorize Twitch, select a live channel, wait for Connected, then send manually. |
| Twitch | Captions | Enable local captions and install Moonshine Tiny in Control Center. |
| Twitch | AI companion | Enable local AI features, install/load Gemma, and choose mood, safety, joke, technical, calming, or memory options. |
| X | My Feed | Connect OAuth in X Settings, then open My Feed for the authenticated home timeline. |
| X | Account | Save a handle and app Bearer Token, then open Account for that public user's posts. |
| X | Search | Enter a recent-search query and combine language/media/reply/repost filters. |
| X | Carousel | Load any X source first, then page manually or allow timed local advance. |
| X | Follows | Reconnect with `follows.read`, then Sync to encrypt followers and following offline. |
| X | Media Vault | Select Store encrypted on a post; rotate keys or erase items from Vault. |
| X | Content Lab | Load posts and Gemma, set bounded controls, scan, then filter private classifications. |
| Privacy | Auto-lock | Set the idle interval in Control Center; locking clears sensitive runtime state. |
| Appearance | Themes/layout | Select an appearance profile in Control Center; compact layouts are supported. |

## System requirements

For Linux or ChromeOS/Crostini, use a current Flutter stable SDK with Linux
desktop enabled. The application needs enough free storage for its build output,
encrypted media, and the optional Gemma model. The pinned Gemma 4 E2B artifact
is approximately 2.6 GB, so allow several additional gigabytes for verification
and runtime overhead. Local inference also needs considerably more memory than
ordinary playback.

You need network access to Twitch and X only for their online features. The
vault, downloaded X media, offline social graph, Gemma inference, and retained
transcripts remain local. Twitch and X developer accounts are required only for
authenticated features.

## Install and run

Install Flutter first, then install the Linux build packages:

```bash
./scripts/install-linux-build-deps.sh
flutter config --enable-linux-desktop
flutter pub get
```

For normal use, run a release build:

```bash
flutter run --release -d linux
```

For performance testing with DevTools, use profile mode:

```bash
flutter run --profile -d linux
```

Plain `flutter run` starts a debug build. Debug mode uses JIT compilation and
extra checks, so its frame rate is not representative of the finished app.

On ChromeOS/Crostini, Twitch Freedom uses Sommelier's X11 bridge because the
native Wayland Flutter surface can stall on affected images. If the container
has no usable `/dev/dri` render node, the app keeps video safe by using Mesa
llvmpipe and CPU media decoding. A machine with a usable render node
automatically gets the accelerated path.

## Create and unlock the vault

1. Create a vault password with at least 10 characters.
2. Decide whether to enable **Remember this device**. This wraps the unlock key
   through the operating-system keyring; it does not remove vault encryption.
3. Keep the password somewhere safe. There is no cloud recovery service and the
   application cannot recover a forgotten vault password.
4. After unlocking, open **Control Center** for Twitch, AI, privacy, playback,
   discovery, and appearance settings.

The Linux keyring is only used for the optional “remember this device” feature.
If Crostini reports `KeyringLocked`, password unlock still works normally.

## Configure Twitch

Watching public streams does not require Twitch account authorization. Account
authorization is needed for followed-stream discovery and authenticated chat.

### Create the Twitch application

1. Sign in to the Twitch Developer Console with the account you intend to use.
2. Open **Applications**, choose **Register Your Application**, and give the app
   a recognizable name.
3. Select an appropriate application category. Twitch Freedom uses Twitch's
   device authorization flow, so the browser approval page is supplied by
   Twitch rather than hosted by this application.
4. After registration, open **Manage**, copy the **Client ID**, and generate a
   **Client Secret**. Treat the secret like a password.
5. Do not place either value in source code, shell history, screenshots, issue
   reports, or `.env` files committed to Git.

### Connect Twitch Freedom

1. Unlock the application vault.
2. Open **Control Center**, then the Twitch authorization section.
3. Enter the application's Client ID and Client Secret and save them.
4. Start device authorization. Twitch Freedom displays a short-lived user code
   and opens Twitch's verification page in the system browser.
5. Confirm that the browser is signed into the intended Twitch account, enter or
   approve the code, and return to the application.
6. Wait for the connection status to show the authorized Twitch login.

Requested scopes are `chat:read`, `user:write:chat`, and
`user:read:follows`.

The app encrypts the Twitch application credentials, access token, refresh
token, expiry, account ID, login, and granted scopes. It refreshes expiring
tokens automatically. It never asks for or stores your Twitch password.

## Use Twitch playback and chat

1. Add a saved stream using a channel name or an HTTPS Twitch channel URL.
2. Select **Video** or **Audio only**, then choose a quality. Lower resolutions
   and 30 FPS are useful on CPU-constrained Chromebooks.
3. Press Play. The player resolves Twitch's current HLS variants and rejects
   manifests or redirects outside the trusted Twitch CDN boundary.
4. Use the bottom player controls for pause, volume, speed, quality, and full
   screen. Player controls no longer place a translucent interaction layer over
   the video.
5. Chat connects to the selected channel after authorization. Sending uses
   Twitch's authenticated API and displays Twitch's send receipt as local echo.

Additional Twitch features include saved streams, followed-stream discovery,
search, audio-only playback, optional low latency, CPU/GPU backend selection,
encrypted bounded chat history, optional captions, local AI companion cards,
and appearance profiles. No chat message is sent automatically.

## Configure X

X mode uses only the official X API v2. It does not scrape pages or embed the X
website. Available endpoints and monthly usage depend on the X developer tier
attached to your project.

### Create the X project and app

1. Open the X Developer Portal and create or select a Project and App.
2. Open the app's **User authentication settings** and enable OAuth 2.0.
3. Choose an application type:
   - **Native App** is a public PKCE client. Copy the Client ID and leave Client
     Secret empty in Twitch Freedom.
   - **Web App / confidential client** has a Client ID and Client Secret. Enter
     both; Twitch Freedom authenticates token exchange and refresh with HTTP
     Basic while still using PKCE and callback-state validation.
4. Add this callback exactly, including scheme, address, port, and path:

   ```text
   http://127.0.0.1:27183/x/oauth/callback
   ```

5. Give the app read access and enable the scopes used here: `tweet.read`,
   `users.read`, `follows.read`, and `offline.access`.
6. Generate an app-only Bearer Token if you want public account lookup or recent
   search. My Feed and social-graph sync use the OAuth user token instead.

### Enter X credentials

1. Unlock Twitch Freedom and open **X mode** then **X Settings**.
2. Enter the OAuth Client ID. Enter the Client Secret only for a confidential
   client.
3. Optionally enter the app-only Bearer Token and a public account handle.
4. Select **Save settings**. Secret fields clear after saving because the UI is
   write-only; blank fields retain previously saved secret values.
5. Select **Connect My Feed**, approve X in the external browser, and return to
   the app after the local callback page confirms connection.

If the X app was authorized before `follows.read` was added, select **Remove
credentials**, enter the settings again, and reconnect. OAuth providers do not
retroactively add scopes to an existing token.

## Use every X mode

### My Feed

Loads the authenticated account's reverse-chronological home timeline. It does
not use the public account handle. Opening X mode, selecting **My Feed**, or
pressing Refresh requests this timeline directly with the OAuth user token.
Auto refresh is opt-in, runs at most every two minutes while unlocked, and keeps
at most 100 unique posts in memory.

### Account

Loads public posts for the handle saved in X Settings. For example, entering
`elonmusk` affects **Account**, not **My Feed**. Account lookup requires the
app-only Bearer Token.

### Search

Recent search supports X query operators plus language, media, reply, and repost
filters. Search requires the app-only Bearer Token. The result list becomes the
current Content Lab input until another source is loaded.

### Carousel

Displays the current My Feed, Account, or Search result set one post at a time.
It advances locally every nine seconds, pauses while video is playing, and does
not make an API request for each slide.

### Vault

Shows X photos and videos explicitly saved into encrypted media containers.
**Store encrypted** streams media directly into authenticated chunks without a
plaintext cache file. Rotate creates a fresh random media key and re-encrypts
stored containers. Erase deletes the record and container, checkpoints the
SQLite WAL where applicable, and removes the associated encryption key.

### Follows

The encrypted **Follows** view snapshots both followers and following for
offline browsing and marks mutual connections. It requires `follows.read`; users
authorized by an older build must remove the X credentials and reconnect once.
Press Sync while online; the last authenticated snapshot remains readable after
the network is disconnected as long as the vault is unlocked.

### X Settings

Contains connection status, OAuth credentials, app-only access, the fixed
callback, save/connect actions, and secure credential removal. Removing X
credentials stops feed refresh and deletes the encrypted credential record. It
does not silently publish, follow, like, repost, or message anyone.

## Set up Gemma 4

Content Lab and the optional Twitch AI companion share the local Gemma 4 E2B
runtime. Content Lab does not require cloud AI or an API key.

### Install from inside the app

1. Unlock the vault and open **Content Lab** or **Control Center > Local AI**.
2. Select **Install model** / **Install verified Gemma 4 E2B**.
3. Keep the app open while the pinned artifact downloads.
4. The app checks file type, maximum size, immutable model revision, and SHA-256
   before recording an encrypted attestation and loading it.

### Use an existing model file

1. The file must be named or selected as `gemma-4-E2B-it.litertlm` and must
   match the pinned digest in `AppConfig`.
2. Open **Control Center > Local AI > Gemma model file**, choose the file or its
   containing directory, and let verification finish.
3. Select a backend. `GPU first` is the normal choice; `CPU only` is slower but
   useful on systems with unstable or unavailable acceleration.
4. Enable **Load selected model after unlock** for automatic loading, or use
   **Load model** inside Content Lab when needed.

The model is approximately 2.6 GB. A failed digest is not bypassed: use the
pinned artifact rather than renaming an unrelated `.litertlm` model.

## Use Content Lab

**Content Lab** sends bounded batches of already-loaded posts to the local Gemma
4 model. Runs are limited by both loop count and elapsed time. Its private scores
power mood, topic, visual-color, weirdness, meme, and negativity filters plus a
topic cloud. These are uncertain content classifications, not claims about an
author, and Content Lab never publishes or performs an X action.

1. Load posts from **My Feed**, **Account**, or **Search**.
2. Open **Content Lab**. Its header must say **Gemma 4 ready on device**. If it
   says installed but unloaded, press **Load model**. If missing, press
   **Install model**.
3. Choose Loops and Minutes. Both are hard bounds; reaching either one stops the
   run. Each loop classifies at most five posts to fit Gemma's context safely.
4. Press **Scan locally**. Progress and failures appear inside Content Lab. Stop
   remains available during generation.
5. Refine the classified set with:
   - Mood: funny, calm, weird, scary, mad, or uplifting.
   - Topic: science, engineering, music, memes, art, or technology.
   - Color: blue, orange, purple, red, or green when the supplied content gives
     evidence for a visual palette.
   - Memes: requires a minimum private meme-confidence score.
   - Low negativity: sets the maximum allowed negativity score.
   - More weird: sets the minimum weirdness score.
6. Select a topic-cloud chip to focus the results immediately.

Post text, usernames, and metadata are wrapped as untrusted data. The prompt
forbids following embedded instructions, revealing secrets, taking X actions,
or treating mood as diagnosis. Model output must match a strict JSON schema and
reference only post IDs supplied in that batch. Invalid or truncated output is
rejected and shown as a failure rather than applied silently.

Downloaded photos and videos are accepted only from exact HTTPS X media hosts,
bounded to 1 GiB, and encrypted in independently authenticated 1 MiB chunks as
they arrive. Plaintext media is never written to a cache file. The media-key
rotation command creates a fresh random 256-bit key and container before
cryptographically erasing the prior key and file.

Feed images are decoded into memory and evicted when their widgets are disposed.
Inline video is tap-to-play with Media Kit disk caching disabled and a 64 MiB RAM
buffer ceiling. The player selects a bandwidth-capped rendition for stable inline
playback, prebuffers finite clips in memory, and pauses carousel movement while a
video is playing. Viewing feed media does not implicitly create a durable copy.

## Local AI model

The expected file is:

```text
gemma-4-E2B-it.litertlm
```

You can download it inside the app or select that exact `.litertlm` file. The
app checks the pinned SHA-256 digest before registering it. Model files are
large and are intentionally ignored by Git.

Moonshine Tiny is the lower-cost speech model used for optional captions. Raw
audio windows are temporary and are deleted after local transcription.
Transcript retention is a separate opt-in setting.

## Encrypted storage and deletion

On Linux, the vault and downloaded models are kept in the Flutter application
support directory under `TwitchFreedom/`:

```text
TwitchFreedom/vault.sqlite3
TwitchFreedom/models/
TwitchFreedom/x-media/
```

The vault encrypts individual records with AES-256-GCM. The SQLite file itself
is not page-encrypted, so file size and update timing can still be visible. See
[SECURITY.md](SECURITY.md) for the full security boundary.

`.gitignore` excludes SQLite databases and their WAL/SHM files, downloaded
models, temporary audio, profiler output, local environment files, and signing
keys. Do not force-add those files to a commit.

Locking closes the vault, clears credentials and social data from application
memory, stops refresh timers, disconnects chat, stops playback, and unloads the
local models. Credential removal deletes the relevant encrypted record. Media
deletion and key rotation also checkpoint deleted SQLite/WAL state where the
storage implementation can do so. Filesystem snapshots, SSD wear leveling, and
host backups remain outside the application's deletion guarantee; see
[SECURITY.md](SECURITY.md).

## Useful Linux overrides

Most users should leave these unset:

```bash
TWITCH_FREEDOM_SOFTWARE=1 flutter run --release -d linux
TWITCH_FREEDOM_ACCELERATED_UI=1 flutter run --release -d linux
TWITCH_FREEDOM_GDK_BACKEND=wayland flutter run --release -d linux
LP_NUM_THREADS=6 flutter run --release -d linux
```

- `TWITCH_FREEDOM_SOFTWARE=1` forces the CPU-safe UI path.
- `TWITCH_FREEDOM_ACCELERATED_UI=1` tries acceleration even without a detected
  render node.
- `TWITCH_FREEDOM_GDK_BACKEND=wayland` is an experimental override. The tested
  Crostini default is X11.
- `LP_NUM_THREADS` manually limits llvmpipe workers. The Crostini default is
  four so input and video decoding retain CPU time.

## Troubleshooting

### Twitch authorization does not start

- Confirm the Twitch Client ID contains only the developer-console identifier,
  with no spaces or quotes.
- Generate a current Client Secret and save both values before starting device
  authorization.
- Ensure the system clock is correct and the verification code has not expired.
- If authorization completes but chat cannot send, remove Twitch authorization
  and reconnect so all current scopes are granted.

### X authorization cannot complete

- Confirm the callback in the X portal exactly matches
  `http://127.0.0.1:27183/x/oauth/callback`.
- Make sure no other process is using local port `27183`.
- Native App: use Client ID and leave Client Secret empty.
- Confidential Web App: provide both Client ID and Client Secret.
- Do not paste an app-only Bearer Token into the Client ID or OAuth secret
  fields; they are different credential types.
- If Follows returns an authorization error, remove credentials and reconnect to
  grant `follows.read`.

### My Feed shows an account instead of the home timeline

Use **My Feed** for the OAuth account's home timeline. The handle in X Settings
belongs to the separate **Account** tab. Search results similarly remain their
own source until My Feed is selected again.

### Content Lab does not run

1. Load actual posts in My Feed, Account, or Search.
2. Open Content Lab and inspect the model status at the top.
3. Install or load Gemma 4 there. A model file that has not passed SHA-256
   attestation will not load.
4. Start with one loop and one minute. Each loop may take a while on CPU.
5. Read the inline lab message. Model-not-ready, no-content, generation, and
   invalid-JSON failures are now shown directly.
6. If structured output fails twice, reload the model and retry a short run.
7. On low-memory systems, choose CPU Only, close other large applications, use
   smaller runs, and avoid simultaneous video decoding and model installation.

### Video stutters

- Choose a 30 FPS or lower-resolution stream quality.
- Try Audio only to separate network/decoder issues from UI rendering.
- On Crostini without `/dev/dri`, allow the CPU-safe defaults to remain active.
- Do not judge release performance using a debug build.

### Vault or keyring problems

`KeyringLocked` affects remembered unlock, not password-based vault access. Use
the vault password. Back up the encrypted application-support directory only
while the application is closed so SQLite, WAL, encrypted media, and metadata
remain consistent.

## Development checks

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
./tool/verify_linux_ready.sh
```

The Linux player uses local Media Kit patches in `third_party/`. Do not replace
those path dependencies with hosted packages unless the native texture and
shutdown fixes have been upstreamed.

## Privacy and licensing

Nothing is automatically posted to Twitch. Raw chat remains visible even when
AI features are enabled, and AI-generated alternatives are labeled.

See [SECURITY.md](SECURITY.md), [docs/architecture.md](docs/architecture.md),
and [docs/licensing.md](docs/licensing.md) for implementation and licensing
details.
