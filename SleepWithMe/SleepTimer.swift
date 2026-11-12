import AppKit
import Combine

/// Le cerveau de l'appli : durée choisie, décompte, fondu du volume et séquence de fin.
@MainActor
final class SleepTimer: ObservableObject {

    // MARK: Réglages

    /// Durée maximale réglable, en minutes.
    static let maxMinutes = 180
    /// Durée du fondu de volume avant la mise en veille, en secondes.
    static let fadeDuration: TimeInterval = 45

    private static let minutesKey = "lastMinutes"

    // MARK: État observable

    /// Durée choisie quand aucun décompte ne tourne (mémorisée entre deux lancements).
    @Published private(set) var minutes: Int = 30
    /// Heure de fin du décompte en cours, nil si rien ne tourne.
    @Published private(set) var endDate: Date?
    /// Secondes restantes pendant le décompte.
    @Published private(set) var remaining: TimeInterval = 0
    /// Incrémenté à chaque réglage manuel, pour déclencher le retour haptique.
    @Published private(set) var hapticTick = 0
    /// Vrai si macOS nous autorise à simuler la touche Lecture/Pause.
    @Published private(set) var canPausePlayback = CGPreflightPostEventAccess()

    var isRunning: Bool { endDate != nil }

    // MARK: État interne

    private var ticker: Timer?
    private var activity: NSObjectProtocol?
    private var volumeBeforeFade: Float?
    private var scrollAccumulator: CGFloat = 0

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.minutesKey)
        if saved > 0 { minutes = min(saved, Self.maxMinutes) }
        installEventMonitors()
    }

    // MARK: Valeurs affichées

    /// Valeur en minutes montrée par le cadran (durée choisie, ou temps restant arrondi au-dessus).
    var currentMinutes: Int {
        guard isRunning else { return minutes }
        return max(1, Int((remaining / 60).rounded(.up)))
    }

    /// Le gros chiffre au centre : des minutes, puis des secondes pendant la dernière minute.
    var displayValue: Int {
        if isRunning && remaining < 60 { return Int(remaining.rounded(.up)) }
        return currentMinutes
    }

    var displayUnit: String {
        if isRunning && remaining < 60 { return displayValue > 1 ? "secondes" : "seconde" }
        return currentMinutes > 1 ? "minutes" : "minute"
    }

    /// Remplissage de l'arc, de 0 à 1.
    var fraction: Double {
        let value = isRunning ? remaining / 60 : Double(minutes)
        return min(1, max(0, value / Double(Self.maxMinutes)))
    }

    var menuBarText: String {
        remaining < 60 ? "\(Int(remaining.rounded(.up))) s" : "\(currentMinutes) min"
    }

    // MARK: Réglage de la durée

    /// Fixe la durée. Pendant un décompte, cela déplace l'heure de fin.
    func setMinutes(_ value: Int) {
        let clamped = min(Self.maxMinutes, max(1, value))
        guard clamped != currentMinutes else { return }
        hapticTick += 1

        if isRunning {
            endDate = Date().addingTimeInterval(TimeInterval(clamped) * 60)
            restoreVolumeIfFading()
            tick()
        } else {
            minutes = clamped
            UserDefaults.standard.set(clamped, forKey: Self.minutesKey)
        }
    }

    /// Un cran vers le haut ou le bas. En mode « coarse », on saute au multiple de 5 suivant.
    func nudge(_ direction: Int, coarse: Bool = false) {
        let current = currentMinutes
        let next: Int
        if coarse {
            next = direction > 0 ? (current / 5 + 1) * 5 : ((current - 1) / 5) * 5
        } else {
            next = current + direction
        }
        setMinutes(next)
    }

    // MARK: Décompte

    func start() {
        guard !isRunning else { return }
        requestPausePermissionIfNeeded()

        remaining = TimeInterval(minutes) * 60
        endDate = Date().addingTimeInterval(remaining)

        // Empêche App Nap de ralentir le décompte en arrière-plan.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Minuteur de sommeil en cours"
        )

        let ticker = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    func cancel() {
        guard isRunning else { return }
        restoreVolumeIfFading(force: true)
        stopTicking()
    }

    func toggle() {
        if isRunning { cancel() } else { start() }
    }

    func extend(byMinutes extra: Int) {
        guard let endDate else { return }
        let cap = Date().addingTimeInterval(TimeInterval(Self.maxMinutes) * 60)
        self.endDate = min(endDate.addingTimeInterval(TimeInterval(extra) * 60), cap)
        hapticTick += 1
        restoreVolumeIfFading()
        tick()
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        remaining = 0
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func tick() {
        guard let endDate else { return }
        let left = endDate.timeIntervalSinceNow
        remaining = max(0, left)

        if left <= 0 {
            finish()
        } else if left <= Self.fadeDuration {
            if volumeBeforeFade == nil {
                volumeBeforeFade = AudioController.volume
            }
            if let original = volumeBeforeFade {
                AudioController.volume = original * Float(left / Self.fadeDuration)
            }
        }
    }

    /// Remet le volume d'origine si un fondu avait commencé. Sans `force`, on ne touche à rien
    /// tant que la nouvelle heure de fin reste dans la fenêtre de fondu.
    private func restoreVolumeIfFading(force: Bool = false) {
        guard let original = volumeBeforeFade else { return }
        if !force, let endDate, endDate.timeIntervalSinceNow <= Self.fadeDuration { return }
        AudioController.volume = original
        volumeBeforeFade = nil
    }

    /// Fin du décompte : silence, pause de la lecture, volume restauré, puis mise en veille.
    private func finish() {
        let original = volumeBeforeFade
        volumeBeforeFade = nil
        stopTicking()

        Task { @MainActor in
            if original != nil { AudioController.volume = 0 }

            // La touche Lecture/Pause est une bascule : on ne l'envoie que si du son sort vraiment,
            // sinon elle risquerait de lancer la lecture au lieu de l'arrêter.
            if AudioController.isOutputActive && CGPreflightPostEventAccess() {
                MediaKey.playPause()
            }

            try? await Task.sleep(for: .seconds(1))
            if let original { AudioController.volume = original }
            try? await Task.sleep(for: .milliseconds(300))
            SystemSleep.sleepNow()
        }
    }

    // MARK: Autorisation d'accessibilité

    func refreshPermission() {
        canPausePlayback = CGPreflightPostEventAccess()
    }

    /// Affiche la demande système (une seule fois) pour pouvoir simuler la touche Lecture/Pause.
    func requestPausePermissionIfNeeded() {
        if !CGPreflightPostEventAccess() {
            _ = CGRequestPostEventAccess()
        }
        refreshPermission()
    }

    // MARK: Clavier, défilement, veille manuelle

    private func installEventMonitors() {
        // Défilement trackpad / molette n'importe où sur le panneau.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard event.momentumPhase.isEmpty else { return nil }
            let delta = event.scrollingDeltaY
            let precise = event.hasPreciseScrollingDeltas
            let began = event.phase.contains(.began)
            MainActor.assumeIsolated {
                self?.handleScroll(delta: delta, precise: precise, began: began)
            }
            return nil
        }

        // Flèches pour régler (Maj = par 5), Entrée pour démarrer ou annuler.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let coarse = event.modifierFlags.contains(.shift)
            let direction: Int
            switch event.keyCode {
            case 126, 124: direction = 1      // haut, droite
            case 125, 123: direction = -1     // bas, gauche
            case 36, 76:                      // Entrée
                MainActor.assumeIsolated { self?.toggle() }
                return nil
            default:
                return event
            }
            MainActor.assumeIsolated { self?.nudge(direction, coarse: coarse) }
            return nil
        }

        // Si le Mac est mis en veille à la main pendant un décompte, on annule :
        // sinon il se rendormirait tout seul dès le réveil.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    private func handleScroll(delta: CGFloat, precise: Bool, began: Bool) {
        if began { scrollAccumulator = 0 }

        guard precise else {
            // Molette classique : un cran = une minute.
            if delta != 0 { nudge(delta > 0 ? 1 : -1) }
            return
        }

        // Trackpad : une minute tous les 7 points de défilement.
        scrollAccumulator += delta
        let stepSize: CGFloat = 7
        let steps = Int(scrollAccumulator / stepSize)
        if steps != 0 {
            scrollAccumulator -= CGFloat(steps) * stepSize
            setMinutes(currentMinutes + steps)
        }
    }
}
