import Foundation

/// Coarse relative time for list meta lines: "just now", "5 min", "3 h",
/// "yesterday", "4 d", then a short date. Deliberately imprecise — the
/// popover is a glance, not a log.
enum RelativeTime {
    static func coarse(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 24 * 3600, calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600 {
            return "\(Int(seconds / 3600)) h"
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days <= 1 { return "yesterday" }
        if days < 7 { return "\(days) d" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
