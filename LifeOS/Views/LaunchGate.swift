import SwiftUI

/// Shows the app once `LocalStore` has migrated and loaded the user's data
/// (FND-15). Loading is off the main thread and usually takes a few milliseconds,
/// so the placeholder is deliberately quiet.
struct LaunchGate: View {
    @ObservedObject var store: LocalStore
    let dependencies: AppDependencies

    var body: some View {
        Group {
            switch store.phase {
            case .ready:
                ContentView(dependencies: dependencies)
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .accessibilityLabel("Loading your data")
            case .failed(let message):
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text("Nothing was lost. Your previous data is still on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await store.bootstrap() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .task {
            Diagnostics.shared.start()
            await store.bootstrap()
            // The watch may have connected before data was loaded. Push a real snapshot.
            if store.phase == .ready { dependencies.watchConnectivity.sendSnapshot() }
        }
    }
}
