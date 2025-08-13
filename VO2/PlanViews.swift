import SwiftUI
import Combine
import UIKit

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(vo2 > 0 ? String(format: "%.1f", vo2) : "—")
                    .font(.system(size: 56, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("VO₂ Max").font(.headline).foregroundStyle(.secondary)
                    if !fitness.isEmpty { Text(fitness).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            if vo2 > 0 {
                Gauge(value: min(max((vo2 - 20) / 50, 0), 1)) { } currentValueLabel: { Text(String(format: "%.0f", vo2)) } minimumValueLabel: { Text("20") } maximumValueLabel: { Text("70+") }
                    .tint(.blue)
            }
            HStack(spacing: 16) {
                Label("\(plan.weeks.count) weeks", systemImage: "calendar")
                Label("\(totalWorkouts) workouts", systemImage: "figure.run")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

struct HomeView: View {
    @EnvironmentObject var store: PlanStore
    @EnvironmentObject var health: HealthKitManager
    @StateObject private var saver = FileSaver()
    @State private var genError: String? = nil
    
    enum ScheduleState { case idle, working, success(String), failure(String) }
    @State private var scheduleState: ScheduleState = .idle
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let plan = store.plan {
                    PlanHeaderView(vo2: health.vo2Max, fitness: health.fitnessLevel, plan: plan)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    PlanCalendarView(plan: plan)
                        .padding(.horizontal)
                    
                    if let first = workoutForToday(in: plan) {
                        VStack(spacing: 12) {
                            Button {
                                generate(for: first)
                            } label: {
                                Label("Generate today's .workout", systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            
                            if #available(iOS 17, *) {
                                Button {
                                    Task { await onSchedule(workout: first) }
                                } label: {
                                    Label(scheduleButtonTitle, systemImage: scheduleButtonIcon)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .disabled(isBusy)
                            }
                        }
                        .padding(.horizontal)
                    }
                } else {
                    Text("Import a plan JSON from Settings")
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if case .success(let msg) = scheduleState {
                ToastView(title: "Scheduled", message: msg, systemImage: "checkmark.circle.fill")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding()
            } else if case .failure(let msg) = scheduleState {
                ToastView(title: "Failed", message: msg, systemImage: "exclamationmark.triangle.fill")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button("Shift +1d") { store.shiftSchedule(days: 1) }
                    Button("Shift -1d") { store.shiftSchedule(days: -1) }
                }
            }
        }
        .alert("Generation Error", isPresented: Binding(get: { genError != nil }, set: { if !$0 { genError = nil } })) {
            Button("OK", role: .cancel) { genError = nil }
        } message: { Text(genError ?? "") }
    }
    
    private var isBusy: Bool {
        if case .working = scheduleState { return true }
        return false
    }
    private var scheduleButtonTitle: String {
        switch scheduleState {
        case .idle: return "Schedule"
        case .working: return "Scheduling…"
        case .success: return "Scheduled"
        case .failure: return "Try Again"
        }
    }
    private var scheduleButtonIcon: String {
        switch scheduleState {
        case .idle: return "clock.badge.checkmark"
        case .working: return "clock.arrow.circlepath"
        case .success: return "checkmark.circle"
        case .failure: return "exclamationmark.triangle"
        }
    }
    
    private func workoutForToday(in plan: Plan) -> Workout? {
        let start = plan.startDate ?? store.startDate ?? Date()
        let delta = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        let todayIndex = max(1, delta + 1)
        let flat = plan.weeks.flatMap { $0.workouts }
        let key: (Workout) -> Int = { (($0.weekIndex - 1) * 7 + $0.day) }
        if let exact = flat.first(where: { key($0) == todayIndex }) { return exact }
        if let next = flat.sorted { key($0) < key($1) }.first(where: { key($0) >= todayIndex }) { return next }
        return flat.sorted { key($0) < key($1) }.last
    }
    
    private func generate(for workout: Workout) {
        let dayIndex = max(1, (workout.weekIndex - 1) * 7 + workout.day)
        let targetDate = store.dateForPlanDay(dayIndex) ?? Date()
        let title = makeTitle(dayIndex: dayIndex, date: targetDate)
        do {
            let (data, _) = try WorkoutFileGenerator().generate(workout: workout, titleOverride: title)
            if let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first {
                saver.saveAndShare(data: data, suggestedName: title, from: root)
            }
        } catch {
            genError = error.localizedDescription
        }
    }
    
    @available(iOS 17, *)
    private func onSchedule(workout: Workout) async {
        if isBusy { return }
        scheduleState = .working
        let dayIndex = max(1, (workout.weekIndex - 1) * 7 + workout.day)
        let targetDate = store.dateForPlanDay(dayIndex) ?? Date()
        let title = makeTitle(dayIndex: dayIndex, date: targetDate)
        do {
            let (data, _) = try WorkoutFileGenerator().generate(workout: workout, titleOverride: title)
            try await WKBridge.schedule(data: data, at: targetDate)
            scheduleState = .success(title + " on Apple Watch")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { scheduleState = .idle } }
        } catch {
            scheduleState = .failure(error.localizedDescription)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { withAnimation { scheduleState = .idle } }
        }
    }
    
    private func makeTitle(dayIndex: Int, date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        let m: String = { switch month { case 1: return "Jan"; case 2: return "Feb"; case 3: return "Mar"; case 4: return "Apr"; case 5: return "May"; case 6: return "Jun"; case 7: return "Jul"; case 8: return "Aug"; case 9: return "Sept"; case 10: return "Oct"; case 11: return "Nov"; default: return "Dec" } }()
        return "Day \(dayIndex) | \(m) \(day)"
    }
}

struct ToastView: View {
    let title: String
    let message: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).imageScale(.large)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(radius: 10, y: 6)
    }
}