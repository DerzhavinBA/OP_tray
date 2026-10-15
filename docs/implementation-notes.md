# Desktop application and StreamDock plugin

Implemented the approved plan in the existing workspace. The repository had no HEAD commit and all original files were untracked; no worktree, initial commit, or unrelated Git changes were created.

## Decisions

- Retain Windows PowerShell 5.1/WinForms controller and WSL pipelines. Framework C# executables provide launch, plugin, and setup; no runtime download or Node dependency for users.
- The controller owns operation selection and exclusion. Local IPC is a newline-delimited command and JSON response on a SID-scoped named pipe with an explicit user ACL. Accepted activation is reserved before the UI consumes it. The launcher never retries an activation with an ambiguous result.
- `--background` never starts the stack; `--background --startup` respects the existing opt-in stack autostart setting. Both avoid migration during monitoring or login.
- StreamDock owns persistent per-action appearance settings. Package replacement does not touch user profiles. Background reconnects never resend activation.
- State mapping and TCP/HTTP health checks retain the original tray semantics. A controller heartbeat older than five seconds becomes Error. A missing pipe maps to Offline (black); plugin polling does not launch the controller. The first offline click opens only the controller. A subsequent click activates the stack.
- Version 1.1 adds classic/tile/minimal/orbit styles, four marker corners, glow and tile rounding. Orbit uses 24 frames at 8 FPS; status polling is separate from animation. A bounded image cache avoids repeatedly decoding and rendering identical frames. Hidden actions are removed from the paint list.
- PNG frames in the provided ICO are decoded directly, matching the existing tray workaround for .NET Framework's Icon.ToBitmap limitation.
- Setup imports an optional old settings JSON only if no destination settings exist. Same-folder upgrades retain logs/settings; old logs in a different directory are not moved. Uninstall preserves data and separately installed StreamDock packages.
- Installer payload and uninstall ownership list use explicit generated-file allowlists. User files found in a portable folder cannot enter the installer.

## Validation

Safe tests are in `tests/`; the old root `Test-Tray.ps1` remains an explicitly live WSL test.

- `Test-Desktop.ps1`: compilation, private pipe status/activation, operation exclusion, rendering at sizing extremes, package install/update, locked destination, invalid destination, unrelated plugin preservation, payload file ownership.
- `Test-TrayIntegration.ps1`: actual EXE and WinForms tray in a private fixture, fake WSL pipelines, start/restart-migrate, failure and closed-tray recovery.
- `Test-PluginDialog.ps1`: real dialog control interaction installs to selected folder and saves it.
- `Test-Setup.ps1`: real installer implementation with fake registry and relocated shortcut folders; import, update, lock failure, uninstall, user data preservation.
- `Test-Inspector.js`: settings UI persistence messages, independent contexts, live updates, reset, reopened settings.
- `Test-PluginProtocol.js`: actual plugin executable against a local WebSocket host and private fake controller; registration, rendering, settings, activation exclusion, error and connection recovery.

Named pipe tests require ordinary Windows process permissions; the restricted execution sandbox prevented connections even within the test process. They passed outside that sandbox. No test invokes real WSL, real migrations, or changes StreamDock profiles. Physical device verification and real WSL/migration smoke testing remain manual.

## Review

An independent code review identified stale-busy error priority, missing import from the prior VBS installation, and packaging of unrelated portable files. All three were corrected and covered by regression checks.

Protocol reference: https://sdk.key123.vip/en/guide/registration.html and https://sdk.key123.vip/en/guide/architecture.html.
