import Combine
import Foundation
import HealthKit

@MainActor
class WorkoutTracker: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var completedWorkouts = 0
    @Published var weeklyProgress: [Bool] = Array(repeating: false, count: 7)
    @Published var currentStreak = 0
    @Published var lastWorkoutDate: Date?
    @Published var isLoading = false
    
    init() {
        // Don't automatically load on init to avoid permission issues
    }
    
    func loadWorkoutHistory() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }
        
        isLoading = true
        
        async let recentWorkoutsTask = loadRecentWorkouts()
        async let totalCountTask = loadTotalWorkoutCount()
        
        await recentWorkoutsTask
        await totalCountTask
        
        isLoading = false
    }
    
    private func loadRecentWorkouts() async {
        let workoutType = HKWorkoutType.workoutType()
        let calendar = Calendar.current
        let now = Date()
        
        // Get workouts from the past 7 days
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let datePredicate = HKQuery.predicateForSamples(withStart: oneWeekAgo, end: now, options: .strictStartDate)
        
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let error = error {
                    print("Failed to load recent workouts: \(error)")
                    continuation.resume()
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    self.processWorkouts(workouts)
                    continuation.resume()
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func loadTotalWorkoutCount() async {
        let workoutType = HKWorkoutType.workoutType()
        
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { [weak self] _, samples, error in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if let error = error {
                    print("Failed to load total workout count: \(error)")
                    continuation.resume()
                    return
                }
                
                guard let workouts = samples as? [HKWorkout] else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    self.completedWorkouts = workouts.count
                    print("Total workouts loaded: \(workouts.count)")
                    continuation.resume()
                }
            }
            
            healthStore.execute(query)
        }
    }
    
    private func processWorkouts(_ workouts: [HKWorkout]) {
        let calendar = Calendar.current
        let today = Date()
        
        var newWeeklyProgress = Array(repeating: false, count: 7)
        var lastDate: Date?
        
        // Mark days with workouts
        for workout in workouts {
            let daysSinceWorkout = calendar.dateComponents([.day], from: workout.endDate, to: today).day ?? 0
            
            if daysSinceWorkout >= 0 && daysSinceWorkout < 7 {
                newWeeklyProgress[6 - daysSinceWorkout] = true // Reverse order for chronological display
            }
            
            if lastDate == nil || workout.endDate > lastDate! {
                lastDate = workout.endDate
            }
        }
        
        weeklyProgress = newWeeklyProgress
        lastWorkoutDate = lastDate
        calculateStreak()
        
        print("Processed \(workouts.count) recent workouts")
        print("Weekly progress: \(newWeeklyProgress)")
    }
    
    func markWorkoutCompleted() async {
        let calendar = Calendar.current
        let today = Date()
        let todayIndex = 6 // Today is always the last index in our array
        
        // Mark today as completed
        weeklyProgress[todayIndex] = true
        completedWorkouts += 1
        lastWorkoutDate = today
        
        calculateStreak()
        
        print("Workout marked as completed. Total: \(completedWorkouts)")
    }
    
    private func calculateStreak() {
        var streak = 0
        
        // Calculate streak from today backwards
        for i in stride(from: weeklyProgress.count - 1, through: 0, by: -1) {
            if weeklyProgress[i] {
                streak += 1
            } else {
                break
            }
        }
        
        currentStreak = streak
        print("Current streak: \(streak)")
    }
    
    func getCompletionRate() -> Double {
        let completed = weeklyProgress.filter { $0 }.count
        return Double(completed) / 7.0
    }
    
    func shouldShowEncouragement() -> Bool {
        return currentStreak == 0 && completedWorkouts > 0
    }
    
    func getEncouragementMessage() -> String {
        let completedThisWeek = weeklyProgress.filter { $0 }.count
        
        if currentStreak >= 5 {
            return "Amazing! You're on fire! 🔥"
        } else if currentStreak >= 3 {
            return "Great consistency! Keep it up! 💪"
        } else if completedThisWeek >= 4 {
            return "Fantastic week! You're crushing it! 🎯"
        } else if shouldShowEncouragement() {
            return "Ready to get back on track? 🎯"
        } else if completedWorkouts == 0 {
            return "Let's start your fitness journey! 🚀"
        } else {
            return "Every workout counts! 🚀"
        }
    }
    
    func resetWeeklyProgress() {
        weeklyProgress = Array(repeating: false, count: 7)
        currentStreak = 0
    }
    
    // Get workout statistics
    func getWorkoutStats() -> (thisWeek: Int, lastWeek: Int, total: Int) {
        let thisWeekCount = weeklyProgress.filter { $0 }.count
        return (thisWeek: thisWeekCount, lastWeek: 0, total: completedWorkouts)
    }
}
