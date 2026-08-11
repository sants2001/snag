// swift-tools-version:6.2
import PackageDescription

let package = Package(
	name: "KeyboardShortcuts",
	defaultLocalization: "en",
	platforms: [
		.macOS(.v10_15)
	],
	products: [
		.library(
			name: "KeyboardShortcuts",
			targets: [
				"KeyboardShortcuts"
			]
		)
	],
	targets: [
		.target(
			name: "KeyboardShortcuts",
			swiftSettings: [
				.defaultIsolation(MainActor.self),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances"),
				// Snag fork: Swift 6.3's EarlyPerfInliner recurses without bound on
				// `ObjectAssociation<T>.deinit` (Utilities.swift) and blows the stack, so
				// any -O or -Osize Release build of this package crashes swift-frontend.
				// Only this package is pinned to -Onone; the Cling target keeps -O, which
				// is what SearchEngine.swift needs for the sub-100ms search. Xcode cannot
				// scope a build setting into a *remote* SPM target, which is the only
				// reason this package is vendored at all. Drop the flag and go back to the
				// remote package once the compiler bug is fixed upstream.
				.unsafeFlags(["-Onone"])
			]
		),
		.testTarget(
			name: "KeyboardShortcutsTests",
			dependencies: [
				"KeyboardShortcuts"
			],
			swiftSettings: [
				.defaultIsolation(MainActor.self),
				.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
				.enableUpcomingFeature("InferIsolatedConformances")
			]
		)
	]
)
