# PulseMesh adaptive task scheduler

PulseMesh is the application's central asynchronous work coordinator. It is not
a thread pool and it does not attempt unsafe parallel on-device inference. It
organizes Dart futures into resource-aware lanes while preserving Flutter's
single UI isolate.

## Lanes

| Lane | Typical work | Concurrency |
|---|---|---:|
| realtime | chat keepalive, immediate state transitions | 4 |
| interactive | user-triggered actions | 2 |
| network | Twitch API and resolver work | 3 |
| AI | Gemma inference and structured analysis | 1 |
| maintenance | speech windows, cleanup, memory compaction | 1 |

The global cap is four running tasks. The AI lane is intentionally serialized
because local inference sessions share accelerator and memory pressure.

## New scheduling ideas

### Resource-credit surface

Every task declares an estimated cost. Credits regenerate more slowly while
video is active, which naturally yields capacity to playback and chat. Realtime
work can bypass low credits; AI and maintenance work cannot.

### Affinity gravity

Tasks can declare an affinity such as `gemma:<channel>` or `audio:<channel>`.
A small score boost keeps related work adjacent and reduces model/session or
audio-pipeline thrashing without allowing affinity to defeat deadlines.

### Deadline curvature and fairness aging

Queued work gains priority with age. Deadlines create a nonlinear priority
boost as they approach, so old low-priority tasks cannot starve and urgent
interactive work still wins.

### Epoch-scoped cancellation

Scopes use monotonically increasing epochs. Switching channels or locking the
vault increments the scope epoch. Already-running work detects that its epoch
is stale even after the scope is immediately reused, avoiding the common race
where a Boolean cancellation flag gets cleared too early.

### Single-flight coalescing

Equivalent tasks share one future. Multiple UI rebuilds or repeated taps cannot
start duplicate model loads, analyses, or network requests when they use the
same task key.

### Adaptive recurrence

AI review cadence is not a fixed timer. It moves between five and ten minutes
based on recent chat velocity. Speech-context cadence also adapts, but remains
separate so transcription cannot delay raw chat or playback.

### Capability gates

Tasks can require an unlocked vault or loaded model. They stay queued instead
of repeatedly failing while the capability is unavailable.

### Bounded recovery

Retry policies use bounded exponential backoff plus jitter. Retry state remains
inside the scheduler, not scattered across UI widgets.

## Clean boot order

The `BootPipeline` runs these explicit stages:

1. Platform rendering/security policy
2. PulseMesh startup
3. Vault existence and secure-store probe
4. Optional remembered unlock
5. Encrypted state hydration
6. Gemma artifact-attestation check
7. Moonshine registration-attestation check
8. Ready state and recurring-task arming

A required stage fails closed. Optional future stages can be marked nonfatal.
