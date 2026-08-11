import Foundation

/// Unconditional feature unlock.
///
/// Cling, which Snag is forked from, gates System/Root scopes, external-volume indexing, Quick
/// Filters, folder filters, scripts and the >500 result cap behind a global `proactive` flag
/// that `LowtechPro` derives from the Paddle licence state.
///
/// Declaring `proactive` here shadows that global for the whole Snag target, because Swift
/// resolves an unqualified name against the current module before it looks at imported ones.
/// Every call site (FuzzyClient, ContentView, SettingsView) reads `true` without being edited,
/// which keeps future merges from upstream clean.
///
/// The licence machinery is gone rather than merely disarmed: `LowtechPro` and
/// `LowtechProSentry` are no longer linked, so neither Paddle nor Sentry exists in this binary.
let proactive = true

/// Gates whether a search may run at all.
///
/// `validReq` is called by `FuzzyClient` but is not present anywhere in Cling's public source
/// tree; it lives in `enc.swift.secret`, a git-secret encrypted blob inside `FuzzyIdeas/Lowtech`
/// that only its author can decrypt. That is why Cling does not compile from a clean checkout
/// even once the WarpDrop path is fixed. It is the anti-tamper layer, reimplemented here as
/// always-valid, which is the point of this fork.
func validReq() -> Bool { true }
