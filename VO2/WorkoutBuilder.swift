import SwiftUI
import Combine

struct WorkoutData {
    let description: String
    let totalMinutes: Int
    let displayName: String
}

class WorkoutBuilder: ObservableObject {
    
    func createProgressiveWorkout(vo2Max: Double, completedWorkouts: Int) -> WorkoutData {
        if completedWorkouts > 10 {
            return WorkoutData(
                description: """
                5min Warmup (Zone 2)
                3 × 6min @ Zone 5 (90% HR max)
                    2min recovery (Zone 2)
                5min Cooldown (Zone 1)
                """,
                totalMinutes: 34,
                displayName: "Advanced VO₂ Max Training"
            )
        } else if completedWorkouts > 5 {
            return WorkoutData(
                description: """
                5min Warmup (Zone 2)
                4 × 5min @ Zone 5 (90% HR max)
                    2.5min recovery (Zone 2)
                5min Cooldown (Zone 1)
                """,
                totalMinutes: 40,
                displayName: "Intermediate VO₂ Max Training"
            )
        } else {
            return WorkoutData(
                description: """
                5min Warmup (Zone 2)
                4 × 4min @ Zone 5 (90% HR max)
                    3min recovery (Zone 2)
                5min Cooldown (Zone 1)
                """,
                totalMinutes: 37,
                displayName: "VO₂ Max HIIT Training"
            )
        }
    }
    
    func getTotalDuration(for workout: WorkoutData) -> TimeInterval {
        return TimeInterval(workout.totalMinutes * 60)
    }
    
    func getWorkoutDescription(for workout: WorkoutData) -> String {
        return workout.description
    }
}