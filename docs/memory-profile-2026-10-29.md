# ACP streaming deltas — October 29, 2026

Issue #17's first remaining item: while an ACP reply streamed, every 0.25 s poll still encoded, copied over XPC and decoded the whole conversation, because it had changed. The [October 10 profile](memory-profile-2026-10-10.md) measured about 27 MiB a second for a 1 MB conversation. Measured with the same opt-in fixture in `tools/memory`, fictional conversations, no provider, no owner data and no signed or installed build.

## What changed

- **The helper remembers what it sent.** `ACPConnection` keeps the state and revision of its last reply. Copy-on-write shares that storage with the live state until a message changes, so it costs about one extra copy of the message being streamed.
- **Reads from that revision get only what changed.** `acpRead(after:)` now replies with an `ACPStateUpdate`. When `after` is the revision sent last, the update carries every field except the transcript in full, plus the messages from the first one that differs (`from`). While a reply streams that is normally just its last message. Any other `after` gets the full state (`base` nil), and the current revision still gets no data.
- **The app patches only the revision it holds.** `ACPModel.receive` applies a partial update only when its `base` is the read's `after` and the app's state is still exactly that revision. Any other partial update, including one whose `from` lies outside the app's transcript or one that raced a local change, is stale: the app forgets the helper revision and the next read fetches the full state. A partial update never patches a transcript it wasn't built from.
- **Unchanged:** the 0.25 s timer, the no-data reply for an unchanged conversation, the stale-read guard, and session ownership. Prompt rejection and permission cancellation are untouched too. The AI helper (BYOK and local) still sends a plain `ACPState`, marked by revision -1, because its conversations are capped at 100 messages and 256 KB of text.

## Method

`VOLANT_MEMORY_SCENARIOS="acp-poll-small acp-poll-200k acp-poll-1m" tools/profile-memory.sh OUTPUT` built the optimized fixture from this branch and ran each workload in three fresh processes; the table shows medians. The workloads are those of October 10: 3, 40 or 190 fictional turns built through the real `ACPConnection`, then 40 polls while four 48-byte chunks stream in between each. `full_streaming_40` is the old read, the full state encoded on every poll; `revision_streaming_40` is the production read, now with deltas. Per-second figures assume the 0.25 s poll interval.

## Results

| Conversation | Snapshot | Old read while streaming | New read while streaming |
| --- | --- | --- | --- |
| small, 15 messages | 16 KB | 0.86 MiB/s, 1,731 allocations/s, 1.25 ms/s | 0.39 MiB/s, 904 allocations/s, 0.66 ms/s |
| 200k, 200 messages | 213 KB | 6.38 MiB/s, 11,635 allocations/s, 4.80 ms/s | 0.47 MiB/s, 904 allocations/s, 0.84 ms/s |
| 1m, 950 messages | 1.0 MB | 26.90 MiB/s, 51,267 allocations/s, 20.4 ms/s | 0.83 MiB/s, 904 allocations/s, 1.79 ms/s |

The allocation count no longer grows with the conversation. What still grows with it is small: the app's patched message array and the equality check against its current state. The fixture asserts at the end that the app's patched state equals the helper's.

## Verified and not verified

- **Verified:**
  - The table above.
  - `./tools/check-acp.sh`: a reader without a revision, or at any revision other than the one sent last, gets the full state. Text appended in place sends only the message it changed, and the patched transcript equals the helper's. Every existing check passes.
  - `ACPStateUpdateTests` (Core): where changes start, rebuilding every kind of change, and rejecting bad offsets.
  - `ACPSnapshotModelTests`: only the changed messages patch the held revision, at under a tenth of the full encoding. An update for another revision, one after a local change, and one beyond the held transcript are each stale and force the full state. The AI helper's plain state still applies.
- **Not verified:** a signed, installed VolantAgentHost streaming a real provider. The fixture runs the helper's and the app's code in one process over an in-process XPC connection.

## Helper savings — October 30, 2026

The two small savings recommended in the October 10 profile, measured with the same fixture (`VOLANT_MEMORY_SCENARIOS="acp-poll-200k acp-poll-1m"`, three fresh processes, medians):

- **Tool updates are counted by their frame's size.** `updateSession` used to encode each tool update to JSON again only to count it against the 2 MB tool-detail limit. It now counts the size of the frame the update arrived in, which is slightly larger, so the limit is a little stricter, never looser.
- **The agent's capabilities are read once.** `ACPConnection` decides at initialization whether the agent accepts embedded context, instead of parsing the capabilities JSON again for every prompt.

Building the conversation (`transcript_built`, which feeds every provider frame through the helper):

| Conversation | Before | After |
| --- | --- | --- |
| 200k | 13.2 MiB, 32,798 allocations, 11.7 ms | 11.7 MiB, 29,542 allocations, 9.1 ms |
| 1m | 62.6 MiB, 156,600 allocations, 47.4 ms | 55.7 MiB, 141,191 allocations, 40.7 ms |

`./tools/check-acp.sh` adds a check that tool details past 2 MB end the conversation. Its existing embedded-context checks still pass.
