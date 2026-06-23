import Foundation

@Observable
final class GoogleTasksService {
    private let authManager: GoogleAuthManager
    private let client: GoogleAPIClient

    init(authManager: GoogleAuthManager) {
        self.authManager = authManager
        self.client = GoogleAPIClient(authManager: authManager)
    }

    func fetchReminders() async -> [ReminderItem] {
        guard authManager.isSignedIn else { return [] }
        guard let lists = try? await fetchTaskLists() else { return [] }

        var all: [ReminderItem] = []
        for list in lists {
            if let items = try? await fetchTasks(in: list) {
                all.append(contentsOf: items)
            }
        }
        return all
    }

    func setCompletion(_ item: ReminderItem, completed: Bool) async {
        guard item.source == .google, let listId = item.googleTaskListId else { return }
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/lists/\(listId)/tasks/\(item.id)")!
        struct Patch: Encodable { let status: String }
        let _: GoogleTaskDTO? = try? await client.patch(url, body: Patch(status: completed ? "completed" : "needsAction"))
    }

    private func fetchTaskLists() async throws -> [GoogleTaskListDTO] {
        let url = URL(string: "https://tasks.googleapis.com/tasks/v1/users/@me/lists")!
        let response: GoogleTaskListsResponse = try await client.get(url)
        return response.items ?? []
    }

    private func fetchTasks(in list: GoogleTaskListDTO) async throws -> [ReminderItem] {
        var components = URLComponents(string: "https://tasks.googleapis.com/tasks/v1/lists/\(list.id)/tasks")!
        components.queryItems = [
            URLQueryItem(name: "showCompleted", value: "true"),
            URLQueryItem(name: "showHidden", value: "true")
        ]
        guard let url = components.url else { return [] }

        let response: GoogleTasksResponse = try await client.get(url)
        return (response.items ?? []).map { dto in
            ReminderItem(
                googleTaskId: dto.id,
                title: dto.title ?? "No Title",
                dueDate: dto.due.flatMap(Self.parseDueDate),
                isCompleted: dto.status == "completed",
                notes: dto.notes,
                listId: list.id,
                listTitle: list.title
            )
        }
    }

    private static func parseDueDate(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

private struct GoogleTaskListsResponse: Decodable {
    let items: [GoogleTaskListDTO]?
}

private struct GoogleTaskListDTO: Decodable {
    let id: String
    let title: String
}

private struct GoogleTasksResponse: Decodable {
    let items: [GoogleTaskDTO]?
}

private struct GoogleTaskDTO: Decodable {
    let id: String
    let title: String?
    let notes: String?
    let status: String
    let due: String?
}
