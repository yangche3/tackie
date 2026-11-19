import SwiftUI

/// Cards shown in the top-right corner when reminders come due. They stay until you act on them.
struct ReminderAlertView: View {
    @ObservedObject var store: Store
    let onOpenNote: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(store.alertingItems) { item in
                ReminderCard(store: store, item: item, onOpenNote: onOpenNote)
            }
        }
        .padding(10)                      // room for the card shadows
        .fixedSize()
        .modifier(ThemeScheme(theme: store.theme))
    }
}

private struct ReminderCard: View {
    @ObservedObject var store: Store
    let item: TodoItem
    let onOpenNote: () -> Void
    @ViewState private var ring = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
                .rotationEffect(.degrees(ring ? 12 : -12))
                .animation(.easeInOut(duration: 0.12).repeatCount(9, autoreverses: true), value: ring)
                .onAppear { ring = true }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(store.noteFont(size: 14, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(perform: onOpenNote)
                if let due = item.due {
                    Text("Due \(TodoRow.format(due))")
                        .font(store.noteFont(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    QuickChip("✓ Done") { withAnimation { store.completeFromAlert(item.id) } }
                    QuickChip("10 min") { withAnimation { store.snooze(item.id, until: Date().addingTimeInterval(600)) } }
                    QuickChip("1 hour") { withAnimation { store.snooze(item.id, until: Date().addingTimeInterval(3600)) } }
                    QuickChip("Tomorrow") {
                        withAnimation { store.snooze(item.id, until: TodoRow.at(hour: 9, daysAhead: 1)) }
                    }
                }
                .padding(.top, 2)
            }
            .padding(.trailing, 12)                   // keep the title clear of the × button
        }
        .padding(12)
        .frame(width: 330, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Button { withAnimation { store.dismissAlert(item.id) } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(4)
            .help("Dismiss (keeps the to-do)")
        }
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(store.theme == .glass ? Color(nsColor: .windowBackgroundColor) : store.theme.color)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.5), lineWidth: 1.5)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
}
