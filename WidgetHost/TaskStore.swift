import Foundation

struct TodoItem: Identifiable, Codable {
    var id:          UUID    = UUID()
    var title:       String
    var isCompleted: Bool    = false
    var createdAt:   Date    = Date()
    var tag:         String? = nil
    var parentID:    UUID?   = nil
}

@MainActor
class TaskStore: ObservableObject {
    @Published var tasks: [TodoItem] = [] { didSet { saveLocally() } }

    private let key = "focusapp_tasks_v2"
    private var cloudSyncEnabled: Bool { FirebaseManager.shared.profile != nil }

    init() {
        loadLocally()
        Task { await self.loadFromCloud() }
    }

    func add(_ title: String, tag: String? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        let item = TodoItem(title: t, tag: tag?.trimmingCharacters(in: .whitespaces).nilIfEmpty)
        tasks.append(item)
        if cloudSyncEnabled { FirebaseManager.shared.syncTask(item) }
    }

    func toggle(_ item: TodoItem) {
        guard let i = tasks.firstIndex(where: { $0.id == item.id }) else { return }
        tasks[i].isCompleted.toggle()
        if cloudSyncEnabled { FirebaseManager.shared.syncTask(tasks[i]) }
    }

    func delete(_ item: TodoItem) {
        // Also delete children
        tasks.removeAll { $0.id == item.id || $0.parentID == item.id }
        if cloudSyncEnabled { FirebaseManager.shared.deleteTask(id: item.id) }
    }

    // MARK: - Reorder

    func move(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let from = tasks.firstIndex(where: { $0.id == id }),
              let to   = tasks.firstIndex(where: { $0.id == targetID }) else { return }
        var t    = tasks
        let item = t.remove(at: from)
        t.insert(item, at: from < to ? to - 1 : to)
        tasks = t
    }

    func move(id: UUID, after targetID: UUID) {
        guard id != targetID,
              let from = tasks.firstIndex(where: { $0.id == id }),
              let to   = tasks.firstIndex(where: { $0.id == targetID }) else { return }
        var t    = tasks
        let item = t.remove(at: from)
        t.insert(item, at: from < to ? to : to + 1)
        tasks = t
    }

    // MARK: - Subtasks

    func makeSubtask(_ childID: UUID, of parentID: UUID) {
        guard childID != parentID,
              let idx = tasks.firstIndex(where: { $0.id == childID }) else { return }
        // Only one level deep: parent must not itself be a subtask
        guard tasks.first(where: { $0.id == parentID })?.parentID == nil else { return }
        tasks[idx].parentID = parentID
        if cloudSyncEnabled { FirebaseManager.shared.syncTask(tasks[idx]) }
    }

    func detachFromParent(_ id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].parentID = nil
        if cloudSyncEnabled { FirebaseManager.shared.syncTask(tasks[idx]) }
    }

    // MARK: - Cloud sync

    private func loadFromCloud() async {
        try? await Task.sleep(for: .seconds(2))
        guard cloudSyncEnabled else { return }
        let cloud = await FirebaseManager.shared.loadTasksFromCloud()
        guard !cloud.isEmpty else { return }
        let cloudIDs = Set(cloud.map(\.id))
        var merged   = cloud
        for local in tasks where !cloudIDs.contains(local.id) {
            merged.append(local)
            FirebaseManager.shared.syncTask(local)
        }
        tasks = merged.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Local persistence

    private func saveLocally() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadLocally() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([TodoItem].self, from: data) else { return }
        tasks = saved
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
