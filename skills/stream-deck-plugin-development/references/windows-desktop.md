# Windows companion applications and installation

## Launch and IPC

Use a real Windows executable entry point when the user requests normal application launching; an EXE may wrap an existing PowerShell controller without rewriting the working service logic. Keep runtime files together and document whether distribution is portable-folder or single-file. Do not advertise a wrapper as self-contained if it needs sidecar scripts/DLLs.

For hidden helpers use an absolute executable path, correct argument quoting, explicit working directory, `UseShellExecute=false`, `CreateNoWindow=true`, and hidden window style where applicable. Do not construct shell commands from arbitrary paths. Background launch and user activation should be separate modes if their side effects differ.

A single-instance launcher should coordinate process creation and wait for controller readiness, not assume `Process.Start` means ready. Forward commands to the existing controller instead of creating duplicate tray processes. Use a bounded wait and clear failure result.

Named Pipes are an option for local control: scope the name to the intended user/session, restrict ACLs to the intended identity, bound reads/writes, and validate a small command vocabulary. Keep UI operations on the UI thread or its existing dispatch queue. Publish a heartbeat with state; reserve an accepted operation until it is consumed, so publication of an old idle snapshot cannot reopen the command gate.

Differentiate pipe connection absence from response timeout after connection. The first may mean the app is closed; the second means it may be alive but stalled. A lost acknowledgement is not evidence that a migration/restart did not begin.

## Framework / PowerShell constraints

If using the in-box .NET Framework compiler, compile against its actual C# language version. Older compilers reject `await` in catch/finally blocks; restructure cleanup or deliberately adopt a compatible build toolchain. Do not silently require a downloaded runtime for an offline installer.

Windows PowerShell 5.1 scripts containing non-ASCII text need an encoding it reads reliably (UTF-8 with BOM). Verify packaged copies, not just sources. Use the parser to catch syntax errors without executing the application.

An ICO may contain PNG-compressed frames that Framework `Icon.ToBitmap()` fails to decode. Validate the directory, frame offset and size; decode a suitable PNG frame directly when needed. Keep streams alive for APIs that require them and dispose GDI objects. Explicitly decide how transparent padding affects rounding and perceived size.

## Local plugin updates

Locate the host's actual plugins directory; HotSpot commonly uses `%APPDATA%/HotSpot/StreamDock/plugins`. This is a candidate, not a universal path. Let the user select the parent plugins directory when installation is part of the app; create only your own `.sdPlugin` child.

Validate the complete package before replacing anything. Reject a destination inside the source package and reparse-point traversal in recursive update/delete routines. Stage on the destination volume, check existing files for lock conflicts, rename the old directory to a rollback location, then promote the stage. If promotion fails, restore the old directory. Preserve a recoverable backup if cleanup fails and report it when relevant.

Do not touch unrelated plugins, host profile settings, or service data. A plugin update should preserve per-action settings by keeping its action identity stable. Companion-app updates should preserve user settings/logs and offer import when migrating to a different install directory. Uninstall only explicitly owned files.

If an executable is locked, explain that the host/app must close for replacement; do not forcibly terminate it. Development tests should use disposable directories, a private pipe, fake registry/shortcut locations, and fake service operations.
