import SwiftUI

@main
struct VaxApp: App {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var planStore = PlanStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .environmentObject(planStore)
                .preferredColorScheme(.dark)
                .task {
                    planStore.loadPersistedPlan()
                    await healthKitManager.requestPermissions()
                    await healthKitManager.loadVO2Max()
                }
        }
    }
}