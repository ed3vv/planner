import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Models

struct UserProfile: Identifiable {
    var id: String { uid }
    var uid: String
    var username: String
    var displayName: String
    var focusScore: Double
    var currentApp: String?
    var isOnline: Bool
    var friendUIDs: [String]

    init(uid: String, username: String, displayName: String,
         focusScore: Double = 0, currentApp: String? = nil,
         isOnline: Bool = false, friendUIDs: [String] = []) {
        self.uid = uid; self.username = username; self.displayName = displayName
        self.focusScore = focusScore; self.currentApp = currentApp
        self.isOnline = isOnline; self.friendUIDs = friendUIDs
    }

    init?(from dict: [String: Any], uid: String) {
        guard let username    = dict["username"]    as? String,
              let displayName = dict["displayName"] as? String else { return nil }
        self.uid         = uid
        self.username    = username
        self.displayName = displayName
        self.focusScore  = dict["focusScore"]  as? Double ?? 0
        self.currentApp  = dict["currentApp"]  as? String
        self.isOnline    = dict["isOnline"]    as? Bool   ?? false
        self.friendUIDs  = dict["friendUIDs"]  as? [String] ?? []
    }

    var toDict: [String: Any] {
        var d: [String: Any] = [
            "uid": uid, "username": username, "displayName": displayName,
            "focusScore": focusScore, "isOnline": isOnline, "friendUIDs": friendUIDs
        ]
        if let app = currentApp { d["currentApp"] = app }
        return d
    }
}

enum FocusAppError: LocalizedError {
    case usernameTaken, userNotFound, notAuthenticated, unknown(String)
    var errorDescription: String? {
        switch self {
        case .usernameTaken:    return "That username is already taken."
        case .userNotFound:     return "No user found with that username."
        case .notAuthenticated: return "Please sign in first."
        case .unknown(let m):  return m
        }
    }
}

// MARK: - FirebaseManager

@MainActor
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()

    @Published var authUser: FirebaseAuth.User? = nil
    @Published var profile: UserProfile?        = nil
    @Published var isSignedIn  = false
    @Published var needsSetup  = false   // signed in but no username yet
    @Published var friends: [UserProfile] = []
    @Published var isLoadingFriends = false

    private let db = Firestore.firestore()
    private var profileListener: ListenerRegistration?
    private var friendListeners: [String: ListenerRegistration] = [:]

    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.authUser   = user
                self?.isSignedIn = user != nil
                if let user = user {
                    await self?.loadProfile(uid: user.uid)
                } else {
                    self?.profile = nil; self?.needsSetup = false; self?.friends = []
                }
            }
        }
    }

    // MARK: - Auth

    /// Called at app launch — silently signs in anonymously so Firebase is always ready.
    func signInIfNeeded() async {
        guard authUser == nil else { return }
        do {
            let result = try await Auth.auth().signInAnonymously()
            print("[Firebase] ✅ Signed in anonymously:", result.user.uid)
        } catch {
            print("[Firebase] ❌ Sign in failed:", error.localizedDescription)
        }
    }

    // MARK: - Profile setup

    func createProfile(username: String, displayName: String) async throws {
        guard let uid = authUser?.uid else { throw FocusAppError.notAuthenticated }
        let uname = username.trimmingCharacters(in: .whitespaces).lowercased()
        guard uname.count >= 3 else { throw FocusAppError.unknown("Username must be at least 3 characters.") }

        // Enforce uniqueness
        let snap = try await db.collection("usernames").document(uname).getDocument()
        if snap.exists { throw FocusAppError.usernameTaken }

        let p = UserProfile(uid: uid, username: uname,
                            displayName: displayName.trimmingCharacters(in: .whitespaces))
        let batch = db.batch()
        batch.setData(p.toDict, forDocument: db.collection("users").document(uid))
        batch.setData(["uid": uid], forDocument: db.collection("usernames").document(uname))
        try await batch.commit()

        profile = p
        needsSetup = false
        startProfileListener(uid: uid)
    }

    // MARK: - Presence  (called from AppTracker)

    func updatePresence(focusScore: Double, currentApp: String?, isOnline: Bool) {
        guard let uid = authUser?.uid, profile != nil else { return }
        var data: [String: Any] = [
            "focusScore": focusScore,
            "isOnline":   isOnline,
            "lastSeen":   FieldValue.serverTimestamp()
        ]
        data["currentApp"] = currentApp ?? FieldValue.delete()
        db.collection("users").document(uid).updateData(data)
    }

    // MARK: - Stats sync  (called from AppTracker)

    func syncDailyRecord(_ record: DailyRecord) {
        guard let uid = authUser?.uid, profile != nil else { return }
        let data: [String: Any] = [
            "focusScore":         record.focusScore,
            "productiveSeconds":  record.productiveSeconds,
            "distractingSeconds": record.distractingSeconds,
            "totalSeconds":       record.totalSeconds,
            "sessionCount":       record.sessionCount,
            "updatedAt":          FieldValue.serverTimestamp()
        ]
        db.collection("users").document(uid)
          .collection("stats").document(record.dayKey)
          .setData(data, merge: true)
    }

    // MARK: - Task sync  (called from TaskStore)

    func syncTask(_ task: TodoItem) {
        guard let uid = authUser?.uid, profile != nil else { return }
        var data: [String: Any] = [
            "id":          task.id.uuidString,
            "title":       task.title,
            "isCompleted": task.isCompleted,
            "createdAt":   Timestamp(date: task.createdAt)
        ]
        if let tag = task.tag { data["tag"] = tag }
        db.collection("users").document(uid)
          .collection("tasks").document(task.id.uuidString)
          .setData(data, merge: true)
    }

    func deleteTask(id: UUID) {
        guard let uid = authUser?.uid, profile != nil else { return }
        db.collection("users").document(uid)
          .collection("tasks").document(id.uuidString)
          .delete()
    }

    func loadTasksFromCloud() async -> [TodoItem] {
        guard let uid = authUser?.uid, profile != nil else { return [] }
        guard let snap = try? await db.collection("users").document(uid)
                                      .collection("tasks").getDocuments() else { return [] }
        return snap.documents.compactMap { doc -> TodoItem? in
            let d = doc.data()
            guard let idStr = d["id"]    as? String, let id = UUID(uuidString: idStr),
                  let title = d["title"] as? String else { return nil }
            return TodoItem(id: id, title: title,
                            isCompleted: d["isCompleted"] as? Bool ?? false,
                            createdAt:   (d["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                            tag:         d["tag"] as? String)
        }
    }

    // MARK: - Friends

    func addFriend(username: String) async throws {
        guard let uid = authUser?.uid else { throw FocusAppError.notAuthenticated }
        let uname = username.trimmingCharacters(in: .whitespaces).lowercased()

        let snap = try await db.collection("usernames").document(uname).getDocument()
        guard let friendUID = snap.data()?["uid"] as? String, friendUID != uid else {
            throw FocusAppError.userNotFound
        }
        try await db.collection("users").document(uid).updateData([
            "friendUIDs": FieldValue.arrayUnion([friendUID])
        ])
        // profileListener will fire → updateFriendListeners will add the new friend
    }

    func removeFriend(uid friendUID: String) {
        guard let uid = authUser?.uid else { return }
        db.collection("users").document(uid).updateData([
            "friendUIDs": FieldValue.arrayRemove([friendUID])
        ])
        friendListeners[friendUID]?.remove()
        friendListeners.removeValue(forKey: friendUID)
        friends.removeAll { $0.uid == friendUID }
    }

    // MARK: - Private

    private func loadProfile(uid: String) async {
        let doc = try? await db.collection("users").document(uid).getDocument()
        if let data = doc?.data(), let p = UserProfile(from: data, uid: uid) {
            profile = p; needsSetup = false
            startProfileListener(uid: uid)
            updateFriendListeners(friendUIDs: p.friendUIDs)
        } else {
            needsSetup = true
            startProfileListener(uid: uid)
        }
    }

    private func startProfileListener(uid: String) {
        profileListener?.remove()
        profileListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, _ in
                guard let data = snap?.data(),
                      let p = UserProfile(from: data, uid: uid) else { return }
                Task { @MainActor [weak self] in
                    self?.profile = p
                    self?.needsSetup = false
                    self?.updateFriendListeners(friendUIDs: p.friendUIDs)
                }
            }
    }

    private func updateFriendListeners(friendUIDs: [String]) {
        // Remove stale
        for uid in Set(friendListeners.keys).subtracting(friendUIDs) {
            friendListeners[uid]?.remove()
            friendListeners.removeValue(forKey: uid)
            friends.removeAll { $0.uid == uid }
        }
        // Add new
        for friendUID in Set(friendUIDs).subtracting(friendListeners.keys) {
            let listener = db.collection("users").document(friendUID)
                .addSnapshotListener { [weak self] snap, _ in
                    guard let data = snap?.data(),
                          let p = UserProfile(from: data, uid: friendUID) else { return }
                    Task { @MainActor [weak self] in
                        if let idx = self?.friends.firstIndex(where: { $0.uid == p.uid }) {
                            self?.friends[idx] = p
                        } else {
                            self?.friends.append(p)
                        }
                    }
                }
            friendListeners[friendUID] = listener
        }
    }
}
