import Foundation

/// Snag fork: unconditional feature unlock.
///
/// Upstream Cling gates System/Root scopes, external-volume indexing, Quick Filters,
/// folder filters, scripts and the >500 result cap behind a global `proactive` flag
/// that LowtechPro derives from the Paddle licence state.
///
/// Declaring `proactive` here shadows that global for the whole Cling target, because
/// Swift resolves an unqualified name against the current module before it looks at
/// imported ones. Every call site (FuzzyClient, ContentView, SettingsView) reads `true`
/// with no edits of its own, so upstream merges stay clean.
///
/// The licence machinery itself is disarmed separately in ClingApp.swift by leaving
/// `PM.pro` nil, which keeps Paddle from ever initialising.
let proactive = true

// MARK: - Licence-validation stubs
//
// `validReq`, `invalidReq3` and `PRODUCTS` are referenced by FuzzyClient but are not present
// anywhere in the public source tree: they live in `enc.swift.secret`, a git-secret encrypted
// blob in FuzzyIdeas/Lowtech that only the author can decrypt. That is why upstream Cling does
// not compile from a clean checkout even after the WarpDrop path is fixed.
//
// They are the anti-tamper layer: `validReq()` gates whether a search is allowed to run at all,
// and `invalidReq3` is called at the top of indexing. Reimplemented here as unconditional
// always-valid, which is the whole point of this fork.

// `PRODUCTS` is already declared in ClingApp.swift as `[Any]` (the Paddle product, or empty).
// With `PM.pro` left nil it always evaluates to `[]`.

/// Upstream: revalidates the licence before an index pass. Here: always valid, never invalid.
@discardableResult
func invalidReq3(_: [Any], _: String?) -> Bool { false }

/// Upstream: gates `search()` on a valid licence/receipt. Here: always permitted.
func validReq() -> Bool { true }
