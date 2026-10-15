# Host protocol and Property Inspector

## Host selection

The `.sdPlugin` extension and similar WebSocket messages do not prove complete interoperability. Inspect the exact installed host and supplied example. An Elgato manifest/SDK template may have a different schema, runtime floor, packaging tool, controller vocabulary, or event wrapper from StreamDock.

Use the current official SDK for a new host-specific project; retain a working raw-WebSocket/C#/other runtime when extending an existing project unless a change is justified. Do not impose the Windows Framework implementation from one project on every plugin.

## Raw WebSocket integration

For compiled StreamDock plugins, the documented launch arguments include `-port`, `-pluginUUID`, `-registerEvent`, and `-info`. Register using the supplied event name and UUID after connecting to the supplied localhost port. Do not hard-code a discovered port or registration UUID.

In the browser Property Inspector, the documented callback is `connectElgatoStreamDeckSocket(port, uuid, registerEvent, info, actionInfo)` even for StreamDock. Parse initial settings from the action info; register the inspector with its supplied identity.

Validate these message shapes against the target host/SDK:

- Registration: `{ "event": "<supplied registration event>", "uuid": "<supplied UUID>" }`.
- Image update: `{ "event": "setImage", "context": "<key context>", "payload": { "image": "<supported image data or path>", "target": 0 } }` where supported; validate target semantics.
- Inspector persistence: `setSettings` with inspector context and a complete settings object; the host delivers `didReceiveSettings` to the plugin.
- Lifecycle: `willAppear` / `willDisappear`; input: typically `keyDown` or `keyUp`, but do not fire the same action on both without an explicit reason.

Some wrappers expose lifecycle methods prefixed with `_`. Do not infer that their wire events carry those prefixes. Normalize aliases only if target-host evidence warrants it. Check controller type before handling a key, dial, touch screen, or display-only action.

Support fragmented messages, bounded message sizes, one receive loop, serialized writes, and cancellation. Ignore unknown events safely. Treat contexts as opaque identifiers; a UUID identifies the action type, not a particular button.

## Persistence

The host owns per-key settings. Keep runtime connection/state fields out of persisted appearance settings. Apply defaults for older profiles; unknown icon IDs fall back to an available variant. Preserve unrelated settings when a slider changes. Global settings are for explicitly shared configuration, not a shortcut around context routing.

Opening the inspector should not reset settings, trigger a service action, or launch a companion app. Reconnect should repopulate current contexts from the host, without replaying earlier clicks.

## Official sources

Checked 2026-10-14; reopen the relevant current page when implementing protocol or SDK changes.

- [Elgato WebSocket plugin reference](https://docs.elgato.com/streamdeck/sdk/references/websocket/plugin/).
- [StreamDock registration and launch arguments](https://sdk.key123.vip/en/guide/registration.html).
- [StreamDock architecture and settings ownership](https://sdk.key123.vip/en/guide/architecture.html).

Treat these as separate protocol authorities. Testing one host is not proof of compatibility with the other.
