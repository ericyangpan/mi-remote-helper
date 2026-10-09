# Mi Remote Helper

**English** · [简体中文](README.zh-CN.md)

A native macOS app that turns the microphone on a Xiaomi Bluetooth Remote 2 Pro (RC003) into a virtual microphone for WeChat Input, with customizable remote buttons.

Hold the remote’s voice button to speak, then release it to finish. Speech recognition is handled by your input method; Mi Remote Helper delivers the audio and controls its shortcut.

## Features

- RC003 Bluetooth connection, model verification, ATVV negotiation and reconnection.
- 16 kHz microphone audio routed to an installed BlackHole or MiRemoteV virtual device.
- Left Control or Fn / Globe dictation control using your input method’s **tap to start, tap again to stop** mode.
- Gain adjustment, whisper mode, input level, battery status and a short test tone.
- Configurable short press, double press and long press for 12 buttons; the voice button stays dedicated to dictation.
- Global and per-app mappings, shortcut recording, and JSON import/export.
- Optional system input locking while connected, so headphone changes do not replace the selected virtual microphone.
- Menu bar operation, launch at login, English and Simplified Chinese interfaces.

## Requirements

- Apple Silicon Mac running macOS 14 or later. Intel is not supported. Current validation environment: macOS 27.0.1 and Xcode 27.
- Xiaomi Bluetooth Remote 2 Pro, model RC003. Connect only one supported remote at a time.
- [BlackHole 2ch](https://existential.audio/blackhole/), installed separately, or an existing compatible MiRemoteV device. No driver or installer is bundled.
- WeChat Input configured for voice input. Other dictation tools have not been validated.
- Xcode 27 for the documented source build. Older Xcode versions have not been validated with the Icon Composer assets and current project settings.

## Setup

1. Pair the remote in macOS Bluetooth settings.
2. Install BlackHole 2ch. Its installer may require administrator approval and a restart.
3. Build and open Mi Remote Helper using the instructions below.
4. In Settings, select the virtual microphone and choose Left Control or Fn / Globe to match WeChat Input. Configure that key in WeChat Input for **one tap to start, another tap to finish**, not hold-to-talk. Apply the settings.
5. Connect the remote and grant Bluetooth permission. Allow Accessibility for shortcut injection; button mappings additionally require Input Monitoring. If macOS requests an app restart, quit and reopen it.
6. Select the same virtual microphone in the input method if it offers a device selector. Otherwise it uses the system input.
7. Focus a text field, hold the remote’s voice button, speak, and release. The app taps the configured key on press and taps it again after queued audio drains on release.

The app does not automatically focus text fields. Fn and Left Control use the same toggle logic. Right Option and F20 remain available as native single-key mappings; their behavior depends on the receiving app.

**Keep System Input** is on by default and configurable under Settings → Audio. While connected, it keeps the selected virtual microphone as the system input and corrects changes caused by headphones. It never changes playback output. On disconnect or exit, it restores the prior input only if the app still owns the selection and that device is available. If restoration fails while the app remains open, it retries up to three times at one-second intervals and shows a failure message if necessary; retries respect later external input selections. App termination only attempts synchronous restoration. Turning this option off leaves system input selection to you; interrupted audio routing still recovers automatically.

Settings are applied explicitly and can be reverted before applying. Audio settings cannot change during capture. The test tone checks the virtual audio path without triggering dictation. The meter confirms received audio, not successful transcription.

Whisper mode disables audio smoothing and uses a separately saved gain, initially +6 dB. It is off by default and does not change WeChat’s recognition model; recognition improvements are not guaranteed.

## Button mappings

The remote has 13 buttons: Power, Voice, Up, Down, Left, Right, OK, Back, Home, Menu, Volume Up, Volume Down and TV. Voice is locked to dictation. All other buttons support independent short, double and long presses.

Enable mappings in the Mappings page after granting Accessibility and Input Monitoring. Select an action in the relevant cell; choosing a custom shortcut opens the recorder. Changes save automatically. Application mappings override individual global actions only while the matching app is in front; unspecified actions inherit Global. The built-in Codex profile starts with inheritance. See [example Codex overrides](Examples/codex.mapping.json).

| Default action | Button / gesture |
| --- | --- |
| Application switcher | Home, short press |
| Context menu at the mouse pointer | Menu, short press |
| Play / pause; mute | TV, short / long press |
| Home / End | Left / Right, long press |
| Page Up / Page Down | Up / Down, long press |
| Clear all text in the focused supported text field | Back, long press |

Long press triggers once after 0.5 seconds. Double press has a 0.3-second window; short press is delayed only when a double-press action is configured. Global double-press actions default to no action. Gestures are mutually exclusive, without automatic repeat. Home/End and paging behavior depends on the foreground app.

When the application switcher is open, Left/Right selects, OK/Home confirms, and Back/Power cancels. Voice cancels switching before starting dictation. The session also cancels on disconnect or after 30 seconds.

Definitions can be previewed before import and exported as JSON. Exports use v2; imports accept v1 and v2. See the [format documentation](docs/mapping-definitions.md) and [global defaults](Examples/global-defaults.mapping.json).

## Build and test

Open `MiRemoteHelper/MiRemoteHelper.xcodeproj`, select the `MiRemoteHelper` scheme and **My Mac**, or run:

```sh
xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData build

xcodebuild -project MiRemoteHelper/MiRemoteHelper.xcodeproj \
  -scheme MiRemoteHelper -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/TestDerivedData \
  -only-testing:MiRemoteHelperTests test
```

App: `build/DerivedData/Build/Products/Debug/Mi Remote Helper.app`.

### Signing

Public defaults in `MiRemoteHelper/Config/Build.xcconfig` use arm64 and ad-hoc signing, without an Apple developer account or a maintainer-specific team. This is suitable for building and inspecting the code. Ad-hoc rebuilds may invalidate Bluetooth, Accessibility or Input Monitoring grants; for daily use, sign consistently with your own development certificate.

```sh
cp MiRemoteHelper/Config/Signing.local.xcconfig.example \
   MiRemoteHelper/Config/Signing.local.xcconfig
```

Edit `DEVELOPMENT_TEAM` in the copied file to your team ID and install a matching Apple Development certificate in your Keychain. The optional local file is ignored by Git and applies to both the app and test targets. Keep using the same signing identity and app location. If the identity changes, reauthorize the app in System Settings. Never commit private keys, certificate exports or notarization credentials.

A Release build is **not automatically a notarized download**. Public binary distribution requires a separate Developer ID Application certificate, Hardened Runtime, notarization and stapling. Development certificates must not be presented as a public distribution signing solution. See [release preparation](docs/releasing.md).

## Privacy and permissions

Audio path: remote microphone → BLE ATVV → IMA ADPCM decoding → CoreAudio → virtual audio device → input method.

The app does not capture the Mac’s physical microphone, save recordings, perform transcription or upload audio. WeChat Input’s data handling follows its own settings and policies. Preferences and mappings are stored locally.

- **Bluetooth:** communicate with the remote and receive microphone audio.
- **Accessibility:** send configured shortcuts and inspect the focused element for supported text actions.
- **Input Monitoring:** read the matching remote’s HID reports for mappings. Normal mapping operation does not record other keyboards.

Debug-only keyboard diagnostics are opt-in with `MI_REMOTE_VOICE_DIAGNOSTICS=1`; the observer reads session key events and logs only modifier/voice-key metadata, never text or audio. Release builds omit these diagnostics. Normal protocol logs use private OSLog entries.

See [permissions and security boundaries](docs/security.md) for the least-privilege Release policy and artifact checks.

## Validation and limitations

Validation on 2026-10-08: 109 unit tests passed (110 runs including parameterized cases), including bundled license checks. An isolated public source snapshot also built as an arm64 Release with the default ad-hoc signature and no local signing configuration. Both the public build and the local development-signed build passed strict signature verification. Tests cover audio decoding, Bluetooth lifecycle, gesture resolution, mapping validation and restoration, localization, voice recovery and configurable input locking. See [validation status](docs/validation.md) and [performance measurements](docs/performance.md) for dated results and boundaries.

RC003 voice capture through BlackHole and WeChat’s stop-on-release behavior have been checked on hardware. This does not establish compatibility with every firmware, input method or macOS release. Automated XCTest UI tests have not passed on the validation machine because runner initialization timed out. Full hardware regression, including sleep and reconnect, remains separate from unit tests.

The main window is fixed at 1180 × 800 pt. Closing windows keeps the app in the menu bar. Login startup opens the app; the remote connection is started separately. RC003 firmware requires holding Voice to capture audio. Other models, multiple remotes and macros are unsupported.

A forced quit or crash cannot guarantee restoration of device key mappings. Disconnect and reconnect the remote if mappings remain suppressed. Avoid running competing remote-mapping tools.

## Icons and languages

The app artwork is in `Design/AppIcon.svg`, with its native Icon Composer document at `MiRemoteHelper/MiRemoteHelper/AppIcon.icon`. Menu bar SVGs are also in `Design/`. With Node.js and `sharp` installed or supplied through `NODE_PATH`, `node scripts/generate-app-icon.cjs` regenerates artwork. Normal Xcode builds use the committed assets and do not require Node.js.

The interface follows the macOS app language, falling back to English. Translations live in `Localizable.xcstrings` and `InfoPlist.xcstrings`; device names remain unchanged.


See the [documentation index](docs/README.md) for technical references and translations.

## License and acknowledgements

The software is licensed under **GPL-3.0-only**, aligned with Open Voice Bridge and its RC003 upstream. See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md) for sources, pinned revisions and modifications. The app includes both documents under About → Licenses & Acknowledgements. Public binary releases must provide their corresponding source code.

Arvo and Poppins are bundled under the SIL Open Font License 1.1, with their notices included. BlackHole is an external dependency and is not redistributed by this project.

### Product photo

The remote photo comes from [Xiaomi’s official product page](https://www.mi.com/xiaomi-bluetooth-remote-2-pro) and is retained to identify the compatible device and its buttons. Copyright belongs to Xiaomi and/or the respective rights holders. **The photo is excluded from GPL; no redistribution authorization has been documented.** Attribution and this notice do not replace permission.

If you are a rights holder and believe this use infringes your rights, please contact the maintainers through the repository’s issue tracker with the image location and evidence of ownership. We will remove the image if it infringes your rights. Request a private contact channel before sharing confidential documents. See [photo details](Design/RemoteProductPhoto.md).

This project is not affiliated with or endorsed by Xiaomi, WeChat or OpenAI. Product names identify compatibility only.
