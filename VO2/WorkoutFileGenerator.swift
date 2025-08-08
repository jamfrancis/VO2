
import Foundation

public struct PatchSummary: CustomStringConvertible {
    public var replacedDoubles: Int
    public var replacedZones: Int
    public var titleReplaced: Bool
    public var description: String {
        "PatchSummary(doubles: \(replacedDoubles), zones: \(replacedZones), title: \(titleReplaced))"
    }
}

public final class WorkoutFileGenerator {
    public init() {}

    // Helper to find a reasonable template. Repeats are now set programmatically; this is a fallback.
    private func findTemplate(for repeats: Int) -> URL? {
        let bundle = Bundle.main
        let candidates = [
            "HIITTemplate_r\(repeats)",
            "HighIntensityIntervalTraining_r\(repeats)",
            "HIIT_r\(repeats)",
            "VO2 Max Intervals_r\(repeats)",
            // generic fallbacks
            "HighIntensityIntervalTraining",
            "HIITTemplate"
        ]
        for name in candidates {
            if let url = bundle.url(forResource: name, withExtension: "workout") { return url }
        }
        return nil
    }

    /// Attempts to set the interval repeat count in an Apple-exported .workout blob.
    /// We search for the protobuf-like sequence `3a 04 0a 02 08 02 10 <rep> 32 11` and replace `<rep>`.
    /// Returns true if the field was found and replaced.
    private func setRepeatCount(in data: inout Data, repeats rawRepeats: Int) -> Bool {
        // Clamp to a single-byte varint for safety (1..127).
        let rep: UInt8 = UInt8(max(1, min(127, rawRepeats)))
        let prefix: [UInt8] = [0x3a, 0x04, 0x0a, 0x02, 0x08, 0x02, 0x10]
        let suffix: [UInt8] = [0x32, 0x11]
        let bytesCount = data.count
        if bytesCount < prefix.count + 1 + suffix.count { return false }
        // Manual scan for prefix .. rep .. suffix
        var i = 0
        while i + prefix.count + 1 + suffix.count <= bytesCount {
            // compare prefix
            var matches = true
            for j in 0..<prefix.count {
                if data[i + j] != prefix[j] { matches = false; break }
            }
            if matches {
                let repIdx = i + prefix.count
                let sufIdx = repIdx + 1
                if data[sufIdx] == suffix[0] && data[sufIdx + 1] == suffix[1] {
                    data[repIdx] = rep
                    return true
                }
            }
            i += 1
        }
        return false
    }

    /// Helper to replace a title string in the .workout Data, searching for common placeholders and
    /// padding/truncating to the same byte length as the found field.
    private func replaceTitle(in data: inout Data, with newTitle: String) -> Bool {
        let candidates = ["3 min x 3", "Work out"]
        for c in candidates {
            if let r = data.range(of: Data(c.utf8)) {
                let targetLen = r.upperBound - r.lowerBound
                var bytes = Data(newTitle.utf8)
                if bytes.count > targetLen {
                    bytes = bytes.prefix(targetLen)
                } else if bytes.count < targetLen {
                    bytes.append(Data(repeating: 0x20, count: targetLen - bytes.count))
                }
                data.replaceSubrange(r, with: bytes)
                return true
            }
        }
        return false
    }

    // Overload: generate from a resolved template by repeat count
    public func generate(workout: Workout, titleOverride: String? = nil) throws -> (data: Data, summary: PatchSummary) {
        let repeats = workout.blocks.first?.repeatCount ?? 1
        guard let url = findTemplate(for: repeats) else {
            throw NSError(domain: "WorkoutFileGenerator", code: 404, userInfo: [NSLocalizedDescriptionKey: "No .workout template found for repeats=\(repeats). Add a file named HIITTemplate_r\(repeats).workout (or HighIntensityIntervalTraining_r\(repeats).workout) to the app bundle."])
        }
        return try generate(from: url, workout: workout, titleOverride: titleOverride)
    }

    // Provide the template via bundle URL
    public func generate(from templateURL: URL, workout: Workout, titleOverride: String? = nil) throws -> (data: Data, summary: PatchSummary) {
        var data = try Data(contentsOf: templateURL)
        var replacedDoubles = 0
        var replacedZones = 0
        var titleReplaced = false

        // 1) Replace title (known placeholder or generic 'Work out')
        let desiredTitle = titleOverride ?? (workout.title ?? workout.name)
        titleReplaced = replaceTitle(in: &data, with: desiredTitle)

        // 2) Build canonical durations [warmup, work, recover, cooldown]
        var wu: Double = 0
        var workDur: Double = 0
        var recDur: Double = 0
        var cd: Double = 0
        if let s = workout.warmupSec { wu = Double(s) }
        if let s = workout.cooldownSec { cd = Double(s) }
        // Prefer the first block as the canonical work/recover spec
        if let first = workout.blocks.first {
            switch first.type {
            case .steady:
                workDur = Double(first.durationSec)
                // If a second steady exists, treat it as recover duration (optional)
                if workout.blocks.count > 1 {
                    let second = workout.blocks[1]
                    recDur = Double(second.durationSec)
                }
            case .interval:
                workDur = Double(first.durationSec)
                if let r = first.recover { recDur = Double(r.durationSec) }
            }
        }
        let desired = [wu, workDur, recDur, cd]

        // 3) Find the four duration doubles **already present in the Apple file** and only replace those.
        //    Apple’s .workout seems to store a single set of durations + a repeat count elsewhere.
        //    Replacing more than these four corrupts the file. Keep counts/structure intact.
        var foundOffsets: [Int] = []
        let bytes = data // alias
        var i = 0
        while i + 8 <= bytes.count {
            var d: Double = 0
            withUnsafeMutableBytes(of: &d) { dst in
                bytes.copyBytes(to: dst, from: i..<(i + 8))
            }
            // Accept plausible second-length values (30 sec up to 1 hour)
            if d.isFinite, d >= 30, d <= 3600, abs(d.rounded() - d) < 1e-9 {
                foundOffsets.append(i)
            }
            i += 1
        }
        // Heuristic: the four earliest matches correspond to [warmup, work, recover, cooldown]
        if foundOffsets.count >= 4 {
            let targets = Array(foundOffsets.prefix(4))
            for (j, off) in targets.enumerated() {
                var val = desired[j]
                let repl = withUnsafeBytes(of: &val) { Data($0) }
                data.replaceSubrange(off..<(off + 8), with: repl)
                replacedDoubles += 1
            }
        }

        // 4) Programmatic repeat count (only for interval workouts)
        if let first = workout.blocks.first, case .interval = first.type {
            let repeats = max(1, first.repeatCount)
            let ok = setRepeatCount(in: &data, repeats: repeats)
            if !ok {
                // If we cannot locate the repeat field, emit a helpful error so the UI surfaces it.
                throw NSError(domain: "WorkoutFileGenerator", code: 422, userInfo: [NSLocalizedDescriptionKey: "Could not locate repeat field in template. Provide two Apple-exported .workout files with identical durations but different repeats (e.g., 3× vs 5×) so I can map the field for this template."])
            }
        }

        // HR zone replacement is currently disabled to avoid corrupting the container until fully mapped.
        return (data, PatchSummary(replacedDoubles: replacedDoubles, replacedZones: 0, titleReplaced: titleReplaced))
    }
}
