import Foundation

/// 菜单栏「上次锁定」一行的文案（纯函数，便于测试）。
///
/// 合规 / 排查误锁场景需要看到「何时锁、为什么锁」；当天只显示时间，跨天带日期。
/// 格式化与「是否同一天」的判断必须使用同一日历与时区，否则会出现日期与时间错位。
enum LastLockSummary {
    static func text(
        reason: String,
        at date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(format(date, dateStyle: .omitted, calendar: calendar, locale: locale)) · \(reason)"
        }
        return "\(format(date, dateStyle: .abbreviated, calendar: calendar, locale: locale)) · \(reason)"
    }

    private static func format(
        _ date: Date,
        dateStyle: Date.FormatStyle.DateStyle,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        var style = Date.FormatStyle(date: dateStyle, time: .shortened).locale(locale)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }
}
