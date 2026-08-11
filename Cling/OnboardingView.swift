import Defaults
import Lowtech
import SwiftUI
import System

// MARK: - WindowMode

enum WindowMode: String, CaseIterable {
    case utility = "Utility"
    case desktopApp = "Desktop App"
}

// MARK: - SnagMark

/// Snag's wordmark glyph, drawn rather than shipped as an asset so it scales cleanly and
/// tracks the accent colour. Same hook as the app icon (see `tools/make-icon.py`): long
/// shank, wide bend, barb rising to a point.
struct SnagMark: View {
    var size: CGFloat = 44

    var body: some View {
        Canvas { ctx, rect in
            let s = min(rect.width, rect.height)
            let w = s * 0.072
            let r = s * 0.190
            let shankX = s * 0.585
            let topY = s * 0.215
            let bendCY = s * 0.605
            let barbX = shankX - r
            let barbTop = bendCY - r * 1.02

            var path = Path()
            path.move(to: CGPoint(x: shankX, y: topY))
            path.addLine(to: CGPoint(x: shankX, y: bendCY))
            path.addArc(
                center: CGPoint(x: shankX - r, y: bendCY), radius: r,
                startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false
            )
            path.addLine(to: CGPoint(x: barbX, y: barbTop + w * 0.4))
            ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: w, lineCap: .round))

            var point = Path()
            point.move(to: CGPoint(x: barbX - w * 0.78, y: barbTop + w * 0.75))
            point.addLine(to: CGPoint(x: barbX + w * 0.78, y: barbTop + w * 0.75))
            point.addLine(to: CGPoint(x: barbX, y: barbTop - w * 1.15))
            point.closeSubpath()
            ctx.fill(point, with: .color(.white))
        }
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.22, green: 0.82, blue: 0.96), Color(red: 0.31, green: 0.27, blue: 0.90)],
                    startPoint: .top, endPoint: .bottom
                ))
        )
    }
}

// MARK: - OnboardingStep

/// A numbered row. The first run has exactly two things that must happen before Snag works
/// (disk access, a hotkey that isn't already taken) and one genuine behavioural fork
/// (window mode). Everything else upstream asks for here is reversible and lives in Settings.
private struct OnboardingStep<Content: View>: View {
    let number: Int
    let title: String
    var subtitle: String? = nil
    var done: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.accentColor : Color.primary.opacity(0.08))
                    .frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.snappy, value: done)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).heavy(13)
                    if let subtitle {
                        Text(subtitle)
                            .round(11, weight: .regular)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - OnboardingView

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 22) {
                OnboardingStep(
                    number: 1,
                    title: "Give Snag access to your disk",
                    subtitle: "Without it, Snag can only index part of your Home folder. It reads names and paths; file contents are never opened.",
                    done: fdaGranted
                ) {
                    Button(action: { FullDiskAccess.openSystemSettings() }) {
                        Label(
                            fdaGranted ? "Granted" : "Open System Settings",
                            systemImage: fdaGranted ? "checkmark.circle.fill" : "lock.shield"
                        )
                    }
                    .disabled(fdaGranted)
                }

                OnboardingStep(
                    number: 2,
                    title: "Pick a key to summon Snag",
                    subtitle: "Hold the modifier and tap the key from any app.",
                    done: enableGlobalHotkey
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            DirectionalModifierView(triggerKeys: $triggerKeys, showFnCaps: false)
                            Text("+").heavy(12)
                            DynamicKey(key: $showAppKey, recording: $env.recording, allowedKeys: .showAppKeyChoices)
                            Spacer()
                            Toggle("", isOn: $enableGlobalHotkey)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                        .opacity(enableGlobalHotkey ? 1 : 0.5)

                        // Spelling the chord out in words matters: the modifier picker shows
                        // eight near-identical glyphs, and left/right variants of the same key
                        // are indistinguishable at a glance.
                        if enableGlobalHotkey {
                            Text("Press **\(triggerKeys.readableStr) + \(showAppKey.character)** anywhere to summon Snag. If nothing happens, another app already owns that combination; pick a different one.")
                                .round(11, weight: .regular)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                OnboardingStep(
                    number: 3,
                    title: "Choose how Snag behaves",
                    done: true
                ) {
                    HStack(spacing: 10) {
                        windowModeButton(
                            mode: .utility,
                            icon: "bolt.fill",
                            headline: "Out of the way",
                            detail: "Appears on the hotkey, vanishes when you click away. No Dock icon."
                        )
                        windowModeButton(
                            mode: .desktopApp,
                            icon: "macwindow",
                            headline: "Always there",
                            detail: "Stays open like a normal app, with a Dock icon and Cmd-Tab."
                        )
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.top, 26)

            Spacer(minLength: 20)

            footer
        }
        .frame(width: 580)
        .frame(maxHeight: .infinity)
        .onAppear(perform: configureWindow)
        .onDisappear { fdaChecker = nil }
    }

    @EnvironmentObject private var env: EnvState
    @State private var selectedMode: WindowMode = .utility
    @State private var fdaGranted = false
    @State private var fdaChecker: Repeater?
    @State private var availableVolumes: [FilePath] = FuzzyClient.getVolumes()

    @Default(.enableGlobalHotkey) private var enableGlobalHotkey
    @Default(.showAppKey) private var showAppKey
    @Default(.triggerKeys) private var triggerKeys
    @Default(.showDockIcon) private var showDockIcon
    @Default(.keepWindowOpenWhenDefocused) private var keepWindowOpenWhenDefocused

    private var header: some View {
        VStack(spacing: 10) {
            SnagMark(size: 52)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
            VStack(spacing: 3) {
                Text("Snag").heavy(30)
                Text("Every file on your Mac, found as you type.")
                    .round(13, weight: .regular)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 34)
    }

    /// Live index count, so the first run shows the app doing its job instead of asking the
    /// user to take it on faith. It is already indexing while this window is open.
    @ViewBuilder
    private var indexStatus: some View {
        let count = FUZZY.indexedCount
        if count > 0 {
            HStack(spacing: 6) {
                // No symbolEffect here: .rotate needs macOS 15 and this target still ships
                // back to 14. The counter itself is the motion.
                Image(systemName: FUZZY.indexing ? "circle.dotted" : "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(FUZZY.indexing ? Color.secondary : Color.accentColor)
                Text("\(count.formatted()) files indexed")
                    .round(11, weight: .regular)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .animation(.default, value: count)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            indexStatus
            Button(action: getStarted) {
                Text("Start searching")
                    .heavy(14)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            Text("All of this can be changed later in Settings.")
                .round(10, weight: .regular)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 34)
        .padding(.bottom, 22)
    }

    private func configureWindow() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            window.level = .floating
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .clear
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
        fdaGranted = FullDiskAccess.isGranted
        fdaChecker = Repeater(every: 2) {
            guard FullDiskAccess.isGranted else { return }
            mainActor {
                fdaGranted = true
                fdaChecker = nil
            }
        }
    }

    @ViewBuilder
    private func windowModeButton(mode: WindowMode, icon: String, headline: String, detail: String) -> some View {
        let isSelected = selectedMode == mode

        Button(action: { selectedMode = mode }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text(headline).heavy(12)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                    }
                }
                Text(detail)
                    .round(10, weight: .regular)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .animation(.snappy(duration: 0.15), value: isSelected)
    }

    private func getStarted() {
        switch selectedMode {
        case .utility:
            showDockIcon = false
            keepWindowOpenWhenDefocused = false
            NSApp.setActivationPolicy(.accessory)
        case .desktopApp:
            showDockIcon = true
            keepWindowOpenWhenDefocused = true
            NSApp.setActivationPolicy(.regular)
        }

        // Upstream asked which external volumes to index on this screen. Every attached volume
        // is now indexed by default and can be turned off in Settings > Volumes, because the
        // question is meaningless before you have searched anything once.
        Defaults[.disabledVolumes] = []
        FUZZY.disabledVolumes = []
        FUZZY.externalVolumes = availableVolumes
        if !availableVolumes.isEmpty {
            FUZZY.indexVolumes(availableVolumes)
        }

        Defaults[.onboardingCompleted] = true

        if let onboardingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "onboarding" }) {
            onboardingWindow.close()
        }
        WM.open("main")
        AppDelegate.shared?.focusWindow()
        focus()
    }
}

#Preview {
    OnboardingView()
        .environmentObject(EnvState())
}
