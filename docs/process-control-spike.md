# Process control under App Sandbox: what a Kill Process command could do

Kill Process is the most-installed Raycast extension, at roughly 748,000 installs. It belongs in
the family Volant already has natively — volume, audio devices, connectivity, Caffeinate — rather
than in an extension, because as an extension it would need the most dangerous capability that
could be defined, while as a native command it needs none. The open question was whether a
sandboxed Volant can do it at all. This spike answers that with measurement rather than opinion.

Nothing here is implemented. `tools/spike-process.sh` and `tools/spike-process-vm.py` reproduce it.

## Method

One binary, `tools/process/main.swift`, run twice from signed app bundles that differ only by the
App Sandbox entitlement. The sandboxed bundle carries Volant's own `Volant.entitlements`; the
baseline carries an empty entitlement set. Every probe is independent, so one denial cannot hide
another result.

Termination permission is checked with `kill(pid, 0)`, which performs the kernel's access check
and sends no signal. The destructive half — actually calling `NSRunningApplication.terminate()`
against a real application — runs only in a headless Tart guest against TextEdit, never on the
owner's desktop.

## Results

Reading is available. Acting is denied.

| Probe | Unsandboxed | Sandboxed |
| --- | --- | --- |
| `NSWorkspace.runningApplications` | 272 apps, names and icons | 272 apps, names and icons |
| `proc_listallpids` | 628 pids | **DENIED, EPERM** |
| `sysctl KERN_PROC_ALL` | succeeds | succeeds |
| `proc_name`, `proc_pidpath` | readable | readable |
| `proc_pidinfo` CPU and memory | readable | readable |
| `kill(pid, 0)` on GUI applications | **267 of 271 permitted** | **0 of 271 permitted** |
| `NSRunningApplication.terminate()` | returned true, quit the app | returned **false**, app still running |
| `NSRunningApplication.forceTerminate()` | not needed | returned **false**, app still running |

The GUI-application row is the cleanest evidence: it uses real process identifiers from
`NSWorkspace`, so it does not depend on parsing the kernel's process table. Sandboxed, every one
of them is refused.

`proc_listallpids` being denied does not prevent building a process list; `sysctl KERN_PROC_ALL`
still returns the table, and per-process name, path, CPU and memory remain readable through
`proc_pidinfo`. A read-only process viewer is therefore entirely possible inside the sandbox.

Caveat on one number: the spike's count of `sysctl` entries divides the reply by
`MemoryLayout<kinfo_proc>.stride`, which over-counts, so roughly half the identifiers it derives
are not live processes. That affects only the reported totals in the per-process rows. It does not
affect the termination findings, which were confirmed against real application identifiers and
against a real application.

## What this rules out

The expectation going in was that the process table would be the hard part and quitting an
application would be easy, on the reasoning that `terminate()` posts a quit Apple Event rather
than a signal. That was wrong in both halves. Reading is unrestricted enough to build the whole
display; `terminate()` and `forceTerminate()` both return false and do nothing.

So there is no scoped, sandbox-safe version of this feature. A narrower "Quit Application"
command that only touches user-facing applications fails exactly as the general case does.

## Options

1. **Do not ship it.** A process viewer that cannot act is not worth a command.
2. **An unsandboxed helper.** `VolantAgentHost` already runs with `ENABLE_APP_SANDBOX: NO`, so the
   precedent and the signing work exist. This is the only route that can work.
3. There is no temporary-exception entitlement for signalling other processes, so there is no
   third option that keeps the main app's posture intact.

Option 2 is a genuine security decision, not a feature detail. A helper that can terminate any
process owned by the user is a high-value target, and it would be reachable by anything that can
talk to it. If it is built, its entire API should be one operation — terminate a specific process
identifier that the helper itself re-validates as a user-facing application owned by the same
user — rather than a general signal-sending interface. The same rule `AGENTS.md` already states
for the agent helper applies: keep an explicit narrow API. Root and system processes should be
refused by the helper, not merely hidden by the launcher.

Selection stays in the sandboxed app. The helper never enumerates on the app's behalf and never
accepts a name or a pattern, only an identifier it can independently confirm.

## Relationship to extension capabilities

This is a concrete instance of the broker pattern that extension capabilities need: the privileged
operation lives in a separately entitled process with a deliberately narrow interface, and the
unprivileged caller decides only which operation to request. `AIRedirectGuard` and
`AIHTTPConfiguration.baseURL()` are the existing examples on the network side. If Kill Process is
built this way, it becomes the reference for how a capability broker should look, which is a
better reason to build it than the install count.

## Follow-up: a separately entitled helper does work — September 20, 2026

The open question the first spike left was whether an unsandboxed XPC service *embedded in a
sandboxed app* keeps the permission the app lacks. It does. `tools/spike-privaccess.sh` builds a
sandboxed fixture app with an embedded helper, both Developer ID signed, and
`tools/spike-privaccess-vm.py` runs it against TextEdit in the guest.

The helper's whole vocabulary is one operation plus a probe that sends no signal. There is no
signal-number parameter, and it accepts no names or patterns, so it can never be asked to resolve
a target itself.

Measured in a single run, so the two sides are the same process, machine and moment:

| Step | Result |
| --- | --- |
| Sandboxed client `kill(pid, 0)` | EPERM |
| Sandboxed client `terminate()` | false, TextEdit still running |
| Helper `kill(pid, 0)` | **permitted** |
| Helper asked to terminate with a mismatched bundle identifier | **refused**: "pid 597 is now com.apple.TextEdit, not com.example.not.this.app" |
| Helper asked to terminate the real pair | succeeded, TextEdit quit |

### The caller check was tested by attacking it

A control that has only ever been observed allowing things is not verified. The attack the
code-signing requirement exists to stop is a repackaged app that embeds the genuine, validly
signed helper but whose own binary is not signed by this team. `Intruder.app` is exactly that:
the same bundle with only the outer signature replaced by an ad-hoc one.

The intruder was refused and TextEdit survived; the legitimate client succeeded moments later
against the same helper on the same machine. Because only the caller's signature differs between
those two runs, the refusal is attributable to `setCodeSigningRequirement`. Note that a refused
connection and a helper that fails to launch produce the same symptom from the caller's side —
"Couldn't communicate with a helper application" — so this conclusion rests on the differential,
not on a distinct denial message.

Worth keeping in proportion: bundled XPC services are already private to their containing bundle,
so the signing requirement is defence in depth rather than the primary boundary. The primary
boundary is that nothing outside the app can look the service up at all. The requirement is what
stops the repackaging attack that gets past it.

### What cost an hour, and is worth knowing

The helper refused to launch, and the symptom pointed at permissions. It was not permissions. The
helper was compiled on a macOS 27 host with no deployment target, so it linked
`libswift_DarwinFoundation1.dylib`, which does not exist on the macOS 15 baseline, and died on
launch with `OS_REASON_DYLD`. Building with `-target arm64-apple-macosx15.0` fixed it.

This is the same host-versus-guest mismatch `launcher-actions.md` already records for the SwiftUI
expression budget. Ad-hoc `swiftc` fixtures must carry the deployment target, or they prove
something about the developer's machine rather than about Volant.

Two other changes were made while chasing that failure — the helper's entitlements moved from
`app-sandbox: false` to an empty dictionary, and the bundle gained the `CFBundleVersion` family of
keys. Neither was isolated, so neither is known to have mattered. Matching what `VolantAgentHost`
actually ships is reason enough to keep both.

### What this does not settle

The architecture works; whether to ship it is still the open question, and it is a security
decision rather than a feature one. Unchanged from the first spike: the helper would be reachable
by anything that satisfies the requirement, the refusals must stay in the helper rather than the
launcher, and the README's "sandboxed macOS launcher" framing needs to grow a fuller disclosure
than it currently carries for the agent helper.

## Ports: who is listening, and can Volant stop it — October 14, 2026

The owner wants a `ports` view for the many localhost dev servers people run: one row per listening
TCP port, such as "3000 · node · ~/code/my-app · 2h", where Return opens `http://localhost:3000`,
Command-Return copies the URL and a further action stops the server. `tools/spike-ports.sh` measures
whether that can be built. It starts a fictional dev server (`tools/process/ports.swift` in
`listen` mode, bound to 127.0.0.1:47823) inside a temporary project folder, probes it from two
ad-hoc signed bundles that differ only by App Sandbox, and stops the listener. The sandboxed bundle
carries `VolantDev.entitlements` (the release set minus iCloud, because an ad-hoc signature cannot
launch with the iCloud entitlement; the first attempt with `Volant.entitlements` was killed at
launch). Only counts are printed for the owner's other processes, never their names or ports.

Measured on macOS 27.0.1 on the owner's Mac:

| Probe | Unsandboxed | Sandboxed |
| --- | --- | --- |
| Target's descriptors, `PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO` | found the listening socket on 47823 | **DENIED, EPERM** |
| Scan of every same-user pid from `sysctl KERN_PROC_UID` | 1115 of 1118 descriptor tables readable, 26 listening sockets, target found | **1 of 1118** (its own), none found |
| `/usr/sbin/lsof -iTCP -sTCP:LISTEN` as a child process | found the owner | exit 1, no owner (the child inherits the sandbox) |
| `sysctl net.inet.tcp.pcblist_n` | 48 bytes, the header with no entries | same |
| `proc_name` | readable | readable |
| Working directory, `PROC_PIDVNODEPATHINFO` | matches the project folder | **matches the project folder** |
| Start time and uid, `PROC_PIDTBSDINFO` | readable | readable |
| `kill(pid, 0)` on the listener | permitted | EPERM |

So the sandbox splits the row in half. Given a pid, the app can name it, find its project folder
and work out its age, but it cannot learn which pid owns a port: socket ownership is behind the
same per-process check that blocks signalling. `pcblist_n` would have carried ports without
ownership anyway, and returns no entries to a non-root caller. The main app has no network
entitlement, so it cannot even probe the port with a connection. The port-to-pid mapping has to
come from an unsandboxed helper, as a read-only call, alongside the termination the first spike
already showed needs one.

The earlier follow-up showed that an unsandboxed helper embedded in the signed, sandboxed app keeps
its own permissions and refuses repackaged callers. The unsandboxed column above is therefore what
such a helper would see. That was not re-measured from an embedded helper for ports, nor on the
macOS 15 baseline.

### Proposed helper API (for the owner to approve before anything is built)

A new helper, `VolantProcessHost`, rather than more methods on `VolantAgentHost`: `AGENTS.md`
requires the agent helper to keep an explicit narrow API, and process control is a separate grant
the owner should be able to reason about on its own. Same signing, same
`setCodeSigningRequirement` caller check, launched only when a process command is first used,
never at startup.

Three operations. None takes a name, pattern, path or signal number.

1. `listeners() -> [Listener]`, read-only. For processes owned by the caller's uid only, each
   listening TCP socket as `pid`, `port`, whether it is bound to loopback or all interfaces,
   process name, working directory and start time. At most 256 rows; root and other users'
   processes are never returned. No command-line arguments: they often carry tokens, and the
   working directory already says which project it is.
2. `quitApplication(pid, bundleIdentifier)`, the operation the first follow-up already built: the
   helper confirms the pid is still that user-facing application, then asks it to quit.
3. `stopListener(pid, port, startTime, force)`. Dev servers are background node, python or ruby
   processes, not applications, so this needs its own rule. At call time the helper re-checks that
   the pid is owned by the caller's uid, is not root, is not Volant or one of its helpers, has an
   executable outside `/System`, `/usr/libexec` and `/usr/sbin`, still has the recorded start time
   (so a reused pid is refused), and is listening on exactly that port right now. Then it sends
   SIGTERM, or SIGKILL only when `force` is true; the launcher offers Force Stop only after a stop
   has not worked. Every refusal returns a reason the launcher shows.

The launcher keeps selection: it shows what `listeners()` returned and sends back the exact pid,
port and start time of the chosen row. Opening `http://localhost:<port>` and copying the URL need
no helper.

### Still open

- Whether to ship a helper that can stop the owner's processes at all. That is the owner's
  security decision; this spike only shows it is the one route that works.
- The README and privacy docs would need to say that Volant has a second unsandboxed helper and
  exactly what it can do.
- Not measured: IPv6-only listeners (the probe bound IPv4) and a listener in another user's session.
- Cost is not a concern: scanning every same-user process's descriptors (about 1,118 processes)
  took 6, 16 and 8 ms unsandboxed in three runs, so `listeners()` can scan on each query rather
  than cache.
