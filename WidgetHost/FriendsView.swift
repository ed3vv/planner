import SwiftUI

struct Friend: Identifiable {
    let id       = UUID()
    let name:       String
    let username:   String
    let focusScore: Double
    let isOnline:   Bool
    let currentApp: String?
}

struct FriendsView: View {
    @State private var friends: [Friend] = [
        Friend(name: "Alex",  username: "alex_dev",  focusScore: 82, isOnline: true,  currentApp: "Xcode"),
        Friend(name: "Jamie", username: "jamie23",   focusScore: 45, isOnline: true,  currentApp: "YouTube"),
        Friend(name: "Sam",   username: "samcodes",  focusScore: 91, isOnline: false, currentApp: nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend)
                        if friend.id != friends.last?.id { DSDivider() }
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }

            DSDivider()

            VStack(spacing: DS.Space.sm) {
                DSButton(label: "Sync with Friends", style: .secondary) {
                    // TODO: Supabase / Firebase sync
                }

                Text("Connect a backend to enable live sync")
                    .font(DS.T.caption())
                    .foregroundStyle(DS.C.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Space.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FriendRow: View {
    let friend: Friend
    @State private var isHovered = false

    var scoreColor: Color {
        friend.focusScore >= 70 ? DS.C.green :
        friend.focusScore >= 40 ? DS.C.orange : DS.C.red
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Avatar
            ZStack {
                Circle()
                    .fill(DS.C.bg2)
                    .frame(width: 32, height: 32)
                Text(String(friend.name.prefix(1)))
                    .font(DS.T.heading(14))
                    .foregroundStyle(DS.C.textPrimary)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(friend.isOnline ? DS.C.green : DS.C.textFaint)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DS.C.bg0, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name)
                    .font(DS.T.body())
                    .foregroundStyle(DS.C.textPrimary)

                Text(friend.currentApp.map { "on \($0)" } ?? "offline")
                    .font(DS.T.caption())
                    .foregroundStyle(DS.C.textMuted)
            }

            Spacer()

            Text("\(Int(friend.focusScore))%")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(scoreColor)
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .background(isHovered ? DS.C.bg2 : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .contentShape(Rectangle())
    }
}
