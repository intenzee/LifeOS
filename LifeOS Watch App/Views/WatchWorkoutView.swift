import SwiftUI

struct WatchWorkoutView: View {
    @ObservedObject var session: WatchSessionManager

    private var exercises: [WatchExercise] { session.snapshot.exercises }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(exercises) { exercise in
                        NavigationLink {
                            WatchSetTrackingView(session: session, exercise: exercise)
                        } label: {
                            exerciseRow(exercise)
                        }
                    }
                    if exercises.isEmpty {
                        Text("No exercises yet")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink {
                        WatchExercisePickerView(session: session)
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                            .foregroundStyle(WatchTheme.accent)
                    }
                }
            }
            .navigationTitle("Workout")
        }
    }

    private func exerciseRow(_ exercise: WatchExercise) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(exercise.bodyPart)
                    .font(.system(size: 10))
                    .foregroundStyle(WatchTheme.secondary)
            }
            Spacer()
            Text("\(exercise.setsCompleted)/\(exercise.maxSets)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(exercise.setsCompleted >= exercise.maxSets ? WatchTheme.onTrack : .primary)
        }
    }
}

// MARK: - Exercise picker (body part -> movement)

struct WatchExercisePickerView: View {
    @ObservedObject var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(WatchExerciseCatalog.bodyParts, id: \.self) { bodyPart in
                NavigationLink(bodyPart) {
                    movementList(for: bodyPart)
                }
            }
        }
        .navigationTitle("Body Part")
    }

    private func movementList(for bodyPart: String) -> some View {
        List {
            ForEach(WatchExerciseCatalog.movements(for: bodyPart), id: \.self) { movement in
                Button(movement) {
                    session.addExercise(bodyPart: bodyPart, name: movement, maxSets: 3)
                    dismiss()
                }
            }
        }
        .navigationTitle(bodyPart)
    }
}

// MARK: - Live set tracking (UI/UX Phase 5 §2)

/// Large rep counter, set dots, current exercise, elapsed time and the auto
/// set-tracking state. Rep counting only works while this screen is on, so the
/// screen says so, and "Log set" is a big fallback.
struct WatchSetTrackingView: View {
    @ObservedObject var session: WatchSessionManager
    let exercise: WatchExercise

    @StateObject private var tracker = AutoSetTracker()
    @State private var started = false
    @State private var startedAt: Date?

    private var isComplete: Bool { tracker.setsCompleted >= exercise.maxSets }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                header
                counter
                setDots
                if started { liveMeter }
                controls
                if started {
                    Label("Keep this screen open while you lift", systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchTheme.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .navigationTitle(exercise.bodyPart)
        .onAppear { configureTracker() }
        .onDisappear { tracker.stop() }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(exercise.displayName)
                .font(.system(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(phaseLabel).foregroundStyle(tracker.phase == .active ? WatchTheme.energy : WatchTheme.secondary)
                if let startedAt {
                    Text(startedAt, style: .timer).monospacedDigit().foregroundStyle(WatchTheme.secondary)
                }
            }
            .font(.system(size: 11, weight: .medium))
        }
    }

    private var counter: some View {
        VStack(spacing: 0) {
            Text("\(started ? tracker.reps : tracker.lastSetReps)")
                .font(WatchTheme.number(52))
                .foregroundStyle(tracker.phase == .active ? WatchTheme.energy : .primary)
                .contentTransition(.numericText())
            Text(started ? "reps" : (tracker.lastSetReps > 0 ? "reps last set" : "reps"))
                .font(.system(size: 11)).foregroundStyle(WatchTheme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(started ? tracker.reps : tracker.lastSetReps) reps")
    }

    private var setDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(exercise.maxSets, 1), id: \.self) { i in
                Circle()
                    .fill(i < tracker.setsCompleted ? (isComplete ? WatchTheme.onTrack : WatchTheme.energy) : WatchTheme.card)
                    .overlay(Circle().strokeBorder(WatchTheme.energy.opacity(0.5), lineWidth: 1))
                    .frame(width: 12, height: 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set \(min(tracker.setsCompleted, exercise.maxSets)) of \(exercise.maxSets)")
    }

    private var liveMeter: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(WatchTheme.energy)
                    .frame(width: geo.size.width * tracker.motionLevel)
                    .animation(.easeOut(duration: 0.15), value: tracker.motionLevel)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if isComplete {
                Label("Exercise complete", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WatchTheme.onTrack)
            }

            Button {
                tracker.manualAddSet()
            } label: {
                Label("Log set", systemImage: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.energy)
            .disabled(isComplete)

            Button {
                if started {
                    tracker.stop()
                    startedAt = nil
                } else {
                    tracker.start(initialSets: exercise.setsCompleted)
                    startedAt = Date()
                }
                started.toggle()
            } label: {
                Label(started ? "Stop counting" : "Count reps for me",
                      systemImage: started ? "stop.fill" : "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(started ? WatchTheme.over : WatchTheme.accent)
        }
    }

    private var phaseLabel: String {
        switch tracker.phase {
        case .idle: return started ? "Counting…" : "Ready"
        case .active: return "Counting…"
        case .resting: return "Resting"
        }
    }

    private func configureTracker() {
        tracker.onSetFinalized = { total, _ in
            // Push each finalized set to the phone; clamp to the exercise's max.
            session.updateExerciseSets(exercise.id, setsCompleted: min(total, exercise.maxSets))
            if total >= exercise.maxSets {
                tracker.stop()
                started = false
                startedAt = nil
            }
        }
    }
}
