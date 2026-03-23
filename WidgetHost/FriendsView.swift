import SwiftUI

struct FriendsView: View {
    @ObservedObject private var fb = FirebaseManager.shared

    @State private var addingFriend  = false
    @State private var friendInput   = ""
    @State private var addError      = ""
    @State private var isAdding      = false
    @State private var authTimedOut  = false

    var body: some View {
        Group {
            if !fb.isSignedIn && !authTimedOut {
                // Signing in anonymously on launch — brief loading state
                VStack(spacing: DS.Space.md) {
                    ProgressView().progressViewStyle(.circular)
                    Text("Connecting…")
                        .font(DS.T.caption())
                        .foregroundStyle(DS.C.textFaint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // If Firebase isn't configured (missing plist), don't hang forever
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        if !fb.isSignedIn { authTimedOut = true }
                    }
                    Task { await fb.signInIfNeeded() }
                }
            } else if authTimedOut && !fb.isSignedIn {
                // Firebase not reachable — plist missing or misconfigured
                VStack(spacing: DS.Space.md) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 28))
                        .foregroundStyle(DS.C.textFaint)
                    Text("Firebase not connected")
                        .font(DS.T.body())
                        .foregroundStyle(DS.C.textPrimary)
                    Text("Make sure GoogleService-Info.plist is added to the FocusApp target.")
                        .font(DS.T.caption())
                        .foregroundStyle(DS.C.textFaint)
                        .multilineTextAlignment(.center)
                    DSButton(label: "Retry", style: .secondary) {
                        authTimedOut = false
                        Task { await fb.signInIfNeeded() }
                    }
                }
                .padding(DS.Space.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if fb.needsSetup {
                AuthView()
            } else {
                friendsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Friends list

    var friendsList: some View {
        VStack(spacing: 0) {
            // Your own status card
            if let profile = fb.profile {
                SelfRow(profile: profile)
                DSDivider()
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if fb.friends.isEmpty {
                        Text("No friends yet — add someone below.")
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.textFaint)
                            .padding(DS.Space.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(fb.friends.sorted { $0.isOnline && !$1.isOnline }) { friend in
                            FriendRow(friend: friend) {
                                fb.removeFriend(uid: friend.uid)
                            }
                            DSDivider()
                        }
                    }
                }
            }

            DSDivider()

            // Add friend
            VStack(spacing: DS.Space.sm) {
                if addingFriend {
                    HStack(spacing: DS.Space.sm) {
                        Text("@").foregroundStyle(DS.C.textFaint).font(DS.T.caption())
                        TextField("username", text: $friendInput)
                            .textFieldStyle(.plain)
                            .font(DS.T.body())
                            .foregroundStyle(DS.C.textPrimary)
                            .onSubmit { submitAddFriend() }

                        if isAdding {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.6)
                        } else {
                            Button { submitAddFriend() } label: {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(DS.C.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DS.Space.sm)
                    .background(DS.C.bg1)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if !addError.isEmpty {
                        Text(addError)
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.red)
                    }
                }

                DSButton(label: addingFriend ? "Cancel" : "Add Friend", style: .secondary) {
                    withAnimation { addingFriend.toggle(); friendInput = ""; addError = "" }
                }
            }
            .padding(DS.Space.md)
        }
    }

    private func submitAddFriend() {
        guard !friendInput.isEmpty, !isAdding else { return }
        isAdding = true; addError = ""
        Task {
            do {
                try await fb.addFriend(username: friendInput)
                friendInput = ""; addingFriend = false
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }
}

// MARK: - Self status row

struct SelfRow: View {
    let profile: UserProfile

    var scoreColor: Color {
        profile.focusScore >= 70 ? DS.C.green :
        profile.focusScore >= 40 ? DS.C.orange : DS.C.red
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            ZStack {
                Circle().fill(DS.C.accent.opacity(0.2)).frame(width: 32, height: 32)
                Text(String(profile.displayName.prefix(1)))
                    .font(DS.T.heading(14)).foregroundStyle(DS.C.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(profile.displayName).font(DS.T.body()).foregroundStyle(DS.C.textPrimary)
                    Text("(you)").font(DS.T.caption()).foregroundStyle(DS.C.textFaint)
                }
                Text("@\(profile.username)").font(DS.T.caption()).foregroundStyle(DS.C.textMuted)
            }
            Spacer()
            if profile.isOnline {
                Text("\(Int(profile.focusScore))%")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(scoreColor)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
    }
}

// MARK: - Friend row

struct FriendRow: View {
    let friend: UserProfile
    var onRemove: () -> Void
    @State private var isHovered = false

    var scoreColor: Color {
        friend.focusScore >= 70 ? DS.C.green :
        friend.focusScore >= 40 ? DS.C.orange : DS.C.red
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // Avatar + online dot
            ZStack {
                Circle().fill(DS.C.bg2).frame(width: 32, height: 32)
                Text(String(friend.displayName.prefix(1)))
                    .font(DS.T.heading(14)).foregroundStyle(DS.C.textPrimary)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(friend.isOnline ? DS.C.green : DS.C.textFaint)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(DS.C.bg0, lineWidth: 1.5))
                    .offset(x: 1, y: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(DS.T.body()).foregroundStyle(DS.C.textPrimary)
                Text(friend.currentApp.map { "on \($0)" } ?? "offline")
                    .font(DS.T.caption()).foregroundStyle(DS.C.textMuted)
            }

            Spacer()

            if friend.isOnline {
                Text("\(Int(friend.focusScore))%")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(scoreColor)
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .background(isHovered ? DS.C.bg2 : .clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove \(friend.displayName)", role: .destructive) { onRemove() }
        }
    }
}
