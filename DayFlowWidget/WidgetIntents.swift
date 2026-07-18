import AppIntents
import WidgetKit

enum WidgetOpenDestination: String, AppEnum {
    case today
    case record
    case insights

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Open App To")
    static var caseDisplayRepresentations: [WidgetOpenDestination: DisplayRepresentation] = [
        .today: "今日",
        .record: "今日の記録",
        .insights: "分析",
    ]

    var route: DayFlowSharedStore.Route {
        switch self {
        case .today: .today
        case .record: .todayActual
        case .insights: .insights
        }
    }
}

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

    @Parameter(title: "Open App To", default: .today)
    var openDestination: WidgetOpenDestination
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

    @Parameter(title: "Open App To", default: .insights)
    var openDestination: WidgetOpenDestination
}

struct TypicalDayWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Typical Day Settings"
    static var description = IntentDescription("Choose where to continue in DayFlow.")

    @Parameter(title: "Open App To", default: .insights)
    var openDestination: WidgetOpenDestination
}
