import SwiftUI
import Foundation

@main
struct TaskNotesApp: App {
    init() {
        // Make the window title bar transparent
        if let windowClass = NSClassFromString("NSWindow") as? NSWindow.Type {
            DispatchQueue.main.async {
                for window in NSApplication.shared.windows {
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .visible
                    window.styleMask.insert(.fullSizeContentView)
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Apply window styling when view appears
                    DispatchQueue.main.async {
                        if let window = NSApplication.shared.windows.first {
                            window.titlebarAppearsTransparent = true
                            window.titleVisibility = .visible
                            window.styleMask.insert(.fullSizeContentView)
                            window.isMovableByWindowBackground = true
                            window.title = "Untitled"
                        }
                    }
                }
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    // Create new file functionality
                    NotificationCenter.default.post(name: .newFile, object: nil)
                }
                .keyboardShortcut("n")
            }
            
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o")
                
                Divider()
            }
            
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .saveFile, object: nil)
                }
                .keyboardShortcut("s")
                
                Button("Save As...") {
                    saveAsFile()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            DataManager.shared.loadFromFile(url: url)
            
            // Update window title
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.title = url.lastPathComponent
                    window.representedURL = url
                }
            }
            
            // Post notification to refresh the UI
            NotificationCenter.default.post(name: .fileOpened, object: nil)
        }
    }
    
    private func saveAsFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "TaskNotes.txt"
        panel.canCreateDirectories = true
        
        if panel.runModal() == .OK {
            guard let url = panel.url else { return }
            DataManager.shared.saveCurrentDataTo(url: url)
            
            // Update window title
            DispatchQueue.main.async {
                if let window = NSApplication.shared.windows.first {
                    window.title = url.lastPathComponent
                    window.representedURL = url
                    window.isDocumentEdited = false
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var taskStore = TaskStore()
    @State private var notes = ""
    @State private var newTaskText = ""
    @State private var hasUnsavedChanges = false
    private let dataManager = DataManager.shared
    
    var body: some View {
        HSplitView {
            // Left side - Tasks
            VStack(alignment: .leading, spacing: 16) {
                Text("Today's Tasks")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                // Add new task
                HStack {
                    TextField("Add new task...", text: $newTaskText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            addTask()
                        }
                    
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                // Tasks list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(taskStore.tasks) { task in
                            TaskRow(task: task, onToggle: {
                                taskStore.toggleTask(task)
                                markAsEdited()
                            }, onDelete: {
                                taskStore.deleteTask(task)
                                markAsEdited()
                            })
                        }
                        
                        if taskStore.tasks.isEmpty {
                            Text("No tasks yet")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer()
            }
            .frame(minWidth: 300, maxWidth: 400)
            .background(Color(NSColor.controlBackgroundColor))
            
            // Right side - Notes
            VStack(alignment: .leading, spacing: 16) {
                Text("Notes")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                TextEditor(text: $notes)
                    .font(.system(.body, design: .default))
                    .scrollContentBackground(.hidden)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .padding(.horizontal)
                    .padding(.bottom)
            }
            .frame(minWidth: 400)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(Color.clear)
        .onAppear {
            loadNotes()
            setupWindowCloseHandler()
        }
        .onChange(of: notes) { _ in
            markAsEdited()
            saveNotes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fileOpened)) { _ in
            refreshFromFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .newFile)) { _ in
            createNewFile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { _ in
            saveCurrentFile()
        }
    }
    
    private func addTask() {
        guard !newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        taskStore.addTask(title: newTaskText)
        newTaskText = ""
        markAsEdited()
    }
    
    private func saveNotes() {
        dataManager.saveNotes(notes)
    }
    
    private func loadNotes() {
        notes = dataManager.loadNotes()
        hasUnsavedChanges = false
        updateWindowEditedState()
    }
    
    private func refreshFromFile() {
        taskStore.refreshTasks()
        notes = dataManager.loadNotes()
        hasUnsavedChanges = false
        updateWindowEditedState()
    }
    
    private func createNewFile() {
        // Show save dialog if there are unsaved changes
        if hasUnsavedChanges {
            showUnsavedChangesDialog {
                // Clear data for new file
                taskStore.clearTasks()
                notes = ""
                hasUnsavedChanges = false
                updateWindowTitle("Untitled")
                updateWindowEditedState()
            }
        } else {
            // Clear data for new file
            taskStore.clearTasks()
            notes = ""
            hasUnsavedChanges = false
            updateWindowTitle("Untitled")
            updateWindowEditedState()
        }
    }
    
    private func saveCurrentFile() {
        // If no current file, show Save As dialog
        if let window = NSApplication.shared.windows.first,
           let url = window.representedURL {
            dataManager.saveCurrentDataTo(url: url)
            hasUnsavedChanges = false
            updateWindowEditedState()
        } else {
            // No file associated, trigger Save As
            NotificationCenter.default.post(name: .saveAsFile, object: nil)
        }
    }
    
    private func markAsEdited() {
        hasUnsavedChanges = true
        updateWindowEditedState()
    }
    
    private func updateWindowEditedState() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.isDocumentEdited = hasUnsavedChanges
            }
        }
    }
    
    private func updateWindowTitle(_ title: String) {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.title = title
                window.representedURL = nil
            }
        }
    }
    
    private func setupWindowCloseHandler() {
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.delegate = WindowDelegate()
            }
        }
    }
    
    private func showUnsavedChangesDialog(onSave: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Save
            saveCurrentFile()
            onSave()
        case .alertSecondButtonReturn: // Don't Save
            onSave()
        default: // Cancel
            break
        }
    }
}

struct TaskRow: View {
    let task: Task
    let onToggle: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.isCompleted ? .green : .gray)
            }
            .buttonStyle(PlainButtonStyle())
            
            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundColor(task.isCompleted ? .secondary : .primary)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(PlainButtonStyle())
            .opacity(0.7)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

// MARK: - Window Delegate

class WindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender.isDocumentEdited {
            let alert = NSAlert()
            alert.messageText = "Do you want to save the changes?"
            alert.informativeText = "Your changes will be lost if you don't save them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // Save
                NotificationCenter.default.post(name: .saveFile, object: nil)
                return true
            case .alertSecondButtonReturn: // Don't Save
                return true
            default: // Cancel
                return false
            }
        }
        return true
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let fileOpened = Notification.Name("fileOpened")
    static let newFile = Notification.Name("newFile")
    static let saveFile = Notification.Name("saveFile")
    static let saveAsFile = Notification.Name("saveAsFile")
}

// MARK: - Data Manager

class DataManager {
    static let shared = DataManager()
    private let separator = "###$$###"
    private let fileName = "TaskNotes.txt"
    
    private var fileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent(fileName)
    }
    
    private init() {}
    
    // MARK: - File Operations
    
    func loadFromFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Validate the file has the correct structure
            if content.contains(separator) {
                // Save the opened file content to our app's file location
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            } else {
                // Show error - invalid file format
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Invalid File Format"
                    alert.informativeText = "The selected file doesn't have the expected TaskNotes format with the separator '###$$###'."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
                return
            }
        } catch {
            // Show error
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error Opening File"
                alert.informativeText = "Could not read the selected file: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    // MARK: - Tasks Management
    
    func saveTasks(_ tasks: [Task], to url: URL? = nil) {
        let notes = loadNotes()
        let tasksJSON = encodeTasksToJSON(tasks)
        let content = "\(tasksJSON)\n\(separator)\n\(notes)"
        
        let targetURL = url ?? fileURL
        
        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save tasks: \(error)")
        }
    }
    
    func loadTasks() -> [Task] {
        guard let content = readFile() else { return [] }
        
        let components = content.components(separatedBy: separator)
        guard let tasksString = components.first?.trimmingCharacters(in: .whitespacesAndNewlines) else { return [] }
        
        return decodeTasksFromJSON(tasksString)
    }
    
    // MARK: - Notes Management
    
    func saveNotes(_ notes: String, to url: URL? = nil) {
        let tasks = loadTasks()
        let tasksJSON = encodeTasksToJSON(tasks)
        let content = "\(tasksJSON)\n\(separator)\n\(notes)"
        
        let targetURL = url ?? fileURL
        
        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to save notes: \(error)")
        }
    }
    
    func saveCurrentDataTo(url: URL) {
        let tasks = loadTasks()
        let notes = loadNotes()
        let tasksJSON = encodeTasksToJSON(tasks)
        let content = "\(tasksJSON)\n\(separator)\n\(notes)"
        
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Error Saving File"
                alert.informativeText = "Could not save the file: \(error.localizedDescription)"
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
    
    func loadNotes() -> String {
        guard let content = readFile() else { return "" }
        
        let components = content.components(separatedBy: separator)
        guard components.count > 1 else { return "" }
        
        return components.dropFirst().joined(separator: separator).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper Methods
    
    private func readFile() -> String? {
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // File doesn't exist yet, that's okay
            return nil
        }
    }
    
    private func encodeTasksToJSON(_ tasks: [Task]) -> String {
        do {
            let data = try JSONEncoder().encode(tasks)
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            print("Failed to encode tasks: \(error)")
            return ""
        }
    }
    
    private func decodeTasksFromJSON(_ jsonString: String) -> [Task] {
        guard let data = jsonString.data(using: .utf8) else { return [] }
        
        do {
            return try JSONDecoder().decode([Task].self, from: data)
        } catch {
            print("Failed to decode tasks: \(error)")
            return []
        }
    }
    
    // MARK: - File Location Info
    
    func getFileLocation() -> String {
        return fileURL.path
    }
}

// MARK: - Data Models

struct Task: Identifiable, Codable {
    let id = UUID()
    var title: String
    var isCompleted: Bool = false
    let createdAt = Date()
}

class TaskStore: ObservableObject {
    @Published var tasks: [Task] = []
    private let dataManager = DataManager.shared
    
    init() {
        loadTasks()
    }
    
    func addTask(title: String) {
        let task = Task(title: title)
        tasks.insert(task, at: 0)
        saveTasks()
    }
    
    func toggleTask(_ task: Task) {
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isCompleted.toggle()
            saveTasks()
        }
    }
    
    func deleteTask(_ task: Task) {
        tasks.removeAll { $0.id == task.id }
        saveTasks()
    }
    
    func refreshTasks() {
        tasks = dataManager.loadTasks()
    }
    
    func clearTasks() {
        tasks = []
        saveTasks()
    }
    
    private func saveTasks() {
        dataManager.saveTasks(tasks)
    }
    
    private func loadTasks() {
        tasks = dataManager.loadTasks()
    }
}
