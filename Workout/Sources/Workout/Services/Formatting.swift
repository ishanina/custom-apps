import Foundation

enum Fmt {
    /// 75 → "1:15", 3725 → "1:02:05"
    static func clock(_ t: TimeInterval) -> String {
        let s = max(0, Int(t.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// 45 → "45 sec", 1450 → "24 min", 4500 → "1 hr 15 min"
    static func human(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        if s < 60 { return "\(s) sec" }
        let m = (s + 30) / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60, rm = m % 60
        return rm == 0 ? "\(h) hr" : "\(h) hr \(rm) min"
    }

    /// 30 → "30s", 60 → "1m", 90 → "1:30"
    static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds % 60 == 0 { return "\(seconds / 60)m" }
        return clock(TimeInterval(seconds))
    }

    /// Parses "90", "1:30" or "1:02:30". Empty text parses as 0; garbage as nil.
    static func parseTime(_ text: String) -> TimeInterval? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return 0 }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count <= 3 else { return nil }
        var total = 0
        for (i, part) in parts.enumerated() {
            guard let n = Int(part), n >= 0 else { return nil }
            if i > 0 && n >= 60 { return nil }
            total = total * 60 + n
        }
        return TimeInterval(total)
    }

    /// Text for a time field: 0 → "" (so the placeholder shows), else clock format.
    static func fieldText(_ t: TimeInterval) -> String { t > 0 ? clock(t) : "" }
}
