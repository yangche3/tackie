import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var done = false
    var due: Date?
    /// True when `due` was read from the title text (vs. set by hand), so editing
    /// the text may move or remove it. Optional so older saved files still load.
    var dueFromText: Bool?
    /// The due time we've already alerted for (so each reminder pops up once).
    var alertedFor: Date?
    var created = Date()
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var created = Date()
    var updated = Date()

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    /// First non-empty line (minus any leading Markdown "#"), or a placeholder.
    var title: String {
        guard let first = lines.first else { return "New Note" }
        let t = first.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "New Note" : t
    }
    var preview: String { lines.dropFirst().first ?? "" }
    var isBlank: Bool { lines.isEmpty }
}

enum Tab: String { case todo, notes }

enum NoteTheme: String, CaseIterable, Identifiable {
    case yellow, pink, blue, green, purple, glass
    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

enum NoteFont: String, CaseIterable, Identifiable {
    case system, rounded, serif, mono, handwriting, marker, chalkboard, bradley
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .mono: return "Monospaced"
        case .handwriting: return "Noteworthy"
        case .marker: return "Marker Felt"
        case .chalkboard: return "Chalkboard"
        case .bradley: return "Bradley Hand"
        }
    }
}

/// Text size presets (points for a to-do's title).
enum TextSizes {
    static let all: [(name: String, size: Double)] = [
        ("Small", 11), ("Default", 13), ("Large", 15), ("Larger", 17), ("Huge", 20), ("Giant", 24)
    ]
    static let `default` = 13.0
    static func step(_ current: Double, by delta: Int) -> Double {
        let sizes = all.map(\.size)
        let i = sizes.firstIndex(where: { $0 >= current }) ?? sizes.count - 1
        return sizes[min(max(i + delta, 0), sizes.count - 1)]
    }
}

/// Holds the to-do list and settings, persists them, and keeps notifications in sync.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var items: [TodoItem] = [] { didSet { save() } }
    @Published var notes: [Note] = [] { didSet { scheduleNotesSave() } }
    @Published var openNoteID: UUID?
    /// IDs of to-dos whose reminder card is showing right now.
    @Published var alerting: [UUID] = []
    /// Bumped when the window is shown; the visible tab puts the cursor in its new-item row.
    @Published var focusRequest = 0
    /// Bumped by ⌘N; the visible tab responds by starting a new to-do / note.
    @Published var newEntryRequest = 0
    @Published var tab: Tab { didSet { defaults.set(tab.rawValue, forKey: "tab") } }
    @Published var theme: NoteTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    @Published var opacity: Double { didSet { defaults.set(opacity, forKey: "opacity") } }
    @Published var hideCompleted: Bool { didSet { defaults.set(hideCompleted, forKey: "hideCompleted") } }
    @Published var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    @Published var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    /// Off = reminders are silent: no pop-up card, no sound (times still show in the list).
    @Published var alertsEnabled: Bool {
        didSet {
            defaults.set(alertsEnabled, forKey: "alertsEnabled")
            if !alertsEnabled { alerting.removeAll() }
        }
    }
    @Published var fontStyle: NoteFont { didSet { defaults.set(fontStyle.rawValue, forKey: "fontStyle") } }

    private let defaults = UserDefaults.standard
    private let fileURL: URL
    private let notesURL: URL
    private var pendingNotesSave: DispatchWorkItem?

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tackie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("tasks.json")
        notesURL = dir.appendingPathComponent("notes.json")
        tab = Tab(rawValue: defaults.string(forKey: "tab") ?? "") ?? .todo

        theme = NoteTheme(rawValue: defaults.string(forKey: "theme") ?? "") ?? .yellow
        let savedOpacity = defaults.double(forKey: "opacity")
        opacity = savedOpacity == 0 ? 1 : savedOpacity
        hideCompleted = defaults.bool(forKey: "hideCompleted")
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        let savedSize = defaults.double(forKey: "fontSize")
        fontSize = savedSize == 0 ? TextSizes.default : savedSize
        alertsEnabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        fontStyle = NoteFont(rawValue: defaults.string(forKey: "fontStyle") ?? "") ?? .system

        items = Self.load([TodoItem].self, from: fileURL) ?? []
        notes = Self.load([Note].self, from: notesURL) ?? []
        isLoaded = true          // from here on, changes are written to disk
    }

    /// False while loading, so assigning the loaded lists doesn't immediately rewrite the files.
    private var isLoaded = false

    /// Reads a data file. If it exists but can't be read, it's renamed to
    /// "<name>.unreadable-<date>.json" so a later save can never overwrite the user's data.
    private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }   // no file yet
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let value = try? decoder.decode(type, from: data) { return value }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: backup)
        NSLog("Tackie: couldn't read \(url.lastPathComponent); kept it as \(backup.lastPathComponent)")
        return nil
    }

    // MARK: - Notes

    var sortedNotes: [Note] { notes.sorted { $0.updated > $1.updated } }

    /// Opens a fresh note (reusing the open one if it's still blank).
    /// With a title, the note starts as "title⏎" so you continue on the next line.
    func newNote(title: String = "") {
        tab = .notes
        let title = title.trimmingCharacters(in: .whitespaces)
        if let id = openNoteID, let i = notes.firstIndex(where: { $0.id == id }), notes[i].isBlank {
            if !title.isEmpty { notes[i].text = title + "\n" }
            return
        }
        let note = Note(text: title.isEmpty ? "" : title + "\n")
        notes.append(note)
        openNoteID = note.id
    }

    func openNote(_ id: UUID) {
        discardBlankOpenNote()
        openNoteID = id
    }

    func closeNote() {
        discardBlankOpenNote()
        openNoteID = nil
    }

    func updateNote(_ id: UUID, text: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].text != text else { return }
        notes[i].text = text
        notes[i].updated = Date()
    }

    func deleteNote(_ id: UUID) {
        if openNoteID == id { openNoteID = nil }
        notes.removeAll { $0.id == id }
    }

    private func discardBlankOpenNote() {
        if let id = openNoteID, notes.first(where: { $0.id == id })?.isBlank == true {
            notes.removeAll { $0.id == id }
        }
    }

    /// Typing changes notes on every keystroke, so batch writes slightly.
    private func scheduleNotesSave() {
        guard isLoaded else { return }
        pendingNotesSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNotesNow() }
        pendingNotesSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNotesNow() {
        guard isLoaded else { return }
        pendingNotesSave?.cancel()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(notes.filter { !$0.isBlank }) {
            try? data.write(to: notesURL, options: .atomic)
        }
    }

    var remainingCount: Int { items.filter { !$0.done }.count }

    // MARK: - Mutations

    func add(_ rawText: String) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let due = Self.detectDate(in: text)
        let item = TodoItem(title: text, due: due, dueFromText: due != nil)
        // New items go above the completed ones.
        let insertAt = items.firstIndex(where: { $0.done }) ?? items.count
        items.insert(item, at: insertAt)
        syncAlert(item)
    }

    /// Adds one to-do per line of pasted text, dropping list markers like "- ", "• ", "1. " and "[ ] ".
    func addLines(_ text: String) {
        let marker = #/^\s*(?:[-*•–]|\d+[.)]|\[[ xX]?\])\s+/#
        for line in text.split(whereSeparator: \.isNewline) {
            add(String(line).replacing(marker, with: ""))
        }
    }

    func toggle(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.done.toggle()
        if item.done {
            items.append(item)                       // sink to bottom
        } else {
            let insertAt = items.firstIndex(where: { $0.done }) ?? items.count
            items.insert(item, at: insertAt)         // back above completed
        }
        syncAlert(item)
    }

    func rename(_ id: UUID, to title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        if t.isEmpty { delete(id); return }
        let (due, fromText) = Self.resolveDue(for: items[i], newTitle: t)
        items[i].title = t
        items[i].due = due
        items[i].dueFromText = fromText
        syncAlert(items[i])
    }

    /// What the reminder becomes if `item` is retitled to `newTitle`:
    /// - the time phrase changed ("5pm" → "7pm")  → follow the new text
    /// - the time phrase was deleted              → drop the reminder, unless it was set by hand
    /// - the time phrase is unchanged             → keep the current reminder (incl. manual tweaks)
    static func resolveDue(for item: TodoItem, newTitle: String) -> (Date?, Bool?) {
        let old = detectDateMatch(in: item.title)
        let new = detectDateMatch(in: newTitle)
        guard old?.phrase != new?.phrase else { return (item.due, item.dueFromText) }
        if let new { return (new.date, true) }
        return item.dueFromText == true ? (nil, nil) : (item.due, item.dueFromText)
    }

    func setDue(_ id: UUID, _ date: Date?) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].due = date
        items[i].dueFromText = false
        syncAlert(items[i])
    }

    func delete(_ id: UUID) {
        clearAlert(id)
        items.removeAll { $0.id == id }
    }

    func clearCompleted() {
        items.filter(\.done).forEach { clearAlert($0.id) }
        items.removeAll(where: \.done)
    }

    /// Reorders using the visible IDs (in their new order); hidden items keep going at the end.
    func reorder(visibleIDs: [UUID]) {
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let visibleSet = Set(visibleIDs)
        items = visibleIDs.compactMap { lookup[$0] } + items.filter { !visibleSet.contains($0.id) }
    }

    // MARK: - Persistence

    private func save() {
        guard isLoaded else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Reminder alerts
    //
    // The app shows due reminders itself (a floating card) instead of using macOS
    // notifications, which aren't allowed for an app without an Apple-issued signature.

    /// To-dos whose reminder is currently showing, oldest first.
    var alertingItems: [TodoItem] {
        alerting.compactMap { id in items.first { $0.id == id && !$0.done } }
    }

    /// Checks for reminders that just came due; returns true if any new one fired.
    /// Each reminder fires once per due time (changing the time re-arms it).
    /// Reminders more than 12 hours overdue (e.g. while the Mac was off) don't pop up.
    @discardableResult
    func checkDueReminders(now: Date = Date()) -> Bool {
        var fired = false
        for i in items.indices {
            guard !items[i].done, let due = items[i].due, due <= now,
                  now.timeIntervalSince(due) < 12 * 3600,
                  items[i].alertedFor != due else { continue }
            // Marked even when alerts are off, so switching them on later doesn't replay old ones.
            items[i].alertedFor = due
            guard alertsEnabled else { continue }
            if !alerting.contains(items[i].id) { alerting.append(items[i].id) }
            fired = true
        }
        return fired
    }

    func snooze(_ id: UUID, until date: Date) { setDue(id, date) }

    func completeFromAlert(_ id: UUID) {
        if items.first(where: { $0.id == id })?.done == false { toggle(id) }
        clearAlert(id)
    }

    func dismissAlert(_ id: UUID) { clearAlert(id) }

    /// After any change to an item: drop its showing alert if it's done or no longer due.
    private func syncAlert(_ item: TodoItem) {
        if item.done || (item.due ?? .distantPast) > Date() || item.due == nil { clearAlert(item.id) }
    }

    private func clearAlert(_ id: UUID) {
        alerting.removeAll { $0 == id }
    }

    // MARK: - Natural-language dates ("call mom at 5pm", "pay rent tomorrow 9am")

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func detectDate(in text: String) -> Date? { detectDateMatch(in: text)?.date }

    /// The first future date mentioned in `text`, plus the exact words that produced it.
    static func detectDateMatch(in text: String) -> (date: Date, phrase: String)? {
        guard let detector,
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              var date = match.date,
              let range = Range(match.range, in: text) else { return nil }
        // "at 5pm" typed at 6pm means tomorrow, not an already-missed reminder.
        let now = Date()
        if date < now, now.timeIntervalSince(date) < 24 * 3600 {
            date = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
        }
        guard date > now else { return nil }
        return (date, text[range].lowercased().trimmingCharacters(in: .whitespaces))
    }
}
