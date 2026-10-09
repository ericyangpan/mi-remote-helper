# Third-party notices

**English** · [Simplified Chinese translation](THIRD_PARTY_NOTICES.zh-CN.md)

## Open Voice Bridge

- Source: https://github.com/nijez/open-voice-bridge
- Revision: `1796b149f752ff2d2fa82fd818f8a5a2bc60802a`
- Copyright (C) 2026 Open Voice Bridge contributors.
- License: GPL-3.0-only; full text in `LICENSE`.

The ATVV codec, Bluetooth lifecycle, peripheral bridge, device profile, voice-control edge tracker and CoreAudio device catalog are adapted from Open Voice Bridge. The audio output routing and device-specific microphone-key mapping are derived from its implementation. RC003 button usages, report parsing, shortcut recording and keyboard/media event injection are also adapted from the same revision. The button reader tries exclusive device access and falls back to device-local UserKeyMapping suppression, without a global keyboard-event filter. Changes include a macOS-only Xcode application, RC003-only model confirmation, bounded audio buffering, selectable microphone key with left Control as default, connection timeout, input validation, and preservation of pre-start decoder synchronization.

Open Voice Bridge attributes its initial RC003 protocol adaptation to https://github.com/xxb26553663-star/remote-bridge-hub at `8a93f321ac71a602300c6cd77f7256fa4b63068e`, GPL-3.0-only. This attribution is retained. No upstream brand assets, Sparkle binaries or Windows components are included.

Mi Remote Helper is distributed under GPL-3.0-only.

## BlackHole

https://github.com/ExistentialAudio/BlackHole is an external virtual audio device, separately installed by the user. No BlackHole driver binary or installer is included in this repository. The application can use an installed BlackHole or MiRemoteV loopback device.

Xiaomi and WeChat names identify compatible hardware and software, not endorsement or affiliation.

## Fonts

- Arvo Regular and Bold: https://github.com/google/fonts/tree/main/ofl/arvo
- Poppins Regular, Medium and SemiBold: https://github.com/google/fonts/tree/main/ofl/poppins

These unmodified fonts are bundled under the SIL Open Font License 1.1. The full copyright notices and licenses are included in `MiRemoteHelper/MiRemoteHelper/Design/Fonts/Arvo-OFL.txt` and `Poppins-OFL.txt`, and copied into the application bundle. Fonts are registered only for the app process. Chinese text uses the macOS-provided PingFang SC family; keyboard shortcuts use the native macOS system font.

## RC003 product photo

- Source: [Xiaomi Bluetooth Remote 2 Pro product page](https://www.mi.com/xiaomi-bluetooth-remote-2-pro).
- Original image: https://cdn.cnbj1.fds.api.mi-img.com/product-images/xiaomi-bluetooth-remote-2-prob7e569/section-02_list1.jpg
- Copyright belongs to Xiaomi and/or the respective rights holders. This image is excluded from the software's GPL-3.0-only license. No redistribution permission has been documented; attribution and this notice do not grant that permission.
- The photo is included to identify the compatible remote and illustrate its physical buttons. This project is not affiliated with or endorsed by Xiaomi.
- If you are a rights holder and believe this use infringes your rights, please contact the maintainers through this repository's issue tracker with the image location and evidence of ownership. We will remove the image if it infringes your rights. Do not post confidential documents publicly; request a private contact channel first.


## Modification notice

Mi Remote Helper is a modified work based in part on Open Voice Bridge. As of 2026-10-08, its changes include the native macOS interface, per-application button mappings, toggle-based dictation control, audio recovery and configurable system input locking. Copyright © 2026 Mi Remote Helper contributors. The software is provided without warranty under GPL-3.0-only; the full license accompanies the source and application. Separately licensed assets retain the terms stated above.
