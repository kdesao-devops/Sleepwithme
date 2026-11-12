import SwiftUI

@main
struct SleepWithMeApp: App {
    @StateObject private var timer = SleepTimer()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(timer)
        } label: {
            MenuBarLabel(timer: timer)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Ce qui s'affiche dans la barre de menus : une lune, plus le temps restant pendant le décompte.
struct MenuBarLabel: View {
    @ObservedObject var timer: SleepTimer

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: timer.isRunning ? "moon.zzz.fill" : "moon.fill")
            if timer.isRunning {
                Text(timer.menuBarText)
                    .monospacedDigit()
            }
        }
    }
}
