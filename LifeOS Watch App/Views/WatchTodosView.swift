import SwiftUI

struct WatchTodosView: View {
    @ObservedObject var session: WatchSessionManager

    private var todos: [WatchTodo] { session.snapshot.todos }

    var body: some View {
        Group {
            if todos.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No todos today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                List {
                    ForEach(todos) { todo in
                        Button {
                            session.toggleTodo(todo.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.done ? WatchTheme.accent : .secondary)
                                Text(todo.title)
                                    .strikethrough(todo.done)
                                    .foregroundStyle(todo.done ? .secondary : .primary)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Todos")
    }
}
