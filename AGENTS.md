# Repository guidance

This file applies to the whole repository. Maintain AGENTS.md in English only; do not create a translated copy.

## Scope and structure

- Native macOS Swift/SwiftUI app for Apple Silicon, macOS 14+. Use Xcode 27 for the documented build. Do not add Intel or other-platform support without an explicit request.
- `MiRemoteHelper/MiRemoteHelper/Remote/`: RC003 Bluetooth/ATVV transport, HID reports, gestures and key injection.
- `MiRemoteHelper/MiRemoteHelper/Audio/`: device discovery, audio output, metering and optional system input locking.
- `MiRemoteHelper/MiRemoteHelper/Model/`: settings, mapping definitions and session coordination.
- Views and design resources live under `MiRemoteHelper/MiRemoteHelper/`; unit and UI tests have separate sibling directories.
- Read the relevant code before changing it. Preserve unrelated working-tree changes; do not replace user settings with test defaults.

## Behavior to preserve

- Audio flows from the RC003 microphone through BLE ATVV and IMA ADPCM decoding to the selected virtual audio device. The input method performs transcription. Do not add recording, uploading or physical Mac microphone capture without an explicit feature request.
- For Left Control and Fn, remote press sends a complete start tap; release sends a complete end tap after queued audio drains. Both use the same toggle logic, not a held modifier. Preserve cancellation, timeout and stale-callback protection.
- Voice remains dedicated to dictation. Do not reintroduce automatic text-field focus or Codex-specific focus manipulation without an explicit request.
- Short, double and long presses are mutually exclusive. Preserve global defaults, per-app inheritance, import validation and format-version compatibility. Changing the foreground app cancels pending gestures.
- Limit HID reads and suppression to the supported remote. Preserve prior device mappings and retry failed restoration; do not modify unrelated keyboards.
- System input locking is configurable and targets the selected device UID, not a hardcoded device name. Never change system playback output. Restore the previous input only under the ownership and availability rules in `SystemInputLock`.
- Keep audio callbacks lightweight, bound buffering and avoid publishing unchanged UI state. Follow existing concurrency boundaries.

## Build and verification

Run from the repository root:

```sh
xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/AgentChecks build

xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/AgentChecks \
  -only-testing:MiRemoteHelperTests test
```

- Use appropriate checks for the change. Add regression coverage for changes to voice state, mapping restoration, gestures or audio recovery. Documentation-only edits need link and consistency checks, not an app rebuild.
- Build and test in a separate output directory; do not overwrite or restart the daily-use app without a reason within the user's request. Never interrupt active dictation to install or restart a build.
- Distinguish compilation, unit tests, UI automation and hardware checks in reports. Simulated recovery is not proof of real Bluetooth, headphones or input-method behavior. Do not claim an unrun or failed test passed.
- Public configuration uses ad-hoc signing. Keep personal signing overrides and credentials out of Git. Do not alter a user's signing identity or reset privacy permissions as a routine fix. See [release preparation](docs/releasing.md).
- Check Release artifacts with `python3 scripts/check-release-security.py <app-path>`; use `--distribution` for Developer ID builds. Preserve the empty Release entitlement allowlist and the [permission boundaries](docs/security.md). New privileges require a concrete feature need, not a speculative workaround.

## Interface and documentation

- Keep UI text concise and outcome-oriented; do not expose implementation reasoning or development history in the product.
- Localize user-facing strings in English and Simplified Chinese using the existing string catalogs. Keep permissions and error messages accurate.
- Project documentation is English-first. Every project Markdown document except `AGENTS.md` needs a matching `.zh-CN.md` translation with reciprocal language links. Update translated links and the [documentation index](docs/README.md) together.
- Document facts, supported behavior and dated validation boundaries. Do not include conversations, approval logs, temporary diagnostic notes or personal identifiers. Record development process only when explicitly requested.
- Preserve original license texts; explanatory translations do not replace them.

## Licensing and delivery

- Software is GPL-3.0-only. Retain upstream attribution and bundled licenses when adapting code or changing resources.
- Keep the Xiaomi photo's separate rights and removal notice. Do not imply that GPL grants permission for third-party assets.
- Never commit private keys, certificate exports, notarization credentials, recordings or device-specific captures containing personal information.
- Use Conventional Commits and split independent changes when a split is warranted. Do not publish, push or release without user authorization.
- Run `gh` and `wrangler` commands outside the sandbox, using the environment's approval mechanism when required.
