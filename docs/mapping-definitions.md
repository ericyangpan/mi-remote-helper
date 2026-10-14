# Mapping definitions v2

**English** · [简体中文](mapping-definitions.zh-CN.md)

Mappings match the foreground application's Bundle ID exactly, not its display name or window title. Resolution order is an enabled application override, then Global, then the built-in default. Short, double and long presses resolve independently. Explicit `disabled` means no action; an omitted application entry inherits Global. Voice short press is configurable and exportable; its hold is fixed to dictation and its double press is configurable and defaults to no action.

Changing the foreground app cancels pending gestures. Releasing an old press does not send its action to the new app. Application mappings affect keyboard, media and mouse actions, not voice sessions.

## Usage

Select Global or an application on the Mappings page. Application actions may inherit Global or override it. Selecting a profile for editing does not activate it: it applies only when its app is in front and the profile is enabled. Profiles can be disabled, removed or reset to inheritance.

Add App reads the Bundle ID from a macOS `.app` bundle's Info.plist. The built-in Codex profile matches `com.openai.codex` and defaults Voice short press to Command-Option-I and inherits other actions. Importing a definition can add a profile for an app that is not installed.

Export saves the profile being edited. Global exports include the 12 ordinary buttons with all three gestures, plus Voice short and double presses; application exports contain only overrides. Exports omit profile enabled state, Bluetooth and audio devices, permissions, login items and application paths.

Import previews the scope and actions before applying. A global definition replaces all global mappings while preserving application profiles. An application definition replaces overrides for the same Bundle ID while preserving its enabled state. New profiles are enabled. An empty application definition inherits everything.

## File structure

```json
{
  "format": "mi-remote-helper.mapping",
  "version": 4,
  "name": "Codex",
  "scope": "application",
  "bundleIdentifier": "com.openai.codex",
  "shortPress": {},
  "longPress": {},
  "doublePress": {}
}
```

- `format` must be `mi-remote-helper.mapping`. Current `version` is integer `4`; v1/v2/v3 files are accepted and migrated. Older app versions reject v4 files.
- `name` is a nonblank display name of at most 80 characters, without control characters.
- `scope` is `global` or `application`. Global definitions omit `bundleIdentifier`; application definitions require it.
- Bundle IDs are case-sensitive, contain a period, start with an ASCII letter or digit, and contain at most 255 ASCII letters, digits, hyphens or periods.
- `shortPress`, `doublePress` and `longPress` map button identifiers to actions. All three fields are required in v4. Global short and double presses include all 13 buttons; long presses include the 12 ordinary buttons; application definitions may contain only overrides.
- Maximum size is 256 KiB. Unknown versions, buttons or actions, Voice long overrides and invalid shortcuts reject the entire import.
- Long press triggers at 0.5 seconds. If a double action is set, the first release starts a 0.3-second wait. A second short press within the window triggers double press; holding the second press triggers only long press. If double press has no action, short press triggers immediately on release.

`microphone` is accepted only in `shortPress`. Its global default is No Action. The Codex profile uses Command-Option-I; the Grok Bot profile uses Command-I. Configure Codex’s Focus Main Chat shortcut accordingly. Voice short press sends its mapping on release and never starts dictation; holding for 0.5 seconds starts dictation without sending the short action. Up to 0.5 seconds of initial PCM stays in memory while the gesture is undecided; a hold forwards it and a short press discards it.

Ordinary button identifiers: `power`, `up`, `left`, `ok`, `right`, `down`, `back`, `volume_up`, `home`, `volume_down`, `menu`, `tv`.

### Preset actions

```json
{ "type": "preset", "action": "pageUp" }
```

Allowed actions: `disabled`, `escape`, `returnKey`, `arrowUp`, `arrowDown`, `arrowLeft`, `arrowRight`, `homeKey`, `endKey`, `pageUp`, `pageDown`, `deleteBackward`, `clearText`, `showDesktop`, `contextMenu`, `appSwitcher`, `mouseRightClick`, `volumeUp`, `volumeDown`, `volumeMute`, `playPause`.

Both `contextMenu` and `mouseRightClick` send a right click at the current pointer location. Keyboard focus does not change that location. Apps that specifically require Shift-F10 can use a custom shortcut.

`clearText` sends Command-A followed by Delete only when the focused element is a text field, text area or combo box. It targets the app that was in front when triggered. Older versions that do not recognize this action reject the import.

### Custom shortcuts

```json
{
  "type": "shortcut",
  "chord": {
    "keyCode": 8,
    "keyLabel": "C",
    "modifiers": 1
  }
}
```

This example is Command-C. `keyCode` is a macOS physical virtual key code from 0 to 127. `keyLabel` is a nonempty display label of at most 24 characters and is not used for matching. Modifier bits are Command=1, Control=2, Option=4 and Shift=8; zero means no modifiers. Use the shortcut recorder to avoid entering key codes manually.

Definitions contain declarative data only; they do not load scripts, libraries or executable code. New action types or incompatible semantics require a format version change and an explicit migration.

## Examples and migration

- [Codex](../Examples/codex.mapping.json): all actions inherit Global, including the OK short, long and double presses.
- [Global defaults](../Examples/global-defaults.mapping.json): complete defaults, including OK long press Shift+Return and double press Command+Return, directional long presses and Back long press to clear text.

Legacy `buttonMappings.v1` and `buttonHoldMappings.v1` preferences remain the global mappings. Application profiles use `applicationMappings.v1`; global double presses use `buttonDoubleMappings.v1`. Migrated v1 global files set all double presses to no action; migrated v1 application files inherit all double presses.
