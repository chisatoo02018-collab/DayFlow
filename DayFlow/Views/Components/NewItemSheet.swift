import SwiftUI
import EventKitUI

struct NewItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: NewItemType = .event
    @State private var showEventEditor = false
    @State private var showReminderForm = false

    var onSaved: (() async -> Void)?

    enum NewItemType: String, CaseIterable {
        case event = "Event"
        case reminder = "Reminder"

        var icon: String {
            switch self {
            case .event: "calendar.badge.plus"
            case .reminder: "checklist"
            }
        }

        var color: Color {
            switch self {
            case .event: .blue
            case .reminder: .green
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(NewItemType.allCases, id: \.self) { type in
                    Button {
                        switch type {
                        case .event: showEventEditor = true
                        case .reminder: showReminderForm = true
                        }
                    } label: {
                        Label {
                            Text(type.rawValue)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: type.icon)
                                .foregroundStyle(type.color)
                        }
                    }
                }
            }
            .navigationTitle("New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showEventEditor) {
                EventEditView {
                    dismiss()
                    Task { await onSaved?() }
                }
            }
            .sheet(isPresented: $showReminderForm) {
                NewReminderView {
                    dismiss()
                    Task { await onSaved?() }
                }
            }
        }
    }
}

// MARK: - Native Calendar Event Editor

struct EventEditView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = EKEventStore()
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss, onSaved: onSaved)
    }

    class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: DismissAction
        let onSaved: () -> Void

        init(dismiss: DismissAction, onSaved: @escaping () -> Void) {
            self.dismiss = dismiss
            self.onSaved = onSaved
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
            if action == .saved {
                onSaved()
            }
        }
    }
}

// MARK: - New Reminder Form

struct NewReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var priority: Int = 0
    @State private var saving = false

    var onSaved: () -> Void

    private let store = EKEventStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Due Date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate)
                    }
                }

                Section {
                    Picker("Priority", selection: $priority) {
                        Text("None").tag(0)
                        Text("Low").tag(9)
                        Text("Medium").tag(5)
                        Text("High").tag(1)
                    }
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || saving)
                }
            }
        }
    }

    private func save() {
        saving = true
        let reminder = EKReminder(eventStore: store)
        reminder.title = title.trimmingCharacters(in: .whitespaces)
        if !notes.trimmingCharacters(in: .whitespaces).isEmpty {
            reminder.notes = notes
        }
        if hasDueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate
            )
        }
        reminder.priority = priority
        reminder.calendar = store.defaultCalendarForNewReminders()

        do {
            try store.save(reminder, commit: true)
            dismiss()
            onSaved()
        } catch {
            saving = false
        }
    }
}
