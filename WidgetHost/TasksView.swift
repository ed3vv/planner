import SwiftUI

// MARK: - Drag coordinator

@MainActor
final class DragCoordinator: ObservableObject {
    @Published var draggingID:   UUID? = nil
    @Published var dropTargetID: UUID? = nil
    @Published var dropPos:      DropPos = .above

    enum DropPos { case above, below, on }

    // Not published — changes don't need to trigger re-renders directly
    var currentY: CGFloat = 0
    var frames:   [UUID: CGRect] = [:]

    func dragChanged(id: UUID, y: CGFloat) {
        if draggingID != id { draggingID = id }
        currentY = y
        recomputeTarget()
    }

    func dragEnded(taskStore: TaskStore) {
        defer { draggingID = nil; dropTargetID = nil }
        guard let from = draggingID, let to = dropTargetID, from != to else { return }
        switch dropPos {
        case .on:    taskStore.makeSubtask(from, of: to)
        case .above: taskStore.move(id: from, before: to)
        case .below: taskStore.move(id: from, after: to)
        }
    }

    func updateFrame(id: UUID, frame: CGRect) {
        frames[id] = frame
    }

    private func recomputeTarget() {
        guard let did = draggingID else { dropTargetID = nil; return }
        let y = currentY
        for (id, frame) in frames where id != did {
            if y >= frame.minY && y <= frame.maxY {
                let frac = (y - frame.minY) / max(frame.height, 1)
                let pos: DropPos = frac < 0.28 ? .above : frac > 0.72 ? .below : .on
                if dropTargetID != id  { dropTargetID = id }
                if dropPos      != pos { dropPos      = pos }
                return
            }
        }
        if dropTargetID != nil { dropTargetID = nil }
    }
}

// MARK: - Row frame preference key

private struct RowFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - TasksView

struct TasksView: View {
    @EnvironmentObject var taskStore:    TaskStore
    @EnvironmentObject var panelManager: PanelManager
    @FocusState private var inputFocused: Bool

    @State private var newTaskText  = ""
    @State private var newTaskTag   = ""
    @State private var showTagField = false

    @StateObject private var drag = DragCoordinator()

    // MARK: Derived

    private var pendingRoots: [TodoItem] {
        taskStore.tasks.filter { !$0.isCompleted && $0.parentID == nil }
    }
    private var completedRoots: [TodoItem] {
        taskStore.tasks.filter { $0.isCompleted && $0.parentID == nil }
    }
    private var sectionTags: [String?] {
        var seen: [String?] = []
        var seenSet = Set<String>()
        var hasNil  = false
        for t in pendingRoots {
            if let tag = t.tag {
                if seenSet.insert(tag).inserted { seen.append(tag) }
            } else if !hasNil { hasNil = true; seen.append(nil) }
        }
        return seen
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if pendingRoots.isEmpty && completedRoots.isEmpty {
                        Text("No tasks yet")
                            .font(DS.T.body())
                            .foregroundStyle(DS.C.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.top, DS.Space.xl)
                    }

                    ForEach(sectionTags, id: \.self) { tag in
                        if let tag {
                            Text(tag.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.C.accent.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, DS.Space.lg)
                                .padding(.top, DS.Space.lg)
                                .padding(.bottom, 4)
                            DSDivider()
                        }
                        ForEach(pendingRoots.filter { $0.tag == tag }) { task in
                            taskBlock(task)
                        }
                    }

                    if !completedRoots.isEmpty {
                        Text("Completed")
                            .font(DS.T.caption())
                            .foregroundStyle(DS.C.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.top, DS.Space.lg)
                            .padding(.bottom, DS.Space.xs)
                        ForEach(completedRoots) { task in
                            taskBlock(task)
                        }
                    }
                }
                .padding(.vertical, DS.Space.sm)
            }
            // Collect all row frames reported by TaskRow
            .onPreferenceChange(RowFrameKey.self) { drag.frames = $0 }

            DSDivider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { inputFocused = true }
        .onChange(of: panelManager.expansionTrigger) { _ in inputFocused = true }
        .environmentObject(drag)
    }

    @ViewBuilder
    private func taskBlock(_ task: TodoItem) -> some View {
        let children = taskStore.tasks.filter { $0.parentID == task.id }
        TaskRow(taskID: task.id, indent: false)
        ForEach(children) { child in
            TaskRow(taskID: child.id, indent: true)
        }
    }

    // MARK: Input bar

    var inputBar: some View {
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
                    Image(systemName: "gearshape")
                        .font(.system(size: 12, weight: .medium))
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
                    Image(systemName: "tag")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.C.textMuted)
                        .frame(width: 16)
                    TextField("section  (e.g. work, personal…)", text: $newTaskTag)
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

    private func submit() {
        taskStore.add(newTaskText, tag: newTaskTag.isEmpty ? nil : newTaskTag)
        newTaskText  = ""
        newTaskTag   = ""
        showTagField = false
        inputFocused = true
    }
}

// MARK: - TaskRow

struct TaskRow: View {
    @EnvironmentObject var taskStore: TaskStore
    @EnvironmentObject var drag:      DragCoordinator

    let taskID: UUID
    let indent: Bool

    @State private var isHovered = false

    private let rowH: CGFloat = 36

    private var isDragging:  Bool { drag.draggingID  == taskID }
    private var isDropAbove: Bool { drag.dropTargetID == taskID && drag.dropPos == .above }
    private var isDropBelow: Bool { drag.dropTargetID == taskID && drag.dropPos == .below }
    private var isDropOn:    Bool { drag.dropTargetID == taskID && drag.dropPos == .on    }

    var body: some View {
        if let task = taskStore.tasks.first(where: { $0.id == taskID }) {
            HStack(spacing: DS.Space.sm) {
                if indent { subtaskGuide }

                DSCheckbox(checked: task.isCompleted) { taskStore.toggle(task) }

                Text(task.title)
                    .font(indent ? DS.T.body(12) : DS.T.body())
                    .foregroundStyle(task.isCompleted ? DS.C.textFaint : DS.C.textPrimary)
                    .strikethrough(task.isCompleted, color: DS.C.textFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    if task.parentID != nil {
                        Button { taskStore.detachFromParent(taskID) } label: {
                            Image(systemName: "arrow.turn.up.left")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.C.textMuted)
                                .frame(width: 20, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                        .help("Remove from subtask")
                    }

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

                // Drag handle
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(isHovered ? DS.C.textFaint : .clear)
                    .frame(width: 16)
            }
            .padding(.leading, indent ? DS.Space.xl : DS.Space.lg)
            .padding(.trailing, DS.Space.sm)
            .padding(.vertical, 8)
            .frame(height: rowH)
            .background(
                isDropOn  ? DS.C.accent.opacity(0.08) :
                isHovered ? DS.C.bg2 : .clear
            )
            .overlay(alignment: .top)    { if isDropAbove { dropLine } }
            .overlay(alignment: .bottom) { if isDropBelow { dropLine } }
            .opacity(isDragging ? 0.35 : 1)
            .animation(.easeOut(duration: 0.12), value: isDropAbove)
            .animation(.easeOut(duration: 0.12), value: isDropBelow)
            .animation(.easeOut(duration: 0.12), value: isDropOn)
            .contentShape(Rectangle())
            .onHover { h in withAnimation(.easeOut(duration: 0.1)) { isHovered = h } }
            // Report frame for drop-target calculation
            .background(GeometryReader { geo in
                Color.clear.preference(
                    key: RowFrameKey.self,
                    value: [taskID: geo.frame(in: .global)]
                )
            })
            // Drag gesture — immediate, no system delay
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { v in drag.dragChanged(id: taskID, y: v.location.y) }
                    .onEnded   { _ in drag.dragEnded(taskStore: taskStore) }
            )
        }
    }

    private var subtaskGuide: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(DS.C.border)
                .frame(width: 1.5, height: rowH)
                .offset(x: DS.Space.sm)
            Rectangle()
                .fill(DS.C.border)
                .frame(width: 8, height: 1.5)
                .offset(x: DS.Space.sm)
        }
        .frame(width: DS.Space.lg)
        .clipped()
    }

    private var dropLine: some View {
        Rectangle()
            .fill(DS.C.accent)
            .frame(height: 2)
            .padding(.leading, indent ? DS.Space.xl : DS.Space.lg)
    }
}
