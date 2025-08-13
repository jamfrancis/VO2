import SwiftUI

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var store: PlanStore
    
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
                    .navigationTitle("Plan")
            }
            .tabItem { Label("Plan", systemImage: "list.bullet") }
            
            NavigationStack {
                PlanListView()
                    .navigationTitle("Modify Plan")
            }
            .tabItem { Label("Edit", systemImage: "slider.horizontal.3") }
            
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}