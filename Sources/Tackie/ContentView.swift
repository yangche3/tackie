import SwiftUI
import Combine
import AppKit

// The Command Line Tools ship without the SwiftUI macro plugin, so `@State` (now a macro
// in the macOS 27 SDK) cannot expand. This alias points straight at the property wrapper.
typealias ViewState = SwiftUI.State

// MARK: - Theme

extension NoteTheme {
    var color: Color {
        switch self {
        case .yellow: return Color(red: 1.00, green: 0.95, blue: 0.62)
        case .pink:   return Color(red: 1.00, green: 0.85, blue: 0.89)
        case .blue:   return Color(red: 0.81, green: 0.91, blue: 1.00)
        case .green:  return Color(red: 0.84, green: 0.96, blue: 0.80)
        case .purple: return Color(red: 0.91, green: 0.86, blue: 1.00)
        case .glass:  return .clear
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension Store {
    /// A font in the chosen style at an explicit size (used for the header, which has a fixed height).
    func noteFont(size: Double, weight: Font.Weight = .regular) -> Font {
        switch fontStyle {
        case .system:      return .system(size: size, weight: weight)
        case .rounded:     return .system(size: size, weight: weight, design: .rounded)
        case .serif:       return .system(size: size, weight: weight, design: .serif)
        case .mono:        return .system(size: size, weight: weight, design: .monospaced)
        case .handwriting: return .custom("Noteworthy", size: size).weight(weight)
        case .marker:      return .custom("Marker Felt", size: size).weight(weight)
        case .chalkboard:  return .custom("Chalkboard SE", size: size).weight(weight)
        case .bradley:     return .custom("Bradley Hand", size: size).weight(weight)
        }
    }

    /// A font for to-do text, scaled from the chosen text size (e.g. 0.8 for the reminder line).
    func itemFont(_ scale: Double = 1, weight: Font.Weight = .regular) -> Font {
        noteFont(size: fontSize * scale, weight: weight)
    }

    /// Scale factor for icons that sit next to to-do text.
    var iconScale: Double { fontSize / TextSizes.default }

    /// The AppKit font matching `itemFont`, used for real glyph measurements.
    func itemNSFont(_ scale: Double = 1) -> NSFont {
        let size = fontSize * scale
        let system = NSFont.systemFont(ofSize: size)
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            system.fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: size) } ?? system
        }
        switch fontStyle {
        case .system:      return system
        case .rounded:     return design(.rounded)
        case .serif:       return design(.serif)
        case .mono:        return design(.monospaced)
        case .handwriting: return NSFont(name: "Noteworthy", size: size) ?? system
        case .marker:      return NSFont(name: "Marker Felt", size: size) ?? system
        case .chalkboard:  return NSFont(name: "Chalkboard SE", size: size) ?? system
        case .bradley:     return NSFont(name: "Bradley Hand", size: size) ?? system
        }
    }

    /// Distance from the text baseline up to the visual middle of the letters
    /// (half the cap height) — where a checkbox's center should sit.
    var textMidlineAboveBaseline: CGFloat { itemNSFont().capHeight / 2 }
}

extension VerticalAlignment {
    /// Lines up a row's checkbox center with the visual middle of its first line of text.
    private enum FirstLineMid: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d[VerticalAlignment.center] }
    }
    static let firstLineMid = VerticalAlignment(FirstLineMid.self)
}

extension View {
    /// Marks this text's first-line midpoint as the row's `.firstLineMid` alignment.
    func firstLineMid(_ store: Store) -> some View {
        alignmentGuide(.firstLineMid) { d in d[.firstTextBaseline] - store.textMidlineAboveBaseline }
    }
}

/// Sticky colors are light, so force dark text on them; glass follows the system appearance.
struct ThemeScheme: ViewModifier {
    let theme: NoteTheme
    func body(content: Content) -> some View {
        if theme == .glass { content } else { content.environment(\.colorScheme, .light) }
    }
}

// MARK: - Main view

struct ContentView: View {
    @ObservedObject var store: Store
    let window: () -> NSWindow?
    let onHide: () -> Void

    @ViewState private var newText = ""
    @ViewState private var editingID: UUID?
    @ViewState private var now = Date()
    @ViewState private var dragStart: (origin: NSPoint, mouse: NSPoint)?
    @FocusState private var inputFocused: Bool
    @Namespace private var tabSpace

    private let ticker = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            switch store.tab {
            case .todo:
                list
            case .notes:
                NotesView(store: store)
            }
        }
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
        .background {
            if store.theme == .glass { VisualEffect() } else { store.theme.color }
        }
        .ignoresSafeArea()
        .modifier(ThemeScheme(theme: store.theme))
        .onReceive(ticker) { now = $0 }
    }

    // MARK: Header (also the drag handle)

    /// Row 1: today's date + window buttons.  Row 2: the full-width To-do | Notes switch.
    private var header: some View {
        VStack(spacing: 6) {
            topBar
            tabSwitcher
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .gesture(windowDrag)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            // Today's date — longest form that fits:
            // "Thursday, Nov 19, 2026" → "Thu, Nov 19, 2026" → "Thu, Nov 19" → "Thu".
            ViewThatFits(in: .horizontal) {
                dateText(now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                dateText(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                dateText(now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                dateText(now.formatted(.dateTime.weekday(.abbreviated)))
            }
            Spacer(minLength: 0)
            Button { store.alwaysOnTop.toggle() } label: {
                Image(systemName: store.alwaysOnTop ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(store.alwaysOnTop ? 0 : 45))
            }
            .buttonStyle(.plain)
            .foregroundStyle(store.alwaysOnTop ? Color.primary : Color.secondary)
            .help(store.alwaysOnTop ? "Pinned on top — click to let other windows cover it"
                                    : "Not pinned — click to keep it above other windows")
            settingsMenu
            Button(action: onHide) {
                Image(systemName: "minus").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide (⌃⌥T to bring back)")
        }
        .padding(.horizontal, 2)
    }

    // MARK: Tabs — a pill-shaped switch so the two sections are hard to miss

    private var tabSwitcher: some View {
        HStack(spacing: 2) {
            tabSegment("To-do", icon: "checklist", .todo, badge: store.remainingCount)
            tabSegment("Notes", icon: "note.text", .notes, badge: 0)
        }
        .padding(2)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
    }

    private func tabSegment(_ title: String, icon: String, _ tab: Tab, badge: Int) -> some View {
        let selected = store.tab == tab
        let selectedFill = store.theme == .glass ? Color.primary.opacity(0.18) : Color.white.opacity(0.95)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { store.tab = tab }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).font(store.noteFont(size: 13, weight: selected ? .semibold : .medium))
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.12)))
                }
            }
            .lineLimit(1)
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)                 // two equal halves
            .padding(.vertical, 5)
            .background {
                if selected {
                    Capsule()
                        .fill(selectedFill)
                        .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                        .matchedGeometryEffect(id: "selectedTab", in: tabSpace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab == .todo ? "To-do list (⌘1)" : "Quick notes (⌘2)")
    }

    private func dateText(_ s: String) -> some View {
        Text(s)
            .font(store.noteFont(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var windowDrag: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { _ in
                guard let w = window() else { return }
                let mouse = NSEvent.mouseLocation
                if dragStart == nil { dragStart = (w.frame.origin, mouse) }
                guard let s = dragStart else { return }
                w.setFrameOrigin(NSPoint(x: s.origin.x + mouse.x - s.mouse.x,
                                         y: s.origin.y + mouse.y - s.mouse.y))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var settingsMenu: some View {
        Menu {
            Picker("Color", selection: $store.theme) {
                ForEach(NoteTheme.allCases) { Text($0.name).tag($0) }
            }
            Picker("Opacity", selection: $store.opacity) {
                Text("100%").tag(1.0)
                Text("85%").tag(0.85)
                Text("70%").tag(0.7)
                Text("50%").tag(0.5)
            }
            Picker("Text Size", selection: $store.fontSize) {
                ForEach(TextSizes.all, id: \.size) { Text($0.name).tag($0.size) }
            }
            Picker("Font", selection: $store.fontStyle) {
                ForEach(NoteFont.allCases) { Text($0.name).tag($0) }
            }
            Divider()
            Button("New Note  ⌃⌥N") { store.newNote() }
            Button("Export All Notes…") { NoteExport.exportAll(store.notes) }
                .disabled(store.notes.allSatisfy(\.isBlank))
            Divider()
            Toggle("Keep on Top", isOn: $store.alwaysOnTop)
            Toggle("Reminder Alerts", isOn: $store.alertsEnabled)
            Toggle("Hide Completed", isOn: $store.hideCompleted)
            Button("Clear Completed") { withAnimation { store.clearCompleted() } }
                .disabled(!store.items.contains(where: \.done))
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
    }

    // MARK: List

    // Open items, then the "new to-do" row, then completed items — like Reminders.
    private var openItems: [TodoItem] { store.items.filter { !$0.done } }
    private var doneItems: [TodoItem] { store.hideCompleted ? [] : store.items.filter(\.done) }
    private static let newRowID = "new-todo-row"

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(openItems) { item in row(item) }
                    .onMove { from, to in
                        var ids = openItems.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        store.reorder(visibleIDs: ids + doneItems.map(\.id))
                    }

                newTodoRow
                    .id(Self.newRowID)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 8))

                ForEach(doneItems) { item in row(item) }
                    .onMove { from, to in
                        var ids = doneItems.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        store.reorder(visibleIDs: openItems.map(\.id) + ids)
                    }

                // Clicking the blank space under the list starts a new to-do.
                Color.clear
                    .frame(height: 60)
                    .contentShape(Rectangle())
                    .onTapGesture { focusNewRow(proxy) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: store.newEntryRequest) { _ in
                if store.tab == .todo { focusNewRow(proxy) }
            }
            // Arriving on this tab (or showing the window) → cursor ready in the new-to-do row.
            .onAppear { focusSoon(proxy) }
            .onChange(of: store.focusRequest) { _ in
                if store.tab == .todo && editingID == nil { focusSoon(proxy) }
            }
            .onChange(of: openItems.count) { _ in
                if inputFocused { proxy.scrollTo(Self.newRowID) }
            }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        TodoRow(item: item, store: store, editingID: $editingID, now: now,
                onReturn: { inputFocused = true })
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 8))
    }

    /// Focus after the window has had a moment to become key.
    private func focusSoon(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focusNewRow(proxy) }
    }

    private func focusNewRow(_ proxy: ScrollViewProxy) {
        editingID = nil
        withAnimation { proxy.scrollTo(Self.newRowID) }
        inputFocused = true
    }

    /// The always-present empty row you type into to add a to-do.
    private var newTodoRow: some View {
        HStack(alignment: .firstLineMid, spacing: 8) {
            Image(systemName: inputFocused ? "circle" : "plus.circle")
                .font(.system(size: 15 * store.iconScale))
                .foregroundStyle(Color.primary.opacity(inputFocused ? 0.45 : 0.25))
                .onTapGesture { inputFocused = true }
            VStack(alignment: .leading, spacing: 2) {
                TextField("New to-do", text: $newText)
                    .textFieldStyle(.plain)
                    .font(store.itemFont())
                    .firstLineMid(store)
                    .focused($inputFocused)
                    .onSubmit {
                        let text = newText
                        newText = ""
                        if text.trimmingCharacters(in: .whitespaces).isEmpty {
                            inputFocused = false              // Return on an empty row = done adding
                        } else {
                            withAnimation(.easeOut(duration: 0.15)) { store.add(text) }
                            inputFocused = true               // stay ready for the next one
                        }
                    }
                    .onExitCommand { newText = ""; inputFocused = false }
                    .onChange(of: newText) { text in
                        // Typing can't add a line break here, so one means a pasted list:
                        // add each line as its own to-do.
                        guard text.contains(where: \.isNewline) else { return }
                        newText = ""
                        withAnimation(.easeOut(duration: 0.15)) { store.addLines(text) }
                    }
                if let due = Store.detectDate(in: newText) {
                    DueHint(date: due).font(store.itemFont(0.8))
                }
            }
        }
    }
}

// MARK: - Small pieces

/// "🔔 Tomorrow 5:00 PM" preview shown while typing, before the text is saved.
struct DueHint: View {
    let date: Date?
    var removed = false
    var body: some View {
        if let date {
            Label("Will remind \(TodoRow.format(date))", systemImage: "bell.badge")
                .foregroundStyle(Color.accentColor)
        } else if removed {
            Label("Reminder will be removed", systemImage: "bell.slash")
                .foregroundStyle(.secondary)
        }
    }
}

struct QuickChip: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize()                       // never wrap the label
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Row

struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var store: Store
    @Binding var editingID: UUID?
    let now: Date
    /// Called when Return finishes an edit, so the caller can move on to the new-to-do row.
    var onReturn: () -> Void = {}

    @ViewState private var hovering = false
    @ViewState private var draft = ""
    @ViewState private var showPicker = false
    @ViewState private var pickedDate = Date().addingTimeInterval(3600)
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { editingID == item.id }

    var body: some View {
        HStack(alignment: .firstLineMid, spacing: 8) {
            Button { withAnimation(.easeOut(duration: 0.2)) { store.toggle(item.id) } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15 * store.iconScale))
                    .foregroundStyle(item.done ? Color.accentColor : Color.primary.opacity(0.45))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(store.itemFont())
                        .firstLineMid(store)
                        .focused($fieldFocused)
                        .onAppear { draft = item.title; fieldFocused = true }
                        .onSubmit { commit(); onReturn() }
                        .onExitCommand { editingID = nil }
                        .onChange(of: fieldFocused) { focused in if !focused { commit() } }
                } else {
                    Text(Store.linked(item.title))
                        .font(store.itemFont())
                        .firstLineMid(store)
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        // Simultaneous, so a single click on a link still opens it.
                        .simultaneousGesture(TapGesture(count: 2).onEnded { editingID = item.id })
                }
                if isEditing {
                    // Live preview of what the reminder will be once the edit is saved.
                    let (previewDue, _) = Store.resolveDue(for: item, newTitle: draft)
                    if previewDue != item.due {
                        DueHint(date: previewDue, removed: previewDue == nil)
                            .font(store.itemFont(0.8))
                    } else if let due = item.due {
                        dueLabel(due)
                    }
                } else if let due = item.due {
                    Button { openPicker() } label: { dueLabel(due) }
                        .buttonStyle(.plain)
                        .help("Change reminder")
                }
            }

            Spacer(minLength: 0)

            if item.due == nil && !item.done {
                Button { openPicker() } label: {
                    Image(systemName: "bell").font(.system(size: 10 * store.iconScale, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Add reminder")
            }

            Button { withAnimation { store.delete(item.id) } } label: {
                Image(systemName: "xmark").font(.system(size: 10 * store.iconScale, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering ? 1 : 0)
        }
        .onHover { hovering = $0 }
        .contextMenu { menu }
        .popover(isPresented: $showPicker, arrowEdge: .bottom) { picker }
    }

    private func commit() {
        guard isEditing else { return }
        store.rename(item.id, to: draft)
        editingID = nil
    }

    private func dueLabel(_ due: Date) -> some View {
        Label(Self.format(due), systemImage: "bell.fill")
            .font(store.itemFont(0.8))
            .foregroundStyle(due < now && !item.done ? Color.red : Color.secondary)
    }

    private func openPicker() {
        pickedDate = item.due.map { max($0, Date()) } ?? Self.roundedHourFromNow()
        showPicker = true
    }

    private func setAndClose(_ date: Date?) {
        store.setDue(item.id, date)
        showPicker = false
    }

    /// The next full hour, at least ~30 min away (e.g. 2:40 → 4:00, 2:10 → 3:00).
    static func roundedHourFromNow() -> Date {
        let cal = Calendar.current
        let base = Date().addingTimeInterval(30 * 60)
        let hour = cal.dateInterval(of: .hour, for: base)?.start ?? base
        return cal.date(byAdding: .hour, value: 1, to: hour) ?? base
    }

    @ViewBuilder private var menu: some View {
        Button("Edit") { editingID = item.id }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.title, forType: .string)
        }
        ForEach(Store.links(in: item.title), id: \.self) { url in
            Button("Open \(Self.shortName(url))") { NSWorkspace.shared.open(url) }
        }
        Menu("Remind Me") {
            Button("In 15 Minutes") { store.setDue(item.id, Date().addingTimeInterval(15 * 60)) }
            Button("In 1 Hour") { store.setDue(item.id, Date().addingTimeInterval(3600)) }
            if Calendar.current.component(.hour, from: Date()) < 18 {
                Button("This Evening (6 PM)") { store.setDue(item.id, Self.at(hour: 18, daysAhead: 0)) }
            }
            Button("Tomorrow Morning (9 AM)") { store.setDue(item.id, Self.at(hour: 9, daysAhead: 1)) }
            Divider()
            Button("Pick Date & Time…") { openPicker() }
        }
        if item.due != nil {
            Button("Remove Reminder") { store.setDue(item.id, nil) }
        }
        Divider()
        Button(item.done ? "Mark as Not Done" : "Mark as Done") { store.toggle(item.id) }
        Button("Delete") { store.delete(item.id) }
    }

    /// "github.com" for a web link, the address for an email link.
    static func shortName(_ url: URL) -> String {
        if url.scheme == "mailto" { return url.absoluteString.replacingOccurrences(of: "mailto:", with: "") }
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Quick picks
            HStack(spacing: 6) {
                QuickChip("+15 min") { setAndClose(Date().addingTimeInterval(15 * 60)) }
                QuickChip("+1 hour") { setAndClose(Date().addingTimeInterval(3600)) }
                if Calendar.current.component(.hour, from: Date()) < 18 {
                    QuickChip("Tonight") { setAndClose(Self.at(hour: 18, daysAhead: 0)) }
                }
                QuickChip("Tomorrow") { setAndClose(Self.at(hour: 9, daysAhead: 1)) }
            }
            .fixedSize()                           // row sets the popover's minimum width
            Divider()
            DatePicker("", selection: $pickedDate, in: Date()..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Text("Time").foregroundStyle(.secondary)
                DatePicker("", selection: $pickedDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
            }
            HStack {
                if item.due != nil {
                    Button("Remove", role: .destructive) { setAndClose(nil) }
                }
                Spacer()
                Button("Cancel") { showPicker = false }
                    .keyboardShortcut(.cancelAction)
                Button("Set") { setAndClose(pickedDate) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .fixedSize()                               // size to content instead of a fixed width
    }

    static func at(hour: Int, daysAhead: Int) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: daysAhead, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func format(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return "Today \(time)" }
        if cal.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
