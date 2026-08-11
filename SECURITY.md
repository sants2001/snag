# Security

Snag asks for Full Disk Access, the most powerful permission macOS grants. You should not take
any claim below on trust. Every one of them is checkable against the source or against a running
copy, and the commands to check them are included.

## What leaves your machine

Nothing.

Snag opens no network sockets and listens on no ports. There is no account, no sync, no
telemetry, no crash reporting, no licence check, and no update check.

```bash
# Should print 0.
lsof -nP -i -a -p "$(pgrep -f 'Snag.app/Contents/MacOS')" | wc -l
```

This is structural, not configuration. The frameworks that could phone home are not in the
binary at all:

```bash
ls /Applications/Snag.app/Contents/Frameworks   # Sparkle.framework, and nothing else
otool -L /Applications/Snag.app/Contents/MacOS/Snag | grep -ci -e paddle -e sentry   # 0
```

Upstream Cling links Paddle (payments) and Sentry (crash reporting) through `LowtechPro`. Snag
drops both SPM products, so there is no code path to disable and no setting to get wrong.

Sparkle remains because it is a dependency of `LowtechIndie`, which supplies the app delegate.
It cannot fetch anything: `SUFeedURL` is absent from `Info.plist`, so there is no appcast to
check. The "Check for updates" menu item is removed rather than left to fail silently. You
update by rebuilding.

## What is stored on disk

An index of **file names and paths**. Never file contents.

```
~/Library/Caches/com.santino.Snag/
  home.idx  library.idx  root.idx  applications.idx      (~450 MB for ~1.6M files)
```

The only calls that read file data in `SearchEngine.swift` are `loadBinaryIndex` and
`appendBinaryIndex`, both reading Snag's own index file. Your documents are opened only when you
select one and the preview pane renders it, and that content is never written anywhere.

Two honest caveats about that index:

- **It is a complete map of your filesystem.** Not contents, but every filename you have.
  Filenames alone can be sensitive.
- **It is not encrypted.** The containing directory is `drwx------`, so no other account on the
  machine can read it, but anyone with your unlocked disk can.

Delete it any time; it rebuilds on next launch.

```bash
rm -rf ~/Library/Caches/com.santino.Snag
```

## The local IPC surface, and why it is off by default

`SnagCLI` reaches the app through a `CFMessagePort` registered under a **global** mach name
(`com.santino.Snag.cli`, declared in `Snag/Snag.entitlements`). CFMessagePort gives the receiving
side no way to identify its peer: there is no audit token, so the handler cannot distinguish the
real `SnagCLI` from any other process that looks up the same name.

While that listener is running, **any process running as you can query the index** and read back
paths it may not be able to `stat` itself, because Snag has Full Disk Access and it does not.
That is a local privilege boundary worth taking seriously. Nothing about it is reachable from
another machine.

Upstream listens unconditionally. Snag ships the listener **off**, and registers the port only
if you turn on *Settings → Search → Allow the terminal tool to reach Snag*. Toggling it off
tears the port down immediately rather than at next launch.

```bash
# Should report that it cannot connect, unless you enabled it.
/Applications/Snag.app/Contents/SharedSupport/SnagCLI status
```

Fixing this properly means moving the IPC to XPC, which can check a peer's code-signing
requirement. That is the right long-term answer and it is not done yet.

## Permissions Snag asks for

| Permission | Why | If you decline |
|---|---|---|
| Full Disk Access | Index names and paths outside your Home folder | Home and Library scopes stall partway; the rest still works |
| Accessibility | Register the global summon hotkey | The hotkey does nothing; no other effect |

Snag is **not sandboxed**. It cannot be: an App Sandbox would defeat indexing the whole disk.

## Distribution and trust

Builds are **ad-hoc signed**, not notarised, because there is no Apple Developer account behind
this. Two consequences:

- Nobody should run a prebuilt Snag binary handed to them. Clone the repo and build it.
- Every rebuild mints a new signature, so macOS may drop TCC grants and you re-approve.
  `tccutil reset SystemPolicyAllFiles com.santino.Snag` clears a stale record.

Binary distribution is blocked for a separate reason: a compiled `.app` embeds `Lowtech`, which
ships with no licence file. See the README.

## Reporting something

Open an issue at https://github.com/sants2001/snag/issues. If you believe you have found
something that puts users' data at risk, say so in the title and skip the reproduction details
until we have somewhere private to move to.

## What has not been done

Stated plainly so nobody assumes otherwise:

- No third-party security audit. None of this code has been reviewed by anyone but its authors.
- The IPC still uses CFMessagePort rather than peer-authenticated XPC.
- The index is unencrypted at rest.
- Most of the code is inherited from Cling and was written for a signed, notarised, single-user
  distribution model. It has not been re-audited line by line against a hostile local process.
