import Foundation

/// Painting times as text: estimates and time spent. The unit words come from the string
/// catalog (their plural forms and order are a translator's call); only the arithmetic lives
/// here.
nonisolated enum PaintingTimeText {
    /// "~40 min", "~1.5 h", "~12 h".
    static func approximate(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        let duration: String
        if minutes < 55 {
            duration = Self.minutes(max(5, Int((minutes / 5).rounded()) * 5))
        } else {
            let hours = minutes / 60
            if hours < 9.75 {
                let halves = (hours * 2).rounded() / 2
                if halves == halves.rounded() {
                    duration = Self.hours(Int(halves))
                } else {
                    let text = halves.formatted(.number.precision(.fractionLength(1)))
                    duration = String(localized: "time.hours.fractional", defaultValue: "\(text) h",
                                      comment: "A duration in hours with a decimal, e.g. 1.5 h; the argument is the formatted number")
                }
            } else {
                duration = Self.hours(Int(hours.rounded()))
            }
        }
        return String(localized: "time.approximately", defaultValue: "~\(duration)",
                      comment: "An estimated duration, e.g. ~40 min; the argument is the duration text")
    }

    /// "2 h 14 min", "35 min", "< 1 min".
    static func spent(_ seconds: TimeInterval) -> String {
        let value = seconds / 60
        // Double(Int.max) rounds up on 64-bit devices: test the bound before converting.
        let total = value >= Double(Int.max) ? Int.max : (value > 0 ? Int(value) : 0)
        if total < 1 {
            return String(localized: "time.lessThanMinute", defaultValue: "< 1 min",
                          comment: "Painting time shorter than one minute")
        }
        let h = total / 60, m = total % 60
        if h == 0 { return minutes(m) }
        if m == 0 { return hours(h) }
        let hoursText = hours(h), minutesText = minutes(m)
        return String(localized: "time.hoursAndMinutes", defaultValue: "\(hoursText) \(minutesText)",
                      comment: "A duration in hours and minutes, e.g. 2 h 14 min; the arguments are the hours text and the minutes text")
    }

    private static func minutes(_ count: Int) -> String {
        String(localized: "time.minutes", defaultValue: "\(count) min",
               comment: "A duration in minutes, e.g. 35 min; the argument is the number of minutes")
    }

    private static func hours(_ count: Int) -> String {
        String(localized: "time.hours", defaultValue: "\(count) h",
               comment: "A duration in whole hours, e.g. 2 h; the argument is the number of hours")
    }
}
