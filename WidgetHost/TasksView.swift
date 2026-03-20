import SwiftUI

struct TasksView: View {
    @EnvironmentObject var taskStore:    TaskStore
    @EnvironmentObject var panelManager: PanelManager
    @FocusState private var inputFocused: Bool
    @State private var newTaskText = ""
    @State private var newTaskTag  = ""
    @State private var showTagField = false

    var pending:   [Task] { taskStore.tasks.filter { !$0.isCompleted } }
    var completed: [Task] { taskStore.tasks.filter {  $0.isCompleted } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    if pending.isEmpty && completed.isEmpty {
                        Text("No tasks yet")
                            .font(DS.T.body())
                            .foregroundStyle(DS.C.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.top, DS.Space.xl)
                    }
                    ForEach(pending)   { task in TaskRow(taskID: task.id) }
                    if !completed.isEmpty {
                        Text("Completed")
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.top, DS.Space.lg)
                            .padding(.bottom, DS.Space.xs)
                        ForEach(completed) { task in TaskRow(taskID: task.id) }
                    }
                }
                .padding(.vertical, DS.Space.sm)
            }

            DSDivider()

            VStack(spacing: 0) {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.C.textMuted)
                        .frame(width: 16)

                    TextField("New task…", text: $newTaskText)
                        .textFieldStyle(.plain)
                        .font(DS.T.body())
                        .foregroundStyle(DS.C.textPrimary)
                        .focused($inputFocused)
                        .onSubmit { submit() }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showTagField.toggle() }
                    } label: {
                        Text("#")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(showTagField ? DS.C.accent : DS.C.textFaint)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if !newTaskText.isEmpty {
                        Button("Add") { submit() }
                            .font(DS.T.label(11))
                            .foregroundStyle(DS.C.accent)
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)

                if showTagField {
                    HStack(spacing: DS.Space.sm) {
                        Text("#")
                            .font(DS.T.mono(12))
                            .foregroundStyle(DS.C.textMuted)
                            .frame(width: 16)
                        TextField("tag (e.g. work, personal…)", text: $newTaskTag)
                            .textFieldStyle(.plain)
                            .font(DS.T.body(12))
                            .foregroundStyle(DS.C.textPrimary)
                            .onSubmit { submit() }
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.bottom, DS.Space.sm)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(DS.C.bg1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // onAppear handles tab switches (window already key)
        .onAppear { inputFocused = true }
        // expansionTrigger fires after window becomes key → reliable on every expand
        .onChange(of: panelManager.expansionTrigger) { _ in inputFocused = true }
    }

    private func submit() {
        taskStore.add(newTaskText, tag: newTaskTag.isEmpty ? nil : newTaskTag)
        newTaskText  = ""
        newTaskTag   = ""
        showTagField = false
        inputFocused = true
    }
}

struct TaskRow: View {
    @EnvironmentObject var taskStore: TaskStore
    let taskID: UUID
    @State private var isHovered = false

    var body: some View {
        if let task = taskStore.tasks.first(where: { $0.id == taskID }) {
            HStack(spacing: DS.Space.sm) {
                DSCheckbox(checked: task.isCompleted) { taskStore.toggle(task) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(DS.T.body())
                        .foregroundStyle(task.isCompleted ? DS.C.textFaint : DS.C.textPrimary)
                        .strikethrough(task.isCompleted, color: DS.C.textFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let tag = task.tag, !tag.isEmpty {
                        Text("#\(tag)")
                            .font(DS.T.caption(10))
                            .foregroundStyle(DS.C.accent.opacity(0.7))
                    }
                }

                if isHovered {
                    Button { taskStore.delete(task) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.C.textMuted)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, 8)
            .background(isHovered ? DS.C.bg2 : .clear)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
        }
    }
}
