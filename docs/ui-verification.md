# UI verification record

**English** · [简体中文](ui-verification.zh-CN.md)

This is a historical verification record, not a claim that every current interface has been retested. See [validation status](validation.md) for the latest summary.

Date: 2026-10-04. Environment: macOS 27, Xcode 27, native SwiftUI application.

| Area | Result and boundary |
| --- | --- |
| Build and unit tests | Build passed; 61 Swift Testing tests passed, covering localization parity, mapping persistence and rejected edits, inheritance, import/export, gestures and voice control. |
| Action selection | Desktop checks passed for searching, choosing presets and showing the current selection, including names and icons. |
| Shortcut recording | Recording Command+Return, saving with Return and cancelling with Escape passed. Cancellation preserved the prior binding. |
| Application profiles | Switching to Codex, overriding one action and restoring inheritance passed. The tested profile retained OK double press Command+Return and long press Shift+Return. |
| Global import/export | Export, preview and apply passed. Exports contained three gestures for all 12 non-voice buttons. |
| Application export | Codex output was parsed; overrides matched the interface and inherited actions were not expanded into overrides. |
| Errors and cancellation | Invalid JSON displayed an error without changing mappings. Cancelling Add App did not create an empty profile. |
| Audio settings | Editing, reverting and applying passed. Test tone was disabled with unapplied edits. Fn / Globe selection persisted across restart. |
| Test tone | BlackHole 2ch queueing, completion callback and completion indication passed. Audio content was not measured with an external recorder. |
| About | Sidebar and native app menu opened the same version and photo-credit window. |
| Windows | Main window fixed at 1180 × 800 pt, zoom disabled, minimize retained; Settings and About opened separately. |
| Reset | Isolated reset and import round-trip unit tests passed. Reset confirmation on real user settings was not UI-verified. |

These are desktop interaction checks on the built app. The XCTest UI runner timed out during initialization and is not counted as passing.

All physical buttons, photo gesture feedback, actual WeChat transcription and stop-on-release, sleep recovery, driver removal and reauthorization were not included in this end-to-end check. Hardware coverage is described in the [README](../README.md).

## Screenshot checks

- Audio device and shortcut controls shared a column start; device actions aligned to that column and the login toggle sat at the row end.
- Global/application profile controls and Codex enable/import/export controls did not overlap.
- The action picker showed the selected mute action; searching Return from the bottom of the list showed matching results. Custom shortcuts displayed the current chord.
- Recording and recorded-state screenshots were 960 × 580 px (480 × 290 pt), with stable button positions. Completion showed a save hint, Record Again returned to waiting, and cancellation preserved the prior TV long-press mute binding.
- Screenshot and interaction checks used English. Localization tests checked new English and Chinese strings.

## Fonts

- Page titles used Arvo Bold 32 pt; section titles used Arvo Regular 20 pt. Body text used Poppins 13 pt, compact tables 12 pt and secondary text 11 pt.
- Arvo/Poppins and their licenses were bundled and registered only within the app process. Chinese used matching PingFang SC weights; shortcut symbols used the system font.
- Tests verified all five font files, Chinese fallback names and both font-family licenses.
- English Voice, Global/Codex Mappings, action-picker and recorder windows were captured. Chinese fallback was tested automatically; full Chinese interface screenshots were not checked.

## Main window layout

- Both pages used 32 pt outer padding, a 48 pt title area and a bottom action area within the fixed 1180 × 800 pt window.
- The photo column was 220 pt wide. Photo and outlines shared a crop and scale; the feedback label had its own fixed height.
- Mapping values aligned with their column headings, without permanent cell fills or borders. Hover and remote-press feedback remained visible.
- Voice metrics used equal-width columns. Gain and mode shared the left card, whose bottom aligned with the photo panel.
- Sidebar status, navigation and footer entries shared consistent left padding and icon-column widths.
- English screenshots confirmed centered photos, card boundaries and all 13 buttons. Page/profile switching, opening and cancelling the action menu, and About navigation passed desktop checks. Physical-device regression was not repeated for the layout-only changes.
