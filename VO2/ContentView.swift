import SwiftUI

struct ContentView: View {
    @EnvironmentObject var healthKitManager: HealthKitManager
    @EnvironmentObject var store: PlanStore
    
    var body: some View {
        TabView {
            NavigationStack {
                PlanListView()
                    .navigationTitle("Plan")
            }
            .tabItem { Label("Plan", systemImage: "list.bullet") }
            
            NavigationStack {
                GenerateView()
                    .navigationTitle("Generate")
            }
            .tabItem { Label("Generate", systemImage: "hammer") }
            
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
