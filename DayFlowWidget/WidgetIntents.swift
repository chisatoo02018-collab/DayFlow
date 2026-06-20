import AppIntents
import WidgetKit

// MARK: - Today Widget

enum DisplayMode: String, AppEnum {
    case both, calendarOnly, remindersOnly

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display Mode")
    static var caseDisplayRepresentations: [DisplayMode: DisplayRepresentation] = [
        .both: "Calendar & Reminders",
        .calendarOnly: "Calendar Only",
        .remindersOnly: "Reminders Only",
    ]
}

struct TodayWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Today Settings"
    static var description = IntentDescription("Choose what to display.")

    @Parameter(title: "Display", default: .both)
    var displayMode: DisplayMode
}

// MARK: - Stats Widget

enum TrendDays: Int, AppEnum {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Trend Period")
    static var caseDisplayRepresentations: [TrendDays: DisplayRepresentation] = [
        .sevenDays: "7 Days",
        .fourteenDays: "14 Days",
        .thirtyDays: "30 Days",
    ]
}

struct StatsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Stats Settings"
    static var description = IntentDescription("Configure the stats display.")

    @Parameter(title: "Trend Period", default: .sevenDays)
    var trendDays: TrendDays
}
