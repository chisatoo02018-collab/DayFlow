import AppIntents
import WidgetKit

// MARK: - Dashboard Widget Intent

enum DashboardDisplayMode: String, AppEnum {
    case both = "both"
    case calendarOnly = "calendar"
    case remindersOnly = "reminders"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Display Mode")
    static var caseDisplayRepresentations: [DashboardDisplayMode: DisplayRepresentation] = [
        .both: "Calendar & Reminders",
        .calendarOnly: "Calendar Only",
        .remindersOnly: "Reminders Only",
    ]
}

enum DashboardMaxItems: Int, AppEnum {
    case three = 3
    case five = 5
    case eight = 8

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Max Items")
    static var caseDisplayRepresentations: [DashboardMaxItems: DisplayRepresentation] = [
        .three: "3 items",
        .five: "5 items",
        .eight: "8 items",
    ]
}

struct DashboardWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Dashboard Settings"
    static var description = IntentDescription("Choose what to display on the dashboard.")

    @Parameter(title: "Display Mode", default: .both)
    var displayMode: DashboardDisplayMode

    @Parameter(title: "Max Items", default: .five)
    var maxItems: DashboardMaxItems
}

// MARK: - Completion Chart Widget Intent

struct CompletionChartIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Completion Chart Settings"
    static var description = IntentDescription("Choose which time periods to display.")

    @Parameter(title: "Year", default: true)
    var showYear: Bool

    @Parameter(title: "Month", default: true)
    var showMonth: Bool

    @Parameter(title: "Week", default: true)
    var showWeek: Bool

    @Parameter(title: "Day", default: true)
    var showDay: Bool
}

// MARK: - Trend Chart Widget Intent

enum TrendPeriod: Int, AppEnum {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static var caseDisplayRepresentations: [TrendPeriod: DisplayRepresentation] = [
        .sevenDays: "7 Days",
        .fourteenDays: "14 Days",
        .thirtyDays: "30 Days",
    ]
}

enum TrendDisplayContent: String, AppEnum {
    case both = "both"
    case eventsOnly = "events"
    case completionsOnly = "completions"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Content")
    static var caseDisplayRepresentations: [TrendDisplayContent: DisplayRepresentation] = [
        .both: "Events & Completions",
        .eventsOnly: "Events Only",
        .completionsOnly: "Completions Only",
    ]
}

struct TrendChartIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Trend Chart Settings"
    static var description = IntentDescription("Configure the trend chart display.")

    @Parameter(title: "Period", default: .sevenDays)
    var period: TrendPeriod

    @Parameter(title: "Content", default: .both)
    var displayContent: TrendDisplayContent

    @Parameter(title: "Show Completion Rate Bar", default: true)
    var showCompletionRate: Bool
}
