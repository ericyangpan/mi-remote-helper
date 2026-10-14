# Permissions and security boundaries

**English** · [简体中文](security.zh-CN.md)

## Required access

| Access | Purpose and boundary |
| --- | --- |
| Bluetooth | Requested when the user connects manually. Automatic connection at launch only runs with existing Bluetooth authorization and saved device/audio configuration. Receives remote microphone audio over BLE; the device model must be confirmed before voice capture. Discovery may scan advertisements without a service filter, but only candidate remotes are connected. |
| Accessibility | Requested through an explicit permission button. Sends dictation shortcuts and mapped keyboard/mouse actions. Clear Text inspects the foreground element's role, not its text contents. Voice short presses send the configured app-specific shortcut without reading focus or text. Long presses start dictation after the gesture threshold. |
| Input Monitoring | Needed for optional button mapping. The HID manager matches Xiaomi vendor/product IDs and accepts reports only from its selected remote. macOS grants a broader permission than this application uses; it is not a system-enforced per-device grant. |

Mappings default to off. Shortcut recording uses an app-local event monitor only while the recorder is open. Foreground application identifiers are used for profile selection and pending-gesture cancellation; no activity history is stored. Launch at login is enabled only through the user's toggle.

The app does not request physical microphone, camera, screen recording, Apple Events automation, Full Disk Access or administrator privileges. Its audio engine writes remote PCM to a virtual output device; the input method performs capture and recognition. Installing an external audio driver is a separate operation with its own permissions.

## Release policy

Release enables Hardened Runtime and disables base entitlement injection. The expected signed entitlement set is empty: no debugger attachment, JIT, unsigned executable memory, disabled library validation, App Groups or other runtime exceptions. Bluetooth is the only usage-description key. App Group auto-registration is disabled.

App Sandbox remains off because the cross-application accessibility functionality is incompatible with it; see [Apple's sandbox limitations](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox). An empty entitlement set does **not** sandbox the application or restrict ordinary file/network access. These boundaries also depend on implementation review and macOS privacy controls.

Run the artifact check on every Release build:

```sh
python3 scripts/check-release-security.py \
  'build/Distribution/Build/Products/Release/Mi Remote Helper.app' --distribution
```

Omit `--distribution` for a local ad-hoc Release. The check rejects unexpected entitlements or usage descriptions and requires arm64, a valid signature and Hardened Runtime. Distribution additionally requires Developer ID and a secure timestamp. It does not prove notarization, hardware behavior or absence of malicious code. See [release preparation](releasing.md).

## Data and side effects

- Audio and transcripts are neither recorded nor uploaded by this app. Input-method data handling is separate.
- Settings, selected device identifiers and mappings stay in local preferences. Mapping import/export accesses user-selected JSON files and validates their size and schema; it does not execute imported commands or scripts.
- System input locking is visible and configurable. It changes only the selected input, restores the previous input under ownership rules, and never changes playback output.
- Normal diagnostic messages use private OSLog fields. Debug voice-event diagnostics, including metadata logging, require `MI_REMOTE_VOICE_DIAGNOSTICS=1`; they are excluded from Release. The opt-in observer can see session key events, but logs only selected modifier/voice-key metadata, never text or audio. Those fields are private as well.
- The app has no privileged helper, shell-command execution, built-in updater or network upload client. External documentation and installer links open in the user's browser.

Existing macOS permissions are not revoked automatically by rebuilding. Users can review or revoke them in System Settings → Privacy & Security.

Low-battery alerts request notification permission when an alert is first needed. Notifications are local and contain only the remote battery percentage. Below 20% the battery icon is orange; below 10% it is red. Each warning tier alerts once, including across restarts and reconnects. Charging suppresses alerts and shows a green lightning bolt. Charging or recovery to at least 25% rearms alerts. Notification denial does not affect battery display or voice input.
