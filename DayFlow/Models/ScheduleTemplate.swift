import Foundation

struct ScheduleTemplate: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var blocks: [TimeBlock]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, blocks: [TimeBlock], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.createdAt = createdAt
    }
}
