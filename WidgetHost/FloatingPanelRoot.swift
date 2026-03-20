import SwiftUI

// The full expanded panel content shown in the content NSWindow.
struct ExpandedContentView: View {
    @ObservedObject var panelManager: PanelManager
    @ObservedObject var clockStore:   ClockStore
    @ObservedObject var appTracker:   AppTracker
    @ObservedObject var taskStore:    TaskStore

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                if clockStore.isRunning {
                    Image(systemName: timerIcon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(timerColor)
                }
                Text(clockStore.isRunning ? clockStore.displayTime
                     : appTracker.focusScore > 0 ? "\(Int(appTracker.focusScore))% focus"
                     : "Focus")
                    .font(.system(size: 13, weight: .semibold,
                                  design: clockStore.isRunning ? .monospaced : .default))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: clockStore.isRunning)

                Spacer()

                Button { panelManager.collapse() } label: {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle()
                .fill(DS.C.border)
                .frame(height: 1)

            AppMenuView()
                .environmentObject(appTracker)
                .environmentObject(taskStore)
                .environmentObject(clockStore)
                .environmentObject(panelManager)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.C.bg0.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.55), radius: 20, y: 8)
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
