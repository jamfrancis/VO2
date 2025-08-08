
import SwiftUI

struct GenerateView: View {
    @EnvironmentObject var store: PlanStore
    @StateObject var saver = FileSaver()
    @State private var genError: String? = nil
    
    var body: some View {
        VStack(spacing: 16) {
            if let plan = store.plan, let wk = plan.weeks.first?.workouts.first {
                Text(plan.planName).font(.title2).bold()
                Button {
                    generate(for: wk)
                } label: {
                    Label("Generate today’s .workout", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No plan detected.\nGo to Settings → Import JSON to load your plan.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .alert("Generation Error", isPresented: Binding(get: { genError != nil }, set: { if !$0 { genError = nil } })) {
            Button("OK", role: .cancel) { genError = nil }
        } message: {
            Text(genError ?? "")
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
}
