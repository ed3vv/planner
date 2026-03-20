import SwiftUI

struct ClockView: View {
    @EnvironmentObject var clockStore: ClockStore
    @State private var showDurationPicker = false
    @State private var pickerHours   = 0
    @State private var pickerMinutes = 25

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            HStack(spacing: 0) {
                ForEach(ClockMode.allCases, id: \.self) { m in
                    Button { clockStore.setMode(m) } label: {
                        Text(m.rawValue)
                            .font(DS.T.label(11))
                            .foregroundStyle(clockStore.mode == m ? DS.C.textPrimary : DS.C.textMuted)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .overlay(alignment: .bottom) {
                                if clockStore.mode == m {
                                    Rectangle()
                                        .fill(DS.C.textPrimary.opacity(0.4))
                                        .frame(height: 1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, DS.Space.sm)

            DSDivider()

            Spacer()

            // Time display
            VStack(spacing: DS.Space.sm) {
                if clockStore.mode == .pomodoro {
                    Text(clockStore.pomodoroPhase.label.uppercased())
                        .font(DS.T.caption(10))
                        .foregroundStyle(phaseColor)
                        .tracking(1.5)
                }

                Text(clockStore.displayTime)
                    .font(.system(size: 52, weight: .thin, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(DS.C.textPrimary)
                    .contentTransition(.numericText(countsDown: clockStore.mode != .stopwatch))
                    .animation(.default, value: clockStore.displayTime)

                if clockStore.mode == .countdown && !clockStore.isRunning {
                    Button("set duration") { showDurationPicker = true }
                        .font(DS.T.caption(11))
                        .foregroundStyle(DS.C.textMuted)
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDurationPicker) {
                            DurationPickerView(hours: $pickerHours, minutes: $pickerMinutes) {
                                clockStore.setCountdownDuration(hours: pickerHours, minutes: pickerMinutes)
                                showDurationPicker = false
                            }
                            .colorScheme(.dark)
                        }
                }

                // Pomodoro dots
                if clockStore.mode == .pomodoro {
                    HStack(spacing: DS.Space.xs) {
                        ForEach(0..<4, id: \.self) { i in
                            Circle()
                                .fill(i < (clockStore.pomodoroSession - 1) % 4
                                      ? phaseColor : DS.C.textFaint)
                                .frame(width: 6, height: 6)
                        }
                        Text("round \(((clockStore.pomodoroSession - 1) / 4) + 1)")
                            .font(DS.T.caption(10))
                            .foregroundStyle(DS.C.textFaint)
                    }
                }
            }

            Spacer()

            // Controls
            HStack(spacing: DS.Space.sm) {
                DSButton(label: "Reset", style: .secondary) { clockStore.reset() }

                DSButton(
                    label: clockStore.isRunning ? "Pause" : "Start",
                    style: .primary,
                    size: .large
                ) {
                    clockStore.isRunning ? clockStore.pause() : clockStore.start()
                }

                if clockStore.mode == .pomodoro {
                    DSButton(label: "Skip", style: .secondary) { clockStore.skipPomodoroPhase() }
                } else {
                    Color.clear.frame(width: 52, height: 30)
                }
            }
            .padding(.bottom, DS.Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var phaseColor: Color {
        switch clockStore.pomodoroPhase {
        case .work:                 return DS.C.red
        case .shortBreak, .longBreak: return DS.C.green
        }
    }
}

struct DurationPickerView: View {
    @Binding var hours:   Int
    @Binding var minutes: Int
    var onSet: () -> Void

    var body: some View {
        VStack(spacing: DS.Space.md) {
            Text("Set Duration")
                .font(DS.T.heading(13))
                .foregroundStyle(DS.C.textPrimary)

            HStack(spacing: DS.Space.xs) {
                VStack(spacing: DS.Space.xs) {
                    Stepper("", value: $hours, in: 0...23).labelsHidden()
                    Text("\(hours) hr")
                        .font(DS.T.mono(28))
                        .foregroundStyle(DS.C.textPrimary)
                }
                Text(":").font(DS.T.mono(28)).foregroundStyle(DS.C.textMuted)
                VStack(spacing: DS.Space.xs) {
                    Stepper("", value: $minutes, in: 0...59).labelsHidden()
                    Text(String(format: "%02d min", minutes))
                        .font(DS.T.mono(28))
                        .foregroundStyle(DS.C.textPrimary)
                }
            }

            DSButton(label: "Set", action: onSet)
        }
        .padding(DS.Space.lg)
        .frame(width: 240)
        .background(DS.C.bg1)
    }
}
