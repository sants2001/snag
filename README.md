# Snag

Instant fuzzy file search for macOS. A fork of [Cling](https://github.com/FuzzyIdeas/Cling) by
Alin Panaitiu, with the Pro licence gate removed and the parts that need the author's private
infrastructure taken out so it builds from a clean checkout.

**Cling is already GPL-3.0.** This fork exists to remove a paywall, not to open closed source.
If you want the polished, signed, notarised, auto-updating build with support behind it, buy
Cling for €12. It is a fair price and Alin wrote every line of the hard part.

## What changed

| Area | Upstream | Here |
|---|---|---|
| Pro gate | `proactive` flag from `LowtechPro`, driven by a Paddle licence | `let proactive = true` in `Cling/SnagUnlock.swift` |
| Licence checks | `validReq()` / `invalidReq3()` from a git-secret encrypted blob in `FuzzyIdeas/Lowtech` | Always-pass stubs in `Cling/SnagUnlock.swift` |
| Paddle | Vendor/product IDs set, `pro.checkProLicense()` on launch | Never configured; `PM.pro` left nil so Paddle is never instantiated |
| Sentry | Crash reports to upstream's Sentry project | DSN removed, never configured |
| Sparkle | `SUFeedURL` pointed at `files.lowtechguys.com` | Removed. Left in place it would replace this build with the gated one |
| Secure Send | `WarpDrop` package + `drop.lowtechguys.com` relay | Removed from the action registry; `SendManager.send` is a no-op |
| Identity | `com.lowtechguys.Cling` | `com.santino.Snag`, own IPC port and index cache |
| Signing | Developer ID, team `RDDXV84A73` | Ad-hoc, see `sign-local.sh` |

Everything Pro is on: System and Root scopes, external volume indexing, Quick Filters, folder
filters, scripts, and the result cap (upstream free tier stops at 500).

## Why the upstream repo does not build

Two pieces are published but not buildable, which is worth knowing before you fork it yourself:

1. `Cling.xcodeproj` references a **local** SPM package at
   `../../../Github/alin23/warpdrop/swift`. That path only exists on the author's machine and
   `WarpDrop` is not a public repo.
2. `validReq`, `invalidReq3` and `proactive` are referenced by `FuzzyClient.swift` but live in
   `enc.swift.secret`, a git-secret encrypted file in `FuzzyIdeas/Lowtech`. Nobody without the
   decryption key can compile them.

Both are handled here.

## Build

Needs Xcode 26+.

```bash
xcodebuild -project Cling.xcodeproj -scheme Cling -configuration Release -destination 'platform=macOS' build
```

```bash
./sign-local.sh && ditto ~/Library/Developer/Xcode/DerivedData/Cling-*/Build/Products/Release/Snag.app /Applications/Snag.app
```

`sign-local.sh` is required, not optional: Sparkle ships pre-signed with its own Team ID and
dyld refuses to load it into an ad-hoc-signed process until the whole bundle is re-signed.

Then grant **Full Disk Access** to `/Applications/Snag.app` in System Settings → Privacy &
Security. Without it the Home and Library scopes stall partway through indexing. Re-signing on
every rebuild changes the ad-hoc signature, so you may have to remove and re-add the grant.

## Usage

Snag has no Dock icon and no menu bar icon (`LSUIElement`), so the hotkey is the only way in.

| | |
|---|---|
| **Summon the window** | **Right Cmd + `/`** |
| Settings | `Cmd + ,` with the window focused |
| Appearance | Settings → Interface → *Window style*: Glassy, Vibrant, Opaque |
| Rebind the hotkey | Settings → Shortcuts |
| Window position | Drag it. The frame persists per scene and reopens where you left it |

Right Command is the trigger because macOS does not otherwise use it as a modifier. If nothing
happens on first try, grant Accessibility permission in System Settings → Privacy & Security →
Accessibility; global hotkeys need it.

Typing filters as you go. `.png icon` and `.pdf invoice` narrow by extension. `Up`/`Down` cycle
search history, `Tab` completes, `Cmd+Down` opens the full history.

There is also a CLI inside the bundle:

```bash
/Applications/Snag.app/Contents/SharedSupport/ClingCLI search kernel --count 20 --verbose
```

## Known ceilings

- `Vendor/KeyboardShortcuts` is a local copy pinned to `-Onone`. Swift 6.3's `EarlyPerfInliner`
  recurses without bound on its `ObjectAssociation<T>.deinit` and crashes the compiler at any
  optimisation level. The Cling target still builds at `-O`, so search speed is unaffected
  (~7ms across 905k entries). Un-vendor it once the compiler bug is fixed.
- `Paddle.framework` and `Sentry.framework` are still linked, because they are dependencies of
  `LowtechPro` and dropping them means forking `FuzzyIdeas/Lowtech`. Neither is ever
  initialised; the running app opens no network sockets.
- No auto-update. Rebuild to update.

## Licence

GPL-3.0, inherited from Cling. See `LICENSE`. Original work © Alin Panaitiu / The Low Tech Guys.

### What you may distribute

**This source repository: yes.** GPL-3.0 explicitly grants the right to distribute modified
versions, which is what this is. The repo contains modified Cling source and a vendored copy of
`KeyboardShortcuts` (MIT, licence included). It does not contain `Lowtech`; SPM fetches that from
GitHub on the building machine, so publishing this repo redistributes nothing proprietary.

**A compiled `.app` or `.dmg`: no, not yet.** `FuzzyIdeas/Lowtech` ships with **no licence file**
and is therefore all-rights-reserved. A built binary statically embeds its compiled code, which
is redistribution. Referencing a dependency is not the same as copying it, and only the binary
does the copying.

Unblocking binaries means getting Lowtech licensed. Given that every other FuzzyIdeas repo is
GPL-3.0 and that a GPL-3 app depending on an all-rights-reserved library is internally
inconsistent (upstream has the same problem distributing Cling), the omission reads as an
oversight rather than a decision. Asking upstream to add a `LICENSE` is the cheap fix.
