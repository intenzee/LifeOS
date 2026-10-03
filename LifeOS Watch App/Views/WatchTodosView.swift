import SwiftUI
import WatchKit

/// Watch Todos (UI/UX Phase 5 §2): today's list, tap to complete.
struct WatchTodosView: View {
    @ObservedObject var session: WatchSessionManager

    private var todos: [WatchTodo] { session.snapshot.todos }

    var body: some View {
        Group {
            if todos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.system(size: 34)).foregroundStyle(WatchTheme.secondary)
                    Text("Nothing planned today").font(.footnote).foregroundStyle(WatchTheme.secondary)
                }
            } else {
                List {
                    Section {
                        ForEach(todos) { todo in
                            Button {
                                WKInterfaceDevice.current().play(todo.done ? .directionDown : .success)
                                session.toggleTodo(todo.id)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(todo.done ? WatchTheme.onTrack : WatchTheme.secondary)
                                    Text(todo.title)
                                        .strikethrough(todo.done)
                                        .foregroundStyle(todo.done ? WatchTheme.secondary : .primary)
                                        .lineLimit(3)
                                }
                                .frame(minHeight: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(todo.title)
                            .accessibilityValue(todo.done ? "Done" : "Not done")
                            .accessibilityHint("Double-tap to toggle")
                        }
                    } header: {
                        Text("\(session.snapshot.todosCompleted) of \(todos.count) done").monospacedDigit()
                    }
                }
            }
        }
        .navigationTitle("Todos")
    }
}
