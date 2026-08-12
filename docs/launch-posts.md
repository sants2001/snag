# Launch posts

Drafts for Santino to review and post himself. Nothing here is posted automatically.

**Do not post until the DMG exists.** Requiring Xcode loses most of a Reddit audience at the
first line. Every draft below assumes a download link.

A note on tone throughout: these lead with the Cling credit rather than burying it. On Reddit,
being the person who volunteers "this is a fork, here is the original, go buy it if you want the
polished one" is a much stronger position than being the person who gets caught not saying it.

---

## r/macapps

Check the subreddit rules the day you post. They change, and some months require a flair or a
specific self-promotion format.

**Title**

> Snag: find any file on your Mac instantly. Free, open source, no telemetry.

**Body**

> I wanted a file finder that was faster than Spotlight for the one thing I do constantly: I
> half-remember a filename and want it open in under a second.
>
> Snag indexes every filename and path on the disk (2 million on mine) and searches them in about
> 40-100ms. Fuzzy, so partial and misspelled queries still hit. Summon with a hotkey from
> anywhere, hit Return, done.
>
> **It is a fork of [Cling](https://lowtechguys.com/cling) by Alin Panaitiu**, and the search
> engine is entirely his work. Cling is GPL-3 and excellent. He sells it for €12 with a free
> tier, and if you want a signed, notarised, supported build with auto-updates, buy his. Mine
> removes the paid tier because I think a tool like this should be free, and along the way I:
>
> - stripped out the payments and crash-reporting SDKs entirely, so they are not in the binary
> - replaced three dependencies that shipped with no licence file
> - made the terminal tool opt-in, because it listened on a port any local process could reach
> - wrote a SECURITY.md that documents what is stored and gives you the commands to verify it
>
> **What it does not do:** search inside file contents. Spotlight already does that well. Snag
> is names and paths only.
>
> Nothing leaves your machine. No account, no telemetry, no crash reporter. It stores an index of
> your filenames locally (~450MB), never file contents, and I would rather tell you that than
> have you find it.
>
> GPL-3, source and download: https://github.com/sants2001/snag

**Comment replies to have ready**

*"Why not just use Alfred/Raycast?"*
> They are launchers with file search attached; Snag is only file search, and it indexes system
> files, dotfiles and app-support paths that Spotlight's index skips. If Raycast already covers
> what you need, it is genuinely the better tool for you.

*"How is this different from Cling?"*
> Functionally, the paid tier is unlocked. Structurally, the payments and crash-reporting SDKs
> are not in the binary, three unlicensed dependencies are gone, and the terminal tool no longer
> listens by default. Cling is the original and still actively developed; I would not have built
> the search engine.

*"Isn't forking a paid app to remove the paywall a bit rude?"*
> It is a fair question. Cling is GPL-3, which grants the right explicitly, and I have kept the
> attribution prominent everywhere including in the app's About pane. I am not selling it and not
> competing for his customers; anyone who wants support or a signed build should buy Cling.

*"Is the index a privacy problem?"*
> Fair concern, and yes it is a complete map of your filenames. It is owner-only but not
> encrypted, so anyone with your unlocked disk can read it. `rm -rf ~/Library/Caches/com.santino.Snag`
> any time. SECURITY.md says this in the same words.

*"Why does it need Full Disk Access?"*
> To index outside your Home folder. Without it you get part of Home and nothing else; Desktop
> and Downloads go missing. That is also why you should build from source rather than trust a
> binary from a stranger, and the repo is set up for exactly that.

---

## Hacker News (Show HN)

Post around 9-11am ET on a weekday. Title format is strict.

**Title**

> Show HN: Snag – instant filename search for macOS, and what I learned forking a paid app

**Body**

> Snag finds any file on your Mac by name in about 40-100ms across 2M paths. It is a fork of
> Cling (GPL-3, €12, by Alin Panaitiu) with the paid tier removed.
>
> The interesting part was not the app, it was what forking it took. Cling is genuinely open
> source and yet does not compile from a clean checkout, for two independent reasons:
>
> 1. The Xcode project references a local SPM package at a path that exists only on the author's
>    machine.
> 2. Three functions the code calls live in a git-secret encrypted blob inside a dependency. The
>    anti-tamper layer is the part that stays closed.
>
> Then the dependency graph: three packages in it ship with no LICENSE file at all, making them
> all-rights-reserved, which blocks distributing any compiled binary. One of them wrapped a
> prebuilt Rust binary for gitignore matching. Replacing them meant reimplementing a hotkey
> layer, an FSEvents watcher, a memoization cache and a gitignore matcher.
>
> A few things I found along the way that might be useful to others:
>
> - Swift resolves unqualified names against the current module before imported ones, so you can
>   shadow a dependency's symbols and migrate off it incrementally with zero call-site edits.
>   Operators do not follow that rule and go ambiguous instead.
> - Magnet invokes target/action hotkeys via `perform(_:with:)`, an NSObject method. Passing a
>   plain Swift class compiles fine and silently does nothing at runtime, while Carbon reports
>   the registration succeeded.
> - macOS TCC keys permissions to a path *and* a code signature, so ad-hoc signed builds lose
>   their grants on every rebuild, and the Privacy pane keeps showing a name from a bundle that
>   no longer exists.
>
> Free, GPL-3: https://github.com/sants2001/snag

---

## X / Twitter

> Snag: find any file on your Mac instantly.
>
> 2M files indexed, ~50ms search, one hotkey.
>
> Free and open source. No telemetry, no account, nothing leaves your machine.
>
> A fork of Cling by @alinpanaitiu with the paid tier removed. His search engine, my de-paywalling.
>
> github.com/sants2001/snag

---

## Before posting

- [ ] DMG exists, is notarised, and opens on a Mac that has never seen Snag
- [ ] README screenshot is in place
- [ ] A stranger can go from the repo to a running app without asking a question
- [ ] Settings → Keyboard Shortcuts binds a new key correctly (still unverified)
- [ ] Decide whether to email Alin first. Not required by anything, but he will hear about it
      either way, and hearing it from you reads very differently to hearing it from a comment.
