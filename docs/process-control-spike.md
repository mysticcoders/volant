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
