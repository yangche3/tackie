import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The "Notes" tab: a list of quick notes, or the editor for the open one.
struct NotesView: View {
    @ObservedObject var store: Store

    var body: some View {
        if let id = store.openNoteID, let note = store.notes.first(where: { $0.id == id }) {
            NoteEditor(store: store, note: note)
                .id(note.id)            // fresh editor (and focus) per note
        } else {
            NotesList(store: store)
        }
    }
}

// MARK: - List

struct NotesList: View {
    @ObservedObject var store: Store
    @ViewState private var newTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        List {
            // Type a title right here; Return opens the note with the cursor on the next line.
            HStack(alignment: .firstLineMid, spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13 * store.iconScale))
                    .foregroundStyle(Color.primary.opacity(titleFocused ? 0.5 : 0.3))
                    .onTapGesture { store.newNote() }
                    .help("Blank note (⌃⌥N)")
                TextField("New note…", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(store.itemFont(weight: .medium))
                    .firstLineMid(store)
                    .focused($titleFocused)
                    .onSubmit {
                        let title = newTitle
                        newTitle = ""
                        store.newNote(title: title)
                    }
                    .onExitCommand { newTitle = ""; titleFocused = false }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 6)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 2, trailing: 8))

            ForEach(store.sortedNotes.filter { !$0.isBlank }) { note in
                NoteRow(store: store, note: note)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Arriving on this list (tab switch, closing a note, showing the window) → ready to type.
        .onAppear(perform: focusSoon)
        .onChange(of: store.focusRequest) { _ in focusSoon() }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { titleFocused = true }
    }
}

struct NoteRow: View {
    @ObservedObject var store: Store
    let note: Note
    @ViewState private var hovering = false

    var body: some View {
        Button { store.openNote(note.id) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(store.itemFont(weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(TodoRow.format(note.updated))
                    if !note.preview.isEmpty {
                        Text(note.preview).lineLimit(1).foregroundStyle(.tertiary)
                    }
                }
                .font(store.itemFont(0.8))
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu { NoteActions(store: store, note: note) }
    }
}

// MARK: - Editor

struct NoteEditor: View {
    @ObservedObject var store: Store
    let note: Note
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { store.closeNote() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11 * store.iconScale, weight: .semibold))
                        Text("All Notes")
                    }
                }
                .buttonStyle(.plain)
                .help("Back to all notes (empty notes are discarded)")
                Spacer(minLength: 4)
                Text(TodoRow.format(note.created))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                ShareButton(
                    pointSize: 12 * store.iconScale,
                    text: { store.notes.first(where: { $0.id == note.id })?.text ?? "" },
                    subject: { store.notes.first(where: { $0.id == note.id })?.title ?? "" },
                    extras: {
                        let current = store.notes.first(where: { $0.id == note.id }) ?? note
                        return NoteExport.airDropService(current) + [
                            .custom(title: "Copy Text", symbol: "doc.on.doc") { NoteExport.copy(current) },
                            .custom(title: "Save As File…", symbol: "square.and.arrow.down") { NoteExport.saveAs(current) },
                        ]
                    })
                    .fixedSize()
                    .disabled(note.isBlank)
                Button { store.deleteNote(note.id) } label: {
                    Image(systemName: "trash").font(.system(size: 11 * store.iconScale))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete this note")
            }
            .font(store.itemFont(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            TextEditor(text: Binding(
                get: { store.notes.first(where: { $0.id == note.id })?.text ?? "" },
                set: { store.updateNote(note.id, text: $0) }))
                .font(store.itemFont())
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
        }
        .onAppear {
            // Give the panel a moment to become key, put the cursor in the note,
            // then move it to the end so you keep writing where you left off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focused = true
                DispatchQueue.main.async {
                    let window = NSApp.windows.first(where: \.isKeyWindow)
                    if let tv = window?.firstResponder as? NSTextView {
                        tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                        tv.scrollRangeToVisible(tv.selectedRange())
                    }
                }
            }
        }
    }
}

/// Copy / Save As / Delete — shared by the row context menu and the editor's share menu.
struct NoteActions: View {
    @ObservedObject var store: Store
    let note: Note

    var body: some View {
        // Shows as a "Share" submenu: AirDrop, Mail, Messages, Notes…
        ShareLink(item: note.text, subject: Text(note.title)) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(note.isBlank)
        Button("Copy Text") { NoteExport.copy(note) }
            .disabled(note.isBlank)
        Button("Save As File…") { NoteExport.saveAs(note) }
            .disabled(note.isBlank)
        Divider()
        Button("Delete Note") { store.deleteNote(note.id) }
    }
}

// MARK: - Share button (the system share menu: AirDrop, Mail, Messages, Notes…)

struct ShareButton: NSViewRepresentable {
    var pointSize: CGFloat
    let text: () -> String
    let subject: () -> String
    /// Our own entries (Copy, Save As…) listed alongside the system services.
    let extras: () -> [NSSharingService]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up",
                                             accessibilityDescription: "Share")!,
                              target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = "Share — AirDrop, Mail, Messages, copy, save as file…"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.symbolConfiguration = .init(pointSize: pointSize, weight: .regular)
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var parent: ShareButton
        init(_ parent: ShareButton) { self.parent = parent }

        @objc func show(_ sender: NSButton) {
            NSApp.activate(ignoringOtherApps: true)    // so AirDrop / Mail windows come to the front
            let picker = NSSharingServicePicker(items: [parent.text()])
            picker.delegate = self
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker,
                                  sharingServicesForItems items: [Any],
                                  proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
            parent.extras() + proposed
        }

        func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            service?.subject = parent.subject()       // e.g. the email subject line
        }
    }
}

extension NSSharingService {
    static func custom(title: String, symbol: String, action: @escaping () -> Void) -> NSSharingService {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) ?? NSImage()
        return NSSharingService(title: title, image: image, alternateImage: nil, handler: action)
    }
}

// MARK: - Export

enum NoteExport {
    static func copy(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    /// macOS only offers AirDrop for files, so this sends the note as a temporary .md file.
    static func airDropService(_ note: Note) -> [NSSharingService] {
        guard let airDrop = NSSharingService(named: .sendViaAirDrop) else { return [] }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName(for: note))
        let service = NSSharingService(title: "AirDrop", image: airDrop.image, alternateImage: nil) {
            try? note.text.write(to: url, atomically: true, encoding: .utf8)
            airDrop.perform(withItems: [url])
        }
        return [service]
    }

    static func saveAs(_ note: Note) {
        NSApp.activate(ignoringOtherApps: true)   // a menu-bar app must activate to show a save dialog
        let panel = NSSavePanel()
        panel.title = "Save Note"
        panel.nameFieldStringValue = fileName(for: note)
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText, .plainText]
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if panel.runModal() == .OK, let url = panel.url {
            write(note, to: url)
        }
    }

    static func exportAll(_ notes: [Note]) {
        let notes = notes.filter { !$0.isBlank }
        guard !notes.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Export All Notes"
        panel.message = "Choose a folder — each note is saved as its own Markdown file."
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for note in notes {
            write(note, to: uniqueURL(in: dir, base: fileName(for: note)))
        }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    private static func write(_ note: Note, to url: URL) {
        do {
            try note.text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// "2026-11-19 1045 Standup notes.md"
    static func fileName(for note: Note) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        let unsafe = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let title = note.title.components(separatedBy: unsafe).joined(separator: "-").prefix(60)
        return "\(f.string(from: note.created)) \(title).md"
    }

    private static func uniqueURL(in dir: URL, base: String) -> URL {
        var url = dir.appendingPathComponent(base)
        let stem = (base as NSString).deletingPathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) (\(n)).md")
            n += 1
        }
        return url
    }
}
