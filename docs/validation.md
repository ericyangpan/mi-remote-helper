# Validation status

**English** · [简体中文](validation.zh-CN.md)

This document records verified results and their limits, not an exhaustive compatibility guarantee.

## Automated checks — 2026-10-08

Environment: Apple Silicon, macOS 27.0.1, Xcode 27.

- 109 unit tests passed (110 runs including parameterized cases), including bundled licenses, localization, audio decoding, Bluetooth lifecycle, gestures, mapping imports, restoration and voice recovery.
- An isolated public source snapshot built as an arm64 Release using default ad-hoc signing without a local signing configuration.
- Public and development-signed builds passed strict code signature verification.
- GPL and both English/Chinese third-party notices are bundled; tests cover language selection while retaining the original GPL text.
- Simulated input restoration tests cover transient and persistent failure, readback verification, bounded retries, reconnect cancellation, external selection and status updates after stopping.
- XCTest UI automation has not passed on the validation machine because runner initialization timed out.

## Recorded UI checks — 2026-10-04

The English interface was checked for action search and selection, shortcut recording and cancellation, profile inheritance and overrides, JSON import previews and exports, invalid input handling, audio-setting apply/revert, test-tone completion, window navigation and layout.

Font tests confirmed bundled Arvo/Poppins fonts and licenses, and Chinese fallback fonts. Full Chinese interface screenshots were not verified. Reset confirmation on real user settings was not verified; isolated reset logic was covered by unit tests.

These dated UI checks precede the latest licensing interface and audio settings. They are not a claim that all current UI paths have been retested.

## Hardware boundaries

RC003 connection, BlackHole audio delivery and WeChat stop-on-release behavior have prior hardware confirmation. Full coverage of every button, gesture, firmware, sleep/wake, driver removal, permission reset and headphones is not established by these results. Simulated recovery tests do not replace physical device acceptance.

See [performance measurements](performance.md) for the conditions behind CPU figures and [RC003 capabilities](rc003-capabilities-research.md) for hardware evidence limits.

Detailed historical results: [UI verification record](ui-verification.md).
