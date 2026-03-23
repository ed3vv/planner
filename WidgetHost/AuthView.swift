import SwiftUI

/// Shown inside the Friends tab when the user hasn't set up their profile yet.
struct AuthView: View {
    @ObservedObject private var fb = FirebaseManager.shared

    @State private var displayName = ""
    @State private var username    = ""
    @State private var errorMsg    = ""
    @State private var isLoading   = false

    var canSubmit: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        username.trimmingCharacters(in: .whitespaces).count >= 3 &&
        !isLoading
    }

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()

            VStack(spacing: DS.Space.xs) {
                Text("Set up your profile")
                    .font(DS.T.heading(15))
                    .foregroundStyle(DS.C.textPrimary)
                Text("Friends will see your focus score and current app in real time.")
                    .font(DS.T.caption())
                    .foregroundStyle(DS.C.textFaint)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: DS.Space.sm) {
                // Display name
                HStack {
                    Text("Name")
                        .font(DS.T.caption())
                        .foregroundStyle(DS.C.textFaint)
                        .frame(width: 64, alignment: .leading)
                    TextField("Your name", text: $displayName)
                        .textFieldStyle(.plain)
                        .font(DS.T.body())
                        .foregroundStyle(DS.C.textPrimary)
                }
                .padding(DS.Space.sm)
                .background(DS.C.bg1)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Username
                HStack {
                    Text("@")
                        .font(DS.T.caption())
                        .foregroundStyle(DS.C.textFaint)
                        .frame(width: 64, alignment: .leading)
                    TextField("username", text: $username)
                        .textFieldStyle(.plain)
                        .font(DS.T.body())
                        .foregroundStyle(DS.C.textPrimary)
                        .onChange(of: username) { _, v in
                            username = v.lowercased()
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                        }
                }
                .padding(DS.Space.sm)
                .background(DS.C.bg1)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !errorMsg.isEmpty {
                Text(errorMsg)
                    .font(DS.T.caption())
                    .foregroundStyle(DS.C.red)
                    .multilineTextAlignment(.center)
            }

            DSButton(label: isLoading ? "Setting up…" : "Continue", style: .primary) {
                submit()
            }
            .disabled(!canSubmit)

            Spacer()
        }
        .padding(.horizontal, DS.Space.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard canSubmit else { return }
        isLoading = true; errorMsg = ""
        Task {
            do {
                try await fb.createProfile(username: username, displayName: displayName)
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}
