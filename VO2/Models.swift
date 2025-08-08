
import Foundation

public enum PrimaryMetric: String, Codable, CaseIterable, Identifiable {
    case vo2max, rhr, hrv, lactate, custom
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .vo2max: return "VO₂ Max"
        case .rhr: return "Resting HR"
        case .hrv: return "HRV"
        case .lactate: return "Lactate"
        case .custom: return "Custom"
        }
    }
}

public struct Plan: Codable, Identifiable {
    public var id: String
    public var planName: String
    public var startDate: Date?
    public var durationWeeks: Int
    public var sessionsPerWeek: Int
    public var primaryMetric: PrimaryMetric
    public var weeks: [Week]
}

public struct Week: Codable, Identifiable {
    public var id: String { "week-\(week)" }
    public var week: Int
    public var workouts: [Workout]
}

public struct Workout: Codable, Identifiable {
    public var id: String { "wk-\(weekIndex)-day-\(day)" }
    public var weekIndex: Int
    public var day: Int
    public var name: String
    public var title: String?
    public var warmupSec: Int?
    public var cooldownSec: Int?
    public var blocks: [Block]
}

public enum BlockType: String, Codable { case interval, steady }

public struct Recovery: Codable {
    public var label: String
    public var hrZone: Int?
    public var durationSec: Int
}

public struct Block: Codable, Identifiable {
    public var id: String = UUID().uuidString
    public var type: BlockType
    public var label: String
    public var hrZone: Int?
    public var durationSec: Int
    public var repeatCount: Int = 1
    public var recover: Recovery?
}

// Utilities
public enum DurationParser {
    public static func seconds(from text: String?) -> Int? {
        guard let t0 = text else { return nil }
        let t = t0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t.contains("sec") {
            let n = t.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if let v = Int(n) { return v }
        }
        if t.contains("min") {
            // handle "5-10 min" -> take lower bound
            let nums = t.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if let first = nums.first { return first * 60 }
        }
        return nil
    }
}

public enum IntensityParser {
    public static func zone(from text: String?) -> Int? {
        guard let s0 = text else { return nil }
        let s = s0.lowercased()
        // zone N or zones like "zone 3-4" -> use upper bound
        if s.contains("zone") {
            let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if let last = nums.last { return last }
        }
        // %HRmax heuristic
        if s.contains("hrmax") {
            let nums = s.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init)
            if let maxPct = nums.max() {
                switch maxPct {
                case 0..<70: return 2
                case 70..<80: return 3
                case 80..<90: return 4
                case 90...100: return 5
                default: return 5
                }
            }
        }
        return nil
    }
}

public struct PlanSchedule {
    public static func shift(weeks: inout [Week], deltaDays: Int, clampWithinWeek: Bool = true) {
        for w in 0..<weeks.count {
            for i in 0..<weeks[w].workouts.count {
                weeks[w].workouts[i].day += deltaDays
                if clampWithinWeek {
                    weeks[w].workouts[i].day = min(7, max(1, weeks[w].workouts[i].day))
                }
            }
        }
    }
}
