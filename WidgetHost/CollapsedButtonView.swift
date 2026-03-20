import SwiftUI

struct CollapsedButtonView: View {
    @ObservedObject var panelManager: PanelManager
    @ObservedObject var clockStore:   ClockStore

    var body: some View {
        Group {
            if clockStore.isRunning {
                HStack(spacing: 6) {
                    Image(systemName: timerIcon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(timerColor)
                    Text(clockStore.displayTime)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: clockStore.mode != .stopwatch))
                        .animation(.default, value: clockStore.displayTime)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.82))
                    .shadow(color: .black.opacity(0.5), radius: 8, y: 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { panelManager.toggle() }
    }

    private var timerIcon: String {
        switch clockStore.mode {
        case .stopwatch: return "stopwatch"
        case .countdown: return "timer"
        case .pomodoro:  return clockStore.pomodoroPhase == .work ? "timer" : "cup.and.saucer"
        }
    }

    private var timerColor: Color {
        switch clockStore.mode {
        case .stopwatch: return DS.C.accent
        case .countdown: return DS.C.orange
        case .pomodoro:  return clockStore.pomodoroPhase == .work ? DS.C.red : DS.C.green
        }
    }
}
