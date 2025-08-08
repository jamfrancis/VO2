
import Foundation

fileprivate func parseStartDate(_ any: Any?) -> Date? {
    guard let s = any as? String else { return nil }
    let iso = ISO8601DateFormatter()
    if let d = iso.date(from: s) { return d }
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd"
    return df.date(from: s)
}

public enum PlanImporter {
    public static func importFromUserJSON(_ data: Data, defaultPrimary: PrimaryMetric = .vo2max) throws -> Plan {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let planName = (obj?["plan_name"] as? String) ?? "Training Plan"
        let durationWeeks = (obj?["duration_weeks"] as? Int) ?? 6
        let sessionsPerWeek = (obj?["sessions_per_week"] as? Int) ?? 3
        let startDateFromJSON = parseStartDate(obj?["start_date"])
        let weeksArr = (obj?["weeks"] as? [[String: Any]]) ?? []
        
        var weeks: [Week] = []
        for (wIndex, wObj) in weeksArr.enumerated() {
            let weekNum = (wObj["week"] as? Int) ?? (wIndex + 1)
            var workouts: [Workout] = []
            let wos = (wObj["workouts"] as? [[String: Any]]) ?? []
            for wo in wos {
                let day = (wo["day"] as? Int) ?? 1
                let name = (wo["name"] as? String) ?? "Workout"
                let warmupSec = DurationParser.seconds(from: wo["warmup"] as? String)
                let cooldownSec = DurationParser.seconds(from: wo["cooldown"] as? String)
                
                var blocks: [Block] = []
                if let mainBlock = wo["main_block"] as? [[String: Any]], let first = mainBlock.first {
                    let label = "Steady"
                    let hrZone = IntensityParser.zone(from: first["intensity"] as? String)
                    let dur = DurationParser.seconds(from: first["work"] as? String) ?? 0
                    blocks.append(Block(type: .steady, label: label, hrZone: hrZone, durationSec: dur, repeatCount: 1, recover: nil))
                    if mainBlock.count > 1, let rec = mainBlock.dropFirst().first {
                        let recZone = IntensityParser.zone(from: rec["intensity"] as? String)
                        let recDur = DurationParser.seconds(from: rec["recover"] as? String) ?? 0
                        blocks.append(Block(type: .steady, label: "Recover", hrZone: recZone, durationSec: recDur, repeatCount: 1, recover: nil))
                    }
                }
                if let intervals = wo["intervals"] as? [[String: Any]], intervals.count >= 2 {
                    let work = intervals[0]
                    let rest = intervals[1]
                    let workDur = DurationParser.seconds(from: work["work"] as? String) ?? 0
                    let restDur = DurationParser.seconds(from: rest["recover"] as? String) ?? 0
                    let workZone = IntensityParser.zone(from: work["intensity"] as? String)
                    let restZone = IntensityParser.zone(from: rest["intensity"] as? String)
                    let repeatCount = (wo["repeat"] as? Int) ?? 1
                    let recover = Recovery(label: "Recovery", hrZone: restZone, durationSec: restDur)
                    blocks.append(Block(type: .interval, label: "Work", hrZone: workZone, durationSec: workDur, repeatCount: repeatCount, recover: recover))
                }
                
                let workout = Workout(weekIndex: weekNum,
                                      day: day,
                                      name: name,
                                      title: wo["name"] as? String,
                                      warmupSec: warmupSec,
                                      cooldownSec: cooldownSec,
                                      blocks: blocks)
                workouts.append(workout)
            }
            weeks.append(Week(week: weekNum, workouts: workouts))
        }
        
        return Plan(id: UUID().uuidString,
                    planName: planName,
                    startDate: startDateFromJSON,
                    durationWeeks: durationWeeks,
                    sessionsPerWeek: sessionsPerWeek,
                    primaryMetric: defaultPrimary,
                    weeks: weeks)
    }
}
