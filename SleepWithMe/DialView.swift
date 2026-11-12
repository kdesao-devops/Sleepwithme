import SwiftUI

/// Le cadran : un arc orange ouvert en bas, qu'on peut attraper et faire tourner.
struct DialView: View {
    @EnvironmentObject private var timer: SleepTimer

    private let size: CGFloat = 176
    private let lineWidth: CGFloat = 12
    /// L'arc couvre 270°, en partant d'en bas à gauche.
    private let sweep: Double = 270
    private let startAngle: Double = 135

    @LocalState private var dragOnRing: Bool?
    @LocalState private var dragHasMoved = false

    private var radius: CGFloat { (size - lineWidth) / 2 }

    var body: some View {
        ZStack {
            // Piste de fond.
            Circle()
                .trim(from: 0, to: sweep / 360)
                .stroke(.white.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(startAngle))
                .padding(lineWidth / 2)

            // Partie remplie.
            Circle()
                .trim(from: 0, to: max(0.001, timer.fraction) * sweep / 360)
                .stroke(
                    LinearGradient(
                        colors: [Theme.orange, Theme.amber],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(startAngle))
                .padding(lineWidth / 2)
                .shadow(color: Theme.orange.opacity(0.55), radius: 8)

            // Poignée au bout de l'arc.
            Circle()
                .fill(.white)
                .frame(width: lineWidth - 4, height: lineWidth - 4)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: radius)
                .rotationEffect(.degrees(startAngle + sweep * timer.fraction))

            // Chiffre central.
            VStack(spacing: -2) {
                Text("\(timer.displayValue)")
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(timer.displayValue)))
                    .animation(.snappy(duration: 0.25), value: timer.displayValue)
                Text(timer.displayUnit)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.82), value: timer.fraction)
        .contentShape(Circle())
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel("Durée")
        .accessibilityValue("\(timer.displayValue) \(timer.displayUnit)")
        .accessibilityAdjustableAction { direction in
            timer.nudge(direction == .increment ? 1 : -1)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let center = CGPoint(x: size / 2, y: size / 2)

                // On ne réagit que si le geste a commencé sur l'anneau, pas au centre.
                if dragOnRing == nil {
                    let distance = hypot(gesture.startLocation.x - center.x,
                                         gesture.startLocation.y - center.y)
                    dragOnRing = abs(distance - radius) < 26
                }
                guard dragOnRing == true else { return }

                // Angle du pointeur, ramené sur l'arc (0 = début, 270 = fin).
                let radians = Double(atan2(gesture.location.y - center.y,
                                           gesture.location.x - center.x))
                var angle = radians * 180 / Double.pi - startAngle
                angle = angle.truncatingRemainder(dividingBy: 360)
                if angle < 0 { angle += 360 }
                if angle > sweep {
                    // Dans l'ouverture du bas : on colle à l'extrémité la plus proche.
                    angle = angle < sweep + (360 - sweep) / 2 ? sweep : 0
                }
                let target = angle / sweep

                // Empêche de sauter d'un bout à l'autre en traversant l'ouverture.
                if dragHasMoved && abs(target - timer.fraction) > 0.5 { return }
                dragHasMoved = true

                timer.setMinutes(Int((target * Double(SleepTimer.maxMinutes)).rounded()))
            }
            .onEnded { _ in
                dragOnRing = nil
                dragHasMoved = false
            }
    }
}

/// Bouton rond en verre : un clic = un cran, un appui long défile puis accélère par 5.
struct RepeatButton: View {
    let systemImage: String
    let label: String
    let action: (_ coarse: Bool) -> Void

    @LocalState private var pressed = false
    @LocalState private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .bold))
            .frame(width: 46, height: 46)
            .contentShape(Circle())
            .glassEffect(.clear.tint(Theme.green.opacity(0.5)).interactive(), in: .circle)
            .scaleEffect(pressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        beginRepeating()
                    }
                    .onEnded { _ in
                        pressed = false
                        repeater?.cancel()
                        repeater = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(false) }
    }

    private func beginRepeating() {
        action(false)
        repeater = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            var count = 0
            while !Task.isCancelled {
                let coarse = count >= 10
                action(coarse)
                count += 1
                try? await Task.sleep(for: .milliseconds(coarse ? 170 : 90))
            }
        }
    }
}
