<div align="center">
  <img src="docs/images/icon.png" width="128" alt="Snag">
  <h1>Snag</h1>
  <p><strong>Find any file on your Mac, instantly.</strong></p>
</div>

Type a few characters, get the file, act on it without leaving the keyboard. Partial and
misspelled queries still match.

No account, no telemetry, nothing leaves your machine.

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

## Install

**Requires Xcode 26 or newer**, free from the Mac App Store. Not just the Command Line Tools;
Snag is a SwiftUI app and needs the full Xcode. First launch Xcode once so it finishes setting
itself up, then:

```bash
git clone https://github.com/sants2001/snag && cd snag && ./install.sh
```

Takes a few minutes. It builds, signs, installs to `/Applications` and launches Snag.

Then two things, both required:

**1. Grant Full Disk Access.** System Settings → Privacy & Security → Full Disk Access → **+** →
choose `/Applications/Snag.app`. Without it Snag can only see part of your Home folder, and
Desktop and Downloads will be missing from results.

**2. Press Right Command + `/`.** That is how you open Snag. There is no Dock icon and no menu
bar icon by design, so the hotkey is the only way in. If nothing happens, another app has
claimed that combination; see [Usage](#usage) for how to rebind.

The first index takes a few minutes and uses noticeable CPU. After that Snag sits idle until you
summon it.

### Updating

```bash
git pull && ./install.sh
```

### Uninstalling

```bash
rm -rf /Applications/Snag.app ~/Library/Caches/com.santino.Snag
defaults delete com.santino.Snag
```

Snag builds on your machine rather than shipping a download, on purpose. There is no Apple
Developer ID behind it, so a downloaded binary would be quarantined and refused by Gatekeeper
with a message that reads like file corruption. Building locally sidesteps that: the app is
ad-hoc signed by the machine that runs it. It also means nobody has to trust a stranger's binary
to run something that asks for Full Disk Access.

### Building by hand

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

## If Snag crashes

Snag has no crash reporter and sends nothing, so a crash on your machine is invisible to
everyone but you. Reporting it is the only way it gets fixed.

macOS saves the report locally. **Settings → About → Crash logs** reveals the newest one in
Finder, ready to drag into an issue. The button only appears if a report exists. Or find them
yourself:

```bash
open ~/Library/Logs/DiagnosticReports
```

Files are named `Snag-<date>.ips`. Attach the newest to
[a new issue](https://github.com/sants2001/snag/issues/new) along with what you were doing.
They contain a stack trace and your macOS version, no file contents and no personal data,
though the process list does name other running apps if that matters to you.

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

**Every dependency is permissively licensed.** See
[docs/independence-plan.md](docs/independence-plan.md) for how that was reached.

| Package | Licence |
|---|---|
| Sauce, Magnet, Defaults, LaunchAtLogin, KeyboardShortcuts, ClopSDK | MIT |
| Sparkle, HighlighterSwift | MIT-style |
| swift-argument-parser | Apache-2.0 |

Three all-rights-reserved packages were removed: `FuzzyIdeas/Lowtech`, `eonil/FSEvents` and
`alin23/swift-ignore`, the last of which wrapped a prebuilt Rust binary. Everything Snag used
from them now lives in `Snag/Kit/`: the hotkey layer on Magnet and Sauce, a native
`FSEventStream` watcher, gitignore matching, memoization, Spotlight app discovery, and the path,
string and view conveniences the app is built on.

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

**You may distribute this source repository**, and now the binaries too. GPL-3.0 grants the
right to distribute modified versions, and with every all-rights-reserved package removed there
is nothing proprietary left to embed.

What still stops a downloadable app is Gatekeeper, not licensing. Snag is ad-hoc signed, so a
downloaded build is quarantined and refused with a message that reads like file corruption.
Building locally via `install.sh` sidesteps that, and is a better security story anyway for
something that asks for Full Disk Access.

`release.sh` produces a signed, notarised, stapled DMG for anyone who does have a **Developer ID
Application** certificate. Note that is a different certificate from the **Apple Distribution**
one used for the App Store; having shipped an app to the store does not mean you have it. It is
free to create with an existing paid account.
