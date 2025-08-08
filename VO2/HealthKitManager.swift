import Combine
import HealthKit
import SwiftUI

class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    
    @Published var vo2Max: Double = 0.0
    @Published var fitnessLevel: String = "Unknown"
    @Published var hasPermission = false
    @Published var isLoading = false
    
    private let typesToRead: Set<HKObjectType> = [
        HKQuantityType(.vo2Max),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKWorkoutType.workoutType()
    ]
    
    private let typesToWrite: Set<HKSampleType> = [
        HKWorkoutType.workoutType()
    ]
    
    func requestPermissions() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }
        
        do {
            try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
            await MainActor.run {
                hasPermission = true
            }
        } catch {
            print("HealthKit authorization failed: \(error)")
        }
    }
    
    func loadVO2Max() async {
        guard hasPermission else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        let vo2MaxType = HKQuantityType(.vo2Max)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: vo2MaxType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sortDescriptor]
        ) { [weak self] _, samples, error in
            guard let self = self, let samples = samples, let mostRecent = samples.first as? HKQuantitySample else {
                DispatchQueue.main.async {
                    self?.isLoading = false
                }
                return
            }
            
            let vo2MaxValue = mostRecent.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo)).unitDivided(by: HKUnit.minute()))
            
            DispatchQueue.main.async {
                self.vo2Max = vo2MaxValue
                self.fitnessLevel = self.calculateFitnessLevel(vo2Max: vo2MaxValue)
                self.isLoading = false
            }
        }
        
        healthStore.execute(query)
    }
    
    private func calculateFitnessLevel(vo2Max: Double) -> String {
        switch vo2Max {
        case 0..<20:
            return "Poor"
        case 20..<35:
            return "Below Average"
        case 35..<45:
            return "Average"
        case 45..<55:
            return "Above Average"
        case 55...:
            return "Excellent"
        default:
            return "Unknown"
        }
    }
    
    func getVO2MaxHistory(days: Int = 30) async -> [VO2MaxDataPoint] {
        guard hasPermission else { return [] }
        
        return await withCheckedContinuation { continuation in
            let vo2MaxType = HKQuantityType(.vo2Max)
            let calendar = Calendar.current
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
            
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            
            let query = HKSampleQuery(
                sampleType: vo2MaxType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let dataPoints = samples.map { sample in
                    VO2MaxDataPoint(
                        date: sample.endDate,
                        value: sample.quantity.doubleValue(for: HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo)).unitDivided(by: HKUnit.minute()))
                    )
                }
                
                continuation.resume(returning: dataPoints)
            }
            
            healthStore.execute(query)
        }
    }
}

struct VO2MaxDataPoint {
    let date: Date
    let value: Double
}