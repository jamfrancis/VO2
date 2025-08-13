
import SwiftUI
#if canImport(WorkoutKit)
import WorkoutKit
#endif

struct GenerateView: View {
    @EnvironmentObject var store: PlanStore
    @StateObject var saver = FileSaver()
    @State private var genError: String? = nil
    @State private var errorMessage: String?
    @State private var scheduleBanner: String?
    @State private var scheduling = false
    
    var body: some View {
        VStack(spacing: 16) {
            if let plan = store.plan, let wk = plan.weeks.first?.workouts.first {
                Text(plan.planName).font(.title2).bold()
                
                VStack(spacing: 12) {
                    Button {
                        generate(for: wk)
                    } label: {
                        Label("Generate today's .workout", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    
#if canImport(WorkoutKit)
                    if #available(iOS 17, *) {
                        Button {
                            Task { await onSchedule(workout: wk) }
                        } label: {
                            Label("Schedule", systemImage: "clock.badge.checkmark")
                        }
                        .buttonStyle(.bordered)
                    }
#endif
                }
            } else {
                Text("No plan detected.\nGo to Settings → Import JSON to load your plan.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .safeAreaInset(edge: .bottom) {
            if let msg = scheduleBanner {
                ToastView(title: "Scheduled", message: msg, systemImage: "checkmark.circle.fill")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding()
            }
        }
        .alert("Generation Error", isPresented: Binding(get: { genError != nil }, set: { if !$0 { genError = nil } })) {
            Button("OK", role: .cancel) { genError = nil }
        } message: {
            Text(genError ?? "")
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
    
    func generate(for workout: Workout) {
        // Program day index (1-based)
        let dayIndex = max(1, (workout.weekIndex - 1) * 7 + workout.day)

        // Date for that plan day, based on plan start date (fallback to today if missing)
        let targetDate: Date = store.dateForPlanDay(dayIndex) ?? Date()

        // Custom month abbreviations (Sept instead of Sep)
        let month = Calendar.current.component(.month, from: targetDate)
        let day   = Calendar.current.component(.day, from: targetDate)
        let monthAbbrev: String = {
            switch month {
            case 1: return "Jan"
            case 2: return "Feb"
            case 3: return "Mar"
            case 4: return "Apr"
            case 5: return "May"
            case 6: return "Jun"
            case 7: return "Jul"
            case 8: return "Aug"
            case 9: return "Sept"
            case 10: return "Oct"
            case 11: return "Nov"
            default: return "Dec"
            }
        }()
        let title = "Day \(dayIndex) | \(monthAbbrev) \(day)"
        do {
            let (data, summary) = try WorkoutFileGenerator().generate(workout: workout, titleOverride: title)
            print("Patched: \(summary)")
            if let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first {
                saver.saveAndShare(data: data, suggestedName: title, from: root)
            }
        } catch {
            genError = error.localizedDescription
        }
    }
    
#if canImport(WorkoutKit)
    @available(iOS 17, *)
    @MainActor
    private func onSchedule(workout: Workout) async {
        let dayIndex = max(1, (workout.weekIndex - 1) * 7 + workout.day)
        let targetDate = store.dateForPlanDay(dayIndex) ?? Date()
        let title = makeTitle(dayIndex: dayIndex, date: targetDate)
        
        do {
            let (data, _) = try WorkoutFileGenerator().generate(workout: workout, titleOverride: title)
            try await WKBridge.schedule(data: data, at: targetDate)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await MainActor.run { scheduleBanner = title + " on Apple Watch" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { withAnimation { scheduleBanner = nil } }
        } catch {
            errorMessage = "Schedule failed: \(error.localizedDescription)"
        }
    }
#endif
    
    private func makeTitle(dayIndex: Int, date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let day = Calendar.current.component(.day, from: date)
        let monthAbbrev: String = {
            switch month {
            case 1: return "Jan"
            case 2: return "Feb"
            case 3: return "Mar"
            case 4: return "Apr"
            case 5: return "May"
            case 6: return "Jun"
            case 7: return "Jul"
            case 8: return "Aug"
            case 9: return "Sept"
            case 10: return "Oct"
            case 11: return "Nov"
            default: return "Dec"
            }
        }()
        return "Day \(dayIndex) | \(monthAbbrev) \(day)"
    }
}

