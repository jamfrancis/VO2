import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: PlanStore
    @State private var showingImporter = false
    
    var body: some View {
        Form {
            Section("Plan start date") {
                DatePicker("Start", selection: Binding(
                    get: { store.startDate ?? Date() },
                    set: { newVal in
                        store.startDate = newVal
                        if var p = store.plan { p.startDate = newVal; store.plan = p }
                    }
                ), displayedComponents: .date)
            }
            Section("Primary metric") {
                Picker("Metric", selection: Binding(
                    get: { store.plan?.primaryMetric ?? .vo2max },
                    set: { store.plan?.primaryMetric = $0 }
                )) {
                    ForEach(PrimaryMetric.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section("Import plan JSON") {
                Button("Import JSON") { showingImporter = true }
            }
            if let plan = store.plan {
                Section("Loaded plan") {
                    Text(plan.planName)
                        .foregroundColor(.secondary)
                }
            }
            if let msg = store.lastImportMessage {
                Section("Import status") {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [UTType.json]) { result in
            switch result {
            case .success(let url):
                var didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    store.importJSON(data: data)
                } catch {
                    print("Import failed to read data: \(error)")
                }
            case .failure(let err):
                print("Import failed: \(err)")
            }
        }
    }
}
