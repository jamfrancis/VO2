import Foundation
import WorkoutKit

enum WKBridge {
    /// Convert your .workout file data into a WorkoutPlan for preview/schedule.
    @available(iOS 17, *)
    static func plan(from data: Data) throws -> WorkoutPlan {
        try WorkoutPlan(from: data)
    }

    /// Schedule on the paired Apple Watch at a specific date/time.
    @available(iOS 17, *)
    @MainActor
    static func schedule(data: Data, at date: Date) async throws {
        let plan = try WorkoutPlan(from: data)
        _ = await WorkoutKit.WorkoutScheduler.shared.requestAuthorization()
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        _ = try await WorkoutKit.WorkoutScheduler.shared.schedule(plan, at: comps)
    }
}