# Snag

Instant fuzzy file search for macOS. Type a few characters, get the file, act on it without
leaving the keyboard. No account, no telemetry, nothing leaves your machine.

Snag is a fork of [Cling](https://github.com/FuzzyIdeas/Cling) by Alin Panaitiu, GPL-3.0. Cling
is excellent and the search engine is his work. This build removes the €12 licence gate, strips
the payments and crash-reporting SDKs out of the binary entirely, and replaces the dependencies
that stopped it compiling from a clean checkout.

## What it is, and is not

Faster than Finder at finding a file **by name**: around 40-100ms across 1.6 million paths,
against a Spotlight round trip.

It is not a Spotlight replacement. Spotlight indexes file *contents* and metadata; Snag indexes
names and paths only. "Where is that file called invoice" is what this is for. "Find documents
containing the word invoice" is not something it can do at all.

## Build

Needs Xcode 26 or newer.

```bash
xcodebuild -project Snag.xcodeproj -scheme Snag -configuration Release -destination 'platform=macOS' build
```

```bash
./sign-local.sh --install
```

`sign-local.sh` is required, not optional. Sparkle ships pre-signed with its own Team ID and dyld
refuses to load it into an ad-hoc-signed process until the whole bundle is re-signed inside-out.
`--install` also moves the app to `/Applications`, deletes the build-products copy and updates
LaunchServices, so exactly one bundle ever claims `com.santino.Snag`.

Then grant **Full Disk Access** to `/Applications/Snag.app` in System Settings → Privacy &
Security. Without it, the Home and Library scopes stall partway through indexing.

## Usage

Snag has no Dock icon and no menu bar icon (`LSUIElement`), so the hotkey is the only way in.

| | |
|---|---|
| **Summon the window** | **Right Cmd + `/`** |
| Settings | `Cmd + ,` with the window focused |
| Appearance | Settings → Style → *Window style*: Glassy, Vibrant, Opaque |
| Rebind the hotkey | Settings → Keyboard Shortcuts, or the first-run screen |
| Window position | Drag it. The frame persists and reopens where you left it |

Typing filters as you go. `.png icon` and `.pdf invoice` narrow by extension. `Up`/`Down` cycle
search history, `Tab` completes, `Cmd+Down` opens the full history.

Right Command is the trigger because macOS does not otherwise use it as a modifier, but other
apps have started claiming it (Claude's desktop app, among others). If it is taken, right Option
is usually free:

```bash
defaults write com.santino.Snag triggerKeys -array 5 && killall Snag
```

`triggerKeys` holds raw `TriggerKey` values: `0 lshift, 1 lctrl, 2 lalt, 3 lcmd, 4 rcmd, 5 ralt,
6 rctrl, 7 rshift`. If nothing happens at all, grant Accessibility in System Settings → Privacy &
Security; global hotkeys need it.

There is also a terminal tool, **off by default** for the reason described in
[SECURITY.md](SECURITY.md#the-local-ipc-surface-and-why-it-is-off-by-default). Turn it on in
Settings → Search, then:

```bash
/Applications/Snag.app/Contents/SharedSupport/SnagCLI search kernel --count 20 --verbose
```

## Security

Nothing leaves your machine, and the frameworks that could send something are not in the binary.
Full detail, with commands to verify each claim yourself, in **[SECURITY.md](SECURITY.md)**.

The one thing worth knowing up front: Snag stores an index of every **file name and path** on
your disk in `~/Library/Caches/com.santino.Snag` (~450 MB). Never file contents. It is
owner-only but unencrypted. `rm -rf` it any time; it rebuilds.

## What this fork changes

| Area | Cling | Snag |
|---|---|---|
| Pro gate | `proactive`, driven by a Paddle licence | `let proactive = true`; every feature on |
| Payments | Paddle linked and configured | Not linked; Paddle absent from the binary |
| Crash reports | Sentry, DSN configured | Not linked; Sentry absent from the binary |
| Auto-update | Sparkle against `files.lowtechguys.com` | No `SUFeedURL`, no update menu item |
| Terminal tool | Mach port always listening | Off by default, opt in |
| Secure Send | `WarpDrop` + `drop.lowtechguys.com` | Removed |
| Identity | `com.lowtechguys.Cling` | `com.santino.Snag`, own IPC port and index cache |
| Signing | Developer ID | Ad-hoc, see `sign-local.sh` |

Everything formerly behind the licence is on: System and Root scopes, external volume indexing,
Quick Filters, folder filters, scripts, and the result cap that upstream's free tier holds at 500.

## Dependencies

Every dependency is permissively licensed except one, which is the last thing standing between
this repo and distributable binaries. See [docs/independence-plan.md](docs/independence-plan.md).

| Package | Licence |
|---|---|
| Sauce, Magnet, Defaults, LaunchAtLogin, KeyboardShortcuts, ClopSDK | MIT |
| Sparkle, HighlighterSwift | MIT-style |
| swift-argument-parser | Apache-2.0 |
| **alin23/swift-ignore** | **none (all rights reserved)** |

`FuzzyIdeas/Lowtech` and `eonil/FSEvents`, both unlicensed, have been removed. Everything Snag
used from them now lives in `Snag/Kit/`: the hotkey layer on Magnet and Sauce, a native
`FSEventStream` watcher, memoization, Spotlight app discovery, and the path, string and view
conveniences the app is built on.

## Why Cling does not build from a clean checkout

Worth knowing if you plan to fork it yourself. Two blockers, neither documented upstream:

1. `Cling.xcodeproj` references a **local** SPM package at
   `../../../Github/alin23/warpdrop/swift`. That path exists only on the author's machine and
   `WarpDrop` is not a public repo, so package resolution fails before anything compiles.
2. `validReq`, `invalidReq3` and `proactive` are called by `FuzzyClient.swift` but exist nowhere
   in the public tree. They live in `enc.swift.secret`, a git-secret encrypted blob inside
   `FuzzyIdeas/Lowtech`. The anti-tamper layer is the part that stays closed.

Both are handled here.

## Known ceilings

- `Vendor/KeyboardShortcuts` is a local copy pinned to `-Onone`. Swift 6.3's `EarlyPerfInliner`
  recurses without bound on its `ObjectAssociation<T>.deinit` and crashes the compiler at `-O`
  and `-Osize`. Xcode cannot scope a build setting into a remote SPM target, hence the vendored
  copy. The Snag target still builds at `-O`, so search speed is unaffected.
- The IPC uses CFMessagePort, which cannot authenticate its peer. XPC is the right answer.
- No auto-update. Rebuild to update.
- The hotkey layer is new and has no test coverage. Verified by hand, not by CI.

## Licence

GPL-3.0, inherited from Cling. See [LICENSE](LICENSE). Original work © Alin Panaitiu / The Low
Tech Guys.

**You may distribute this source repository.** GPL-3.0 explicitly grants the right to distribute
modified versions, which is what this is. The repo contains no proprietary code; SPM fetches
dependencies on the building machine.

**Binaries are still blocked**, by exactly one package. `alin23/swift-ignore` ships with no
licence file and is therefore all-rights-reserved, and a compiled `.app` statically embeds it.
Replacing it means implementing gitignore matching in Swift, since it wraps a prebuilt Rust
binary. That is the last step.
