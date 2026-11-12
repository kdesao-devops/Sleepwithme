import ServiceManagement
import SwiftUI

/// Le petit panneau en verre qui se déroule sous l'icône de la barre de menus.
struct PanelView: View {
    @EnvironmentObject private var timer: SleepTimer
    @LocalState private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 14) {
            header
            DialView()
            stepper
            presets
            actions
        }
        .padding(16)
        .frame(width: 272)
        // Transparence maximale : aucune teinte, aucun verre, fenêtre vidée.
        .background(ClearWindowBackground())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.alignment, trigger: timer.hapticTick)
        .animation(.snappy(duration: 0.3), value: timer.isRunning)
        .onAppear { timer.refreshPermission() }
    }

    // MARK: Sections

    private var header: some View {
        ZStack {
            Text("SleepWithMe")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            HStack {
                Spacer()
                Menu {
                    Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                    if timer.canPausePlayback {
                        Label("Mise en pause de la lecture autorisée", systemImage: "checkmark")
                    } else {
                        Button("Autoriser la mise en pause de la lecture…") {
                            openAccessibilitySettings()
                        }
                    }
                    Divider()
                    Button("Quitter SleepWithMe") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Options")
            }
        }
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 28) {
            RepeatButton(systemImage: "minus", label: "Moins") { coarse in
                timer.nudge(-1, coarse: coarse)
            }
            RepeatButton(systemImage: "plus", label: "Plus") { coarse in
                timer.nudge(1, coarse: coarse)
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 8) {
            ForEach([15, 30, 45, 60], id: \.self) { value in
                Button {
                    timer.setMinutes(value)
                } label: {
                    Text("\(value)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 34, height: 22)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .opacity(timer.currentMinutes == value ? 1 : 0.7)
                .accessibilityLabel("\(value) minutes")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if timer.isRunning {
            HStack(spacing: 10) {
                Button {
                    timer.cancel()
                } label: {
                    Text("Annuler")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(.glass)

                Button {
                    timer.extend(byMinutes: 5)
                } label: {
                    Text("+5 min")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(minHeight: 26)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.tint(Theme.violet.opacity(0.5)).interactive(), in: .capsule)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        } else {
            Button {
                timer.start()
            } label: {
                Text("Démarrer")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(minWidth: 140, minHeight: 26)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.tint(Theme.violet.opacity(0.5)).interactive(), in: .capsule)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
        }
    }

    /// Demande l'autorisation puis ouvre directement Réglages Système > Accessibilité,
    /// car macOS n'affiche sa fenêtre de demande qu'une seule fois.
    private func openAccessibilitySettings() {
        timer.requestPausePermissionIfNeeded()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Couleurs reprises de la capture d'origine.
enum Theme {
    static let nightTop = Color(red: 0.06, green: 0.08, blue: 0.24)
    static let nightBottom = Color(red: 0.04, green: 0.24, blue: 0.32)
    static let orange = Color(red: 1.0, green: 0.48, blue: 0.16)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.28)
    static let green = Color(red: 0.24, green: 0.72, blue: 0.42)
    static let violet = Color(red: 0.47, green: 0.25, blue: 0.95)
}

/// Rend la fenêtre du panneau entièrement transparente : retire le verre dessiné par macOS.
struct ClearWindowBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClearingView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ClearingView)?.clearWindow()
    }
}

/// Vide la fenêtre dès que le panneau s'y rattache, puis à chaque réouverture,
/// pour que la transparence soit visible immédiatement au clic sur l'icône.
final class ClearingView: NSView {
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        clearWindow()
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didResizeNotification,
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.clearWindow() }
            })
        }
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        clearWindow()
    }

    func clearWindow() {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        guard let root = window.contentView?.superview ?? window.contentView else { return }
        Self.hideMaterials(in: root)
    }

    private static func hideMaterials(in view: NSView) {
        for sub in view.subviews {
            if sub is NSVisualEffectView || sub is NSGlassEffectView {
                sub.isHidden = true
            } else {
                hideMaterials(in: sub)
            }
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
