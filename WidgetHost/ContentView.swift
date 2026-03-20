import SwiftUI

enum AppTab: String, CaseIterable {
    case clock   = "Clock"
    case tasks   = "Tasks"
    case friends = "Friends"
    case stats   = "Stats"
}

struct AppMenuView: View {
    @State private var selectedTab: AppTab = .clock
    @EnvironmentObject var appTracker:   AppTracker
    @EnvironmentObject var taskStore:    TaskStore
    @EnvironmentObject var clockStore:   ClockStore
    @EnvironmentObject var panelManager: PanelManager

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — text only, underline indicator
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.rawValue)
                            .font(DS.T.label(11))
                            .foregroundStyle(selectedTab == tab ? DS.C.textPrimary : DS.C.textMuted)
                            .padding(.horizontal, DS.Space.md)
                            .padding(.vertical, DS.Space.sm)
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle()
                                        .fill(DS.C.textPrimary.opacity(0.5))
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

            Group {
                switch selectedTab {
                case .clock:   ClockView()
                case .tasks:   TasksView()
                case .friends: FriendsView()
                case .stats:   StatsView()
                }
            }
            .environmentObject(appTracker)
            .environmentObject(taskStore)
            .environmentObject(clockStore)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
