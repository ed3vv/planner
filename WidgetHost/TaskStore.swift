import Foundation

struct Task: Identifiable, Codable {
    var id:          UUID    = UUID()
    var title:       String
    var isCompleted: Bool    = false
    var createdAt:   Date    = Date()
    var tag:         String? = nil   // optional, user-defined
}

class TaskStore: ObservableObject {
    @Published var tasks: [Task] = [] { didSet { save() } }

    private let key = "focusapp_tasks_v2"

    init() { load() }

    func add(_ title: String, tag: String? = nil) {
        let t = title.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        tasks.append(Task(title: t, tag: tag?.trimmingCharacters(in: .whitespaces).nilIfEmpty))
    }

    func toggle(_ task: Task) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i].isCompleted.toggle()
    }

    func delete(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([Task].self, from: data) else { return }
        tasks = saved
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
