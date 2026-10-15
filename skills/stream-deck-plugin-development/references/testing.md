# Behavioral regression scenarios

Select the rows relevant to the requested change. Tests must assert effects and received messages, not merely match source text.

| Scenario | Evidence to require |
|---|---|
| Registration | Real plugin entry point consumes launch arguments and registers the supplied UUID/event on a local fake WebSocket host. |
| Two buttons | Editing one context changes only its image/settings; same action UUID does not merge instances. |
| Persistence | Reopen inspector/restart host with saved values; defaults fill missing fields without discarding unknown fields. |
| Appearance | Render all variants, size extremes and marker corners; inspect actual PNGs for clipping, contrast, outline, glow and rounding. |
| Animation | Different timed frames reach only the animated visible context; static images are not resent unchanged; disappeared contexts stay stopped even after a late settings event. |
| Lost host connection | Cancel old tasks, reconnect and register once; no duplicate loops or replayed click. |
| Closed companion | Render the specified offline indicator; prove passive polling creates no process if that is the contract. |
| First press | With a fake launcher/controller, prove whether only the app launches or a service command also occurs, as specified by the user. |
| Busy / double press | Multiple keys and local UI cannot start overlapping operations; pending acceptance remains reserved until consumed. |
| Stale controller | A busy flag cannot mask an error/expired heartbeat. Stale green is cleared. |
| Ambiguous response | Drop the acknowledgement after accepting a command; verify no automatic duplicate action. |
| Packaging | Put an unrelated sentinel file in the portable directory and prove it never appears in the release or uninstall inventory. |
| Update | Install/update into a temporary path with spaces/non-ASCII characters; preserve other plugins, settings and logs. |
| Failed update | Locked files, missing package assets and invalid destinations leave the old plugin intact. Test rollback separately from preflight rejection. |
| Device check | Run on the actual target host/device when available; disclose emulator-only coverage otherwise. |

Use private test controller identities so tests cannot attach to a live application. Replace service calls before launching the real UI/EXE in a fixture. Test migration/restart semantics using recorded fake operations; do not infer that a file named Test is harmless to run.

If sandboxed Named Pipe tests time out, inspect both client and server evidence before editing IPC or weakening ACLs. A server waiting without errors can indicate a sandbox namespace restriction. Use the available approval mechanism for a narrowly scoped local test outside the sandbox when justified; report any remaining limitation.

## Skill acceptance scenarios

When evaluating this skill itself, ask another agent for a short implementation approach for:

1. A HotSpot example described as “Stream Deck”: it must inspect the actual host rather than claim Elgato compatibility.
2. Independent animated keys during a reconnect: it must preserve context settings, suppress invisible animation, and avoid command replay.
3. A dirty portable release directory and a locked destination: it must exclude user files and retain the old plugin rather than force-kill the host.
4. Black means app closed; first press opens only the app: it must interpret black as state, not as a command to select a color, and send no service command on the first press.

Report actual deviations, not an invented failing baseline. These examples encode the traps this skill is intended to prevent; they do not impose a particular color scheme on other projects.
