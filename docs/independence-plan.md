# Removing the unlicensed dependencies

**Goal:** make Snag's binary legally distributable, which unblocks GitHub Releases, a DMG, a
Homebrew cask and Snag's own Sparkle update feed.

**Blocker:** exactly two dependencies ship with no licence file and are therefore
all-rights-reserved. A compiled `.app` statically embeds them, and that is redistribution.

| Package | Licence | Used by |
|---|---|---|
| `FuzzyIdeas/Lowtech` | **none** | 34 files (`import Lowtech`), 2 (`import LowtechIndie`) |
| `alin23/swift-ignore` | **none** | 3 files (`import Ignore`) |

Every other dependency is fine: ClopSDK, Magnet, Sauce, Defaults, KeyboardShortcuts,
LaunchAtLogin (MIT), swift-argument-parser (Apache-2.0), Sparkle and HighlighterSwift (MIT-style;
licence files read directly, GitHub just fails to classify them).

This does **not** make Snag stop being a fork of Cling. The search engine is Cling's GPL-3 code
and the attribution stays either way. Independent dependencies buy distribution rights, nothing
more.

## The one surprise

`Lowtech` is an umbrella that re-exports 18 packages. Dropping it also drops `Defaults`,
`Sparkle` and `LaunchAtLogin` out from under the app, which fails at module-resolution time with
errors that look unrelated to Lowtech. Those three must be added as **direct** SPM dependencies
in the same change, or nothing compiles.

The good news: Snag references none of the other 15 by name, so they leave with Lowtech.

## What has to be reimplemented

Roughly 20 symbols. Most are thin wrappers over AppKit and can go in `Snag/Kit/`. No new SPM
package is needed; this is a single app target.

### Trivial, an afternoon

| Symbol | What it is |
|---|---|
| `focus()` | `NSApp.activate` |
| `mainActor { }` | dispatch onto the main actor |
| `asyncNow { }` | `DispatchWorkItem` on a global queue |
| `pub(.key)` | Defaults change publisher, a couple of lines |
| `Repeater` | repeating `Timer` wrapper |
| `SWIFTUI_PREVIEW` | `ProcessInfo` environment check |
| `EnvState` | small `ObservableObject` holding recording state |
| `UM` | update manager holding an `SPUUpdater?` |

`WM` (window manager) and `AM` (appearance) are already local to `Snag/SnagApp.swift`.

### SwiftUI views, mechanical

`FlatButton`, `PaddedPopoverView`, and the `.heavy()` / `.round()` / `.semibold()` text helpers.
`SettingRow` and `DescriptiveToggle` are already local to `Snag/SettingsView.swift`.

### The real work

| Symbol | Why it is hard |
|---|---|
| `KM` / `KeysManager` | The global hotkey layer. Wraps Magnet for registration and Sauce for layout-independent key codes, and implements the right-Cmd style "trigger key" scheme that Snag's summon hotkey depends on. This is the app's primary interaction; it needs care. |
| `DynamicKey` | The key recorder UI on the welcome and Shortcuts screens. |
| `DirectionalModifierView` | The left/right modifier picker beside it. |
| `SauceKey`, `TriggerKey` | Key and modifier enums, `Defaults.Serializable`. `TriggerKey` raw values are **persisted** (`triggerKeys` is `[0,1,2,...]` in prefs), so the case order must be preserved exactly or every existing user's hotkey silently changes. |

`Ignore` implements gitignore pattern semantics for `.fsignore`. Well specified, mechanical, and
there are MIT alternatives worth checking before writing one.

## Suggested order

Each step ends buildable and committable.

1. Add `Defaults`, `Sparkle`, `LaunchAtLogin`, `Magnet`, `Sauce` as direct SPM dependencies
   while Lowtech is still present. Nothing breaks; the graph just stops being implicit.
2. Add `Snag/Kit/` with the trivial helpers. Delete `import Lowtech` from files that need only
   those, one at a time.
3. Port the SwiftUI views and text helpers.
4. Port `SauceKey` / `TriggerKey`, preserving raw values. Verify against a prefs dump before and
   after: `defaults read com.santino.Snag triggerKeys`.
5. Port `KM`, then `DynamicKey` and `DirectionalModifierView`. Test the summon hotkey and the
   recorder by hand; there is no test coverage here.
6. Replace `Ignore`. Verify by diffing indexed file counts before and after against the same
   `.fsignore`.
7. Replace `LowtechIndieAppDelegate` with a plain `NSApplicationDelegate` plus the Sparkle
   controller it was wrapping.
8. Drop `Lowtech`, `LowtechIndie` and `Ignore` from the project. Confirm with
   `otool -L` and by checking `Contents/Frameworks`.

## Then the update feed

Only possible after the above, since it serves binaries.

1. Generate an EdDSA key pair with Sparkle's `generate_keys`. The private key goes in the
   login keychain and **never** in the repo.
2. Put `SUPublicEDKey` and a `SUFeedURL` pointing at the appcast in `Snag/Info.plist`.
3. Host `appcast.xml` and the DMGs on GitHub Releases or GitHub Pages.
4. Restore a "Check for updates" menu item, removed in b5f5df1 because it could only fail.
5. Sign releases properly. Ad-hoc signing is fine for a local build but Gatekeeper will block a
   downloaded one, so shipping binaries realistically means a paid Apple Developer account for
   Developer ID signing and notarisation.

## Risks

- **`TriggerKey` raw values are persisted.** Reordering the enum silently rebinds every user's
  hotkey. Pin the raw values explicitly rather than relying on declaration order.
- **The hotkey layer has no tests.** Manual verification only: summon, rebind, restart, confirm
  it survives.
- **The index format is unchanged**, so `.idx` caches survive this work. Keep it that way; a
  format change forces every user into a full reindex.
- Ad-hoc signing already causes TCC grants to go stale on every rebuild. That gets worse during
  a refactor of this size, so expect to re-approve Full Disk Access repeatedly, or use
  `tccutil reset SystemPolicyAllFiles com.santino.Snag`.
