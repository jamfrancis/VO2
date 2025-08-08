import SwiftUI
import Combine

@MainActor
final class PlanStore: ObservableObject {
    @Published var plan: Plan? = nil
    @Published var lastImportMessage: String? = nil
    // MARK: - Persistence
    private let planFileName = "plan.json"
    private let startDateKey = "plan.startDate"

    @Published var startDate: Date? {
        didSet {
            persistStartDate()
            if var p = plan {
                p.startDate = startDate
                plan = p
            }
        }
    }

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private func planFileURL() -> URL { documentsURL.appendingPathComponent(planFileName) }

    private func persistStartDate() {
        if let d = startDate {
            UserDefaults.standard.set(d.timeIntervalSince1970, forKey: startDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: startDateKey)
        }
    }

    private func loadPersistedStartDate() {
        let t = UserDefaults.standard.double(forKey: startDateKey)
        if t > 0 { startDate = Date(timeIntervalSince1970: t) }
    }

    /// Restore plan JSON and start date from disk/defaults
    func loadPersistedPlan() {
        loadPersistedStartDate()
        loadPrefs()
        let url = planFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try PlanImporter.importFromUserJSON(data)
            var withStart = imported
            if withStart.startDate == nil { withStart.startDate = startDate }
            self.plan = withStart
            let workoutCount = withStart.weeks.reduce(0) { $0 + $1.workouts.count }
            self.lastImportMessage = "Loaded \(withStart.weeks.count) weeks, \(workoutCount) workouts."
        } catch {
            self.lastImportMessage = "Restore failed: \(error.localizedDescription)"
            print("Restore failed: \(error)")
        }
    }

    /// Save the raw JSON used to create the plan so we can restore it on next launch.
    private func persistImportedJSON(_ data: Data) {
        do { try data.write(to: planFileURL(), options: .atomic) }
        catch { print("Failed to persist plan JSON: \(error)") }
    }

    /// Compute the calendar date for a given plan day index (1-based)
    func dateForPlanDay(_ dayIndex: Int) -> Date? {
        guard let start = plan?.startDate ?? startDate else { return nil }
        return Calendar.current.date(byAdding: .day, value: max(0, dayIndex - 1), to: start)
    }

    // MARK: - Future schedule preferences (extensible)
    struct SchedulePreferences: Codable, Equatable {
        var activeWeekdays: Set<Int> = [2,3,4,5,6] // 1=Sun..7=Sat
        var restDays: Set<Int> = []
        var autoLogFromHealthKit: Bool = true
    }
    @Published var schedulePrefs: SchedulePreferences = .init() {
        didSet { savePrefs() }
    }
    private let prefsKey = "schedule.preferences"
    private func loadPrefs() {
        if let d = UserDefaults.standard.data(forKey: prefsKey),
           let p = try? JSONDecoder().decode(SchedulePreferences.self, from: d) {
            schedulePrefs = p
        }
    }
    private func savePrefs() {
        if let d = try? JSONEncoder().encode(schedulePrefs) {
            UserDefaults.standard.set(d, forKey: prefsKey)
        }
    }

    func importJSON(data: Data) {
        Task {
            do {
                var p = try PlanImporter.importFromUserJSON(data)
                // Initialize or sync start date
                if p.startDate == nil {
                    if let existing = self.startDate {
                        p.startDate = existing
                    } else {
                        let today = Date()
                        self.startDate = today
                        p.startDate = today
                    }
                } else {
                    self.startDate = p.startDate
                }
                self.plan = p
                let workoutCount = p.weeks.reduce(0) { $0 + $1.workouts.count }
                self.lastImportMessage = "Loaded \(p.weeks.count) weeks, \(workoutCount) workouts."
                self.persistImportedJSON(data)
            } catch {
                self.lastImportMessage = "Import failed: \(error.localizedDescription)"
                print("Import failed: \(error)")
            }
        }
    }
    func shiftSchedule(days: Int) {
        guard var p = plan else { return }
        var weeks = p.weeks
        PlanSchedule.shift(weeks: &weeks, deltaDays: days)
        p.weeks = weeks
        self.plan = p
    }
}

struct PlanListView: View {
    @EnvironmentObject var store: PlanStore
    @EnvironmentObject var health: HealthKitManager
    var body: some View {
        List {
            if let plan = store.plan {
                // Header with big VO₂ Max
                PlanHeaderView(vo2: health.vo2Max, fitness: health.fitnessLevel, plan: plan)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                // Compact calendar visualization
                PlanCalendarView(plan: plan)
                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)

                Section(plan.planName) {
                    ForEach(plan.weeks) { w in
                        Section("Week \(w.week)") {
                            ForEach(w.workouts.sorted { $0.day < $1.day }) { wo in
                                NavigationLink(wo.name) {
                                    WorkoutEditorView(workoutBinding: binding(for: wo))
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Import a plan JSON from Settings").foregroundColor(.secondary)
            }
        }
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Shift +1d") { store.shiftSchedule(days: 1) }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Shift -1d") { store.shiftSchedule(days: -1) }
            }
        }
    }
    
    func binding(for workout: Workout) -> Binding<Workout> {
        Binding(
            get: { store.plan!.weeks.first { $0.week == workout.weekIndex }!.workouts.first { $0.id == workout.id }! },
            set: { newValue in
                guard var p = store.plan else { return }
                for wi in 0..<p.weeks.count {
                    if p.weeks[wi].week == newValue.weekIndex {
                        if let idx = p.weeks[wi].workouts.firstIndex(where: { $0.id == newValue.id }) {
                            p.weeks[wi].workouts[idx] = newValue
                            store.plan = p
                            return
                        }
                    }
                }
            }
        )
    }
}

struct PlanHeaderView: View {
    let vo2: Double
    let fitness: String
    let plan: Plan
    var totalWorkouts: Int { plan.weeks.reduce(0) { $0 + $1.workouts.count } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(vo2 > 0 ? String(format: "%.1f", vo2) : "—")
                .font(.system(size: 48, weight: .bold))
            Text("VO₂ Max")
                .font(.headline)
                .foregroundColor(.secondary)
            if !fitness.isEmpty {
                Text(fitness)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Divider()
            HStack(spacing: 16) {
                Label("\(plan.weeks.count) weeks", systemImage: "calendar")
                Label("\(totalWorkouts) workouts", systemImage: "figure.run")
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}

struct PlanCalendarView: View {
    let plan: Plan
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.headline)
            ForEach(plan.weeks) { w in
                HStack(spacing: 8) {
                    Text("W\(w.week)")
                        .font(.caption)
                        .frame(width: 28, alignment: .leading)
                        .foregroundColor(.secondary)
                    ForEach(1...7, id: \.self) { d in
                        let hasWO = w.workouts.contains { $0.day == d }
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1))
                            .background(Circle().fill(hasWO ? Color.primary.opacity(0.15) : Color.clear))
                            .frame(width: 18, height: 18)
                            .overlay(Text("\(d)").font(.system(size: 9)))
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

struct WorkoutEditorView: View {
    @EnvironmentObject var store: PlanStore
    @State var workout: Workout
    var workoutBinding: Binding<Workout>?
    
    init(workoutBinding: Binding<Workout>) {
        self._workout = State(initialValue: workoutBinding.wrappedValue)
        self.workoutBinding = workoutBinding
    }
    
    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: Binding(get: { workout.name }, set: { workout.name = $0 }))
                TextField("Title (file)", text: Binding(get: { workout.title ?? "" }, set: { workout.title = $0 }))
                Stepper("Planned day: \(workout.day)", value: Binding(get: { workout.day }, set: { workout.day = max(1, min(7, $0)) }), in: 1...7)
                Stepper("Warmup (sec): \(workout.warmupSec ?? 0)", value: Binding(get: { workout.warmupSec ?? 0 }, set: { workout.warmupSec = $0 }), in: 0...7200)
                Stepper("Cooldown (sec): \(workout.cooldownSec ?? 0)", value: Binding(get: { workout.cooldownSec ?? 0 }, set: { workout.cooldownSec = $0 }), in: 0...7200)
            }
            Section("Blocks") {
                ForEach(workout.blocks.indices, id: \.self) { i in
                    BlockRow(block: $workout.blocks[i])
                }
                .onDelete { workout.blocks.remove(atOffsets: $0) }
                Button { workout.blocks.append(Block(type: .interval, label: "Work", hrZone: 5, durationSec: 60, repeatCount: 4, recover: Recovery(label: "Recovery", hrZone: 2, durationSec: 120))) } label: {
                    Label("Add Interval Block", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Edit Workout")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") { if let b = workoutBinding { b.wrappedValue = workout } }
            }
        }
    }
}

struct BlockRow: View {
    @Binding var block: Block
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Type", selection: $block.type) {
                Text("Interval").tag(BlockType.interval)
                Text("Steady").tag(BlockType.steady)
            }.pickerStyle(.segmented)
            TextField("Label", text: $block.label)
            Picker("HR Zone", selection: Binding(get: { block.hrZone ?? 0 }, set: { block.hrZone = $0 == 0 ? nil : $0 })) {
                Text("None").tag(0)
                ForEach(1...5, id: \.self) { Text("Zone \($0)").tag($0) }
            }
            Stepper("Duration (sec): \(block.durationSec)", value: $block.durationSec, in: 10...7200, step: 5)
            if block.type == .interval {
                Stepper("Repeat: \(block.repeatCount)", value: $block.repeatCount, in: 1...50)
                if let _ = block.recover {
                    VStack(alignment: .leading) {
                        Text("Recovery").font(.caption).foregroundColor(.secondary)
                        Picker("HR Zone", selection: Binding(get: { block.recover?.hrZone ?? 0 }, set: { block.recover?.hrZone = $0 == 0 ? nil : $0 })) {
                            Text("None").tag(0)
                            ForEach(1...5, id: \.self) { Text("Zone \($0)").tag($0) }
                        }
                        Stepper("Duration (sec): \(block.recover!.durationSec)", value: Binding(get: { block.recover!.durationSec }, set: { block.recover!.durationSec = $0 }), in: 10...7200, step: 5)
                    }
                } else {
                    Button("Add Recovery") { block.recover = Recovery(label: "Recovery", hrZone: 2, durationSec: 60) }
                }
            }
        }
    }
}