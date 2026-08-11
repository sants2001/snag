# Snag

Instant fuzzy file search for macOS. Type a few characters, get the file, act on it without
leaving the keyboard. No account, no telemetry, nothing leaves your machine.

Snag is a fork of [Cling](https://github.com/FuzzyIdeas/Cling) by Alin Panaitiu, GPL-3.0. Cling
is excellent and the search engine is his work. This build removes the €12 licence gate, drops
the payments and crash-reporting SDKs entirely, and fixes the two things that stop the published
repo from compiling. If you want a signed, notarised, auto-updating build with support behind
it, buy Cling.

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

`triggerKeys` holds raw values in Lowtech's `TriggerKey` order: `0 lshift, 1 lctrl, 2 lalt,
3 lcmd, 4 rcmd, 5 ralt, 6 rctrl, 7 rshift`. If nothing happens at all, grant Accessibility in
System Settings → Privacy & Security; global hotkeys need it.

There is also a terminal tool, **off by default** for the reason described in
[SECURITY.md](SECURITY.md#the-local-ipc-surface-and-why-it-is-off-by-default). Turn it on in
Settings → Search, then:

```bash
/Applications/Snag.app/Contents/SharedSupport/SnagCLI search kernel --count 20 --verbose
```

## Security

Short version: nothing leaves your machine, and the frameworks that could send something are not
in the binary. Full detail, with commands to verify each claim yourself, in
**[SECURITY.md](SECURITY.md)**.

The one thing worth knowing up front: Snag stores an index of every **file name and path** on
your disk in `~/Library/Caches/com.santino.Snag` (~450 MB). Never file contents. It is
owner-only but unencrypted. `rm -rf` it any time; it rebuilds.

## What this fork changes

| Area | Cling | Snag |
|---|---|---|
| Pro gate | `proactive`, driven by a Paddle licence | `let proactive = true`; every feature on |
| Payments | Paddle linked and configured | `LowtechPro` not linked; Paddle absent from the binary |
| Crash reports | Sentry, DSN configured | `LowtechProSentry` not linked; Sentry absent from the binary |
| Auto-update | Sparkle against `files.lowtechguys.com` | No `SUFeedURL`, no update menu item |
| Terminal tool | Mach port always listening | Off by default, opt in per [SECURITY.md](SECURITY.md) |
| Secure Send | `WarpDrop` + `drop.lowtechguys.com` | Removed |
| Identity | `com.lowtechguys.Cling` | `com.santino.Snag`, own IPC port and index cache |
| Signing | Developer ID | Ad-hoc, see `sign-local.sh` |

Everything formerly behind the licence is on: System and Root scopes, external volume indexing,
Quick Filters, folder filters, scripts, and the result cap that upstream's free tier holds at 500.

## Why Cling does not build from a clean checkout

Worth knowing if you plan to fork it yourself. Two independent blockers, neither documented
upstream:

1. `Cling.xcodeproj` references a **local** SPM package at
   `../../../Github/alin23/warpdrop/swift`. That path exists only on the author's machine and
   `WarpDrop` is not a public repo, so package resolution fails before anything compiles.
2. `validReq`, `invalidReq3` and `proactive` are called by `FuzzyClient.swift` but exist nowhere
   in the public tree. They live in `enc.swift.secret`, a git-secret encrypted blob inside
   `FuzzyIdeas/Lowtech`. The anti-tamper layer is the part that stays closed.

Both are handled here: the Send feature that needed WarpDrop is removed, and the licence checks
are reimplemented as always-pass in `Snag/SnagUnlock.swift`.

## Known ceilings

- `Vendor/KeyboardShortcuts` is a local copy pinned to `-Onone`. Swift 6.3's `EarlyPerfInliner`
  recurses without bound on its `ObjectAssociation<T>.deinit` and crashes the compiler at `-O`
  and `-Osize`. Xcode cannot scope a build setting into a remote SPM target, hence the vendored
  copy. The Snag target still builds at `-O`, so search speed is unaffected (39-95ms warm across
  1.6M entries). Un-vendor once the compiler bug is fixed.
- Sparkle is still linked, as a dependency of `LowtechIndie`. It has no feed to check.
- The IPC uses CFMessagePort, which cannot authenticate its peer. XPC is the right answer.
- No auto-update. Rebuild to update.

## Licence

GPL-3.0, inherited from Cling. See [LICENSE](LICENSE). Original work © Alin Panaitiu / The Low
Tech Guys.

**You may distribute this source repository.** GPL-3.0 explicitly grants the right to distribute
modified versions, which is what this is. The repo contains modified Cling source and a vendored
copy of `KeyboardShortcuts` (MIT, licence included). It does not contain `Lowtech`; SPM fetches
that on the building machine, so publishing this repo redistributes nothing proprietary.

**You may not distribute a compiled `.app` or `.dmg`.** `FuzzyIdeas/Lowtech` ships with no
licence file and is therefore all-rights-reserved. A built binary statically embeds its compiled
code, which is redistribution. Referencing a dependency is not the same as copying it; only the
binary copies it.

Unblocking binary releases means getting Lowtech licensed. Every other FuzzyIdeas repo is
GPL-3.0, and a GPL-3 app depending on an all-rights-reserved library is internally inconsistent
(upstream has the same problem distributing Cling), so the omission reads as an oversight.
