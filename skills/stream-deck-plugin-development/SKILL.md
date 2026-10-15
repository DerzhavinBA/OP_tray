---
name: stream-deck-plugin-development
description: Develop, debug, review, and package Elgato Stream Deck or HotSpot/Mirabox StreamDock plugins (.sdPlugin), including Property Inspector settings, dynamic key icons, animation, local application control, and plugin installation. Use for plugin code and behavior changes, not ordinary device setup, Steam Deck gaming, or unrelated icon illustration.
metadata:
  version: "1.0.0"
  scope: "personal"
---

# Stream Deck / StreamDock plugin development

Use the user's requested host and behavior. Do not silently equate StreamDock with Elgato Stream Deck or replace the established plugin runtime. This is a personal engineering skill, portable across Codex, Cursor, and Claude Code; no particular tool or additional skill is required.

## Establish the contract

Inspect the manifest, entry point, SDK dependencies, settings UI, rendering code, packaging scripts, and existing tests. An installed example is evidence of local host conventions, not permission to modify that example or reuse its identity/assets.

Record the target host/version, OS, action identity, runtime, supported controller types, and entry-point arguments. Resolve discoverable details from the project before asking the user. Read [protocol.md](references/protocol.md) when implementing registration, host messages, or settings; verify current official documentation for host-specific decisions.

Write a compact state/action table before changing behavior. Distinguish:

- Host connection, companion application availability, and managed service readiness.
- Passive monitoring, first launch, subsequent action, operation in progress, and failure.
- Reconnecting to the host versus retrying a user command.

**Interpret indicators as observations, not commands.** For example, if the user requests “app closed = black; first press opens only the app,” black is a rendered offline state. Do not send a command to select black, auto-launch during polling, start the service, or migrate on that first press. Once the app connects, display its actual service state. Preserve different semantics when explicitly requested.

## Runtime and settings

- Maintain action instances by host context, not action UUID alone. Appearance settings belong to each button unless the user requests global settings.
- Use host persistence for settings. Supply backward-compatible defaults, validate enums, clamp numerical ranges, and preserve unknown fields on UI edits. Reopening the inspector and restarting the host must retain settings.
- Keep the receive loop responsive during process launch, IPC, and rendering. Bound connection/read/write waits; serialize WebSocket sends and shut down tasks when the connection closes.
- Reserve long-running operations at the controller before acknowledging acceptance. Cover simultaneous presses from multiple keys and local application controls. Do not replay an activation when a response is lost; the operation may already be running.
- Re-register after reconnect and restore visible contexts from host events. Remove disappeared contexts; late settings events must not restart animation for an invisible key.
- Distinguish absent application from a connected but unresponsive application. Do not let `busy` conceal a stale/error status, or leave a green status after losing its source.
- Read [windows-desktop.md](references/windows-desktop.md) for Windows launchers, Named Pipes, Framework rendering, and local plugin installation.

## Visuals and animation

Expose requested customization directly in the Property Inspector with meaningful labels, ranges, live values, and defaults. Keep icon style, logo size, marker size, marker position, glow, and rounding independent where offered. Apply edits immediately to the selected key only.

Define marker coordinates relative to the key canvas, not logo dimensions. Preserve logo aspect ratio, reserve outline/glow margins, and provide contrast for dark markers. Specify whether rounding affects the logo tile or the whole key; clip the intended surface, including transparent source-image padding.

Offer a static option alongside animation. Verify the host's supported animation mechanism; do not assume GIF support. For generated frames, use a bounded rate (8 FPS / 24 frames is a starting point for a subtle three-second orbit, not a host requirement). Separate status polling from animation, cache a bounded set of rendered frames, suppress unchanged static images, and stop painting invisible/disconnected contexts. Avoid flashing designs; preview motion should respect reduced-motion preferences.

Inspect actual output at minimum/default/maximum sizes and all marker positions. A CSS inspector preview does not prove that the hardware receives the same rendered image.

## Packaging and installation

Build from a clean staging area or explicit product-file allowlist. Never package a whole working portable directory: it may contain user settings, logs, tokens, or personal files. Use the same ownership inventory for uninstall.

Validate the manifest, executable entry point, dependencies, image references, and inspector assets. Use a distinct reverse-DNS action identity; preserve identity across updates to keep existing button settings.

For installation, inspect the intended destination and replace only this plugin. Reject source/destination overlap and unsafe linked paths in recursive operations. Stage the complete package, detect locked files before replacement, retain a rollback copy until replacement succeeds, and preserve host profiles. Report permission/lock errors clearly; do not forcibly kill the host or request elevation merely to work around an in-use plugin. A user-selected folder is preferable to a hard-coded profile path.

Respect the existing authorization for installation or deployment. Shipping code, installing into a live host, restarting the host, and operating a real external service are distinct actions; perform only those within the request. Do not introduce an extra approval ritual for already-authorized work.

## Verification and delivery

Use [testing.md](references/testing.md) to choose relevant regression scenarios. Prefer a fake host WebSocket and isolated fake controller for destructive or expensive service actions. Test the built executable, not only helpers.

Before delivery, re-read the requested behavior table and check it against actual results: correct host, per-key persistence, disappearance/reconnection, operation exclusion, lifecycle semantics, rendered output, package ownership, and rollback. State which checks passed and which remain unverified, especially physical hardware and real-service operations. Never present an emulator result as device verification.

Deliver the built package or installer with concise update steps. If users must install through a companion app or restart the host, say so. Do not claim the installed copy changed when only build output changed.
