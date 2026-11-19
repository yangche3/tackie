// Draws Tackie's app icon. Regenerate Resources/AppIcon.icns with Tools/AppIcon/make-icon.sh
import SwiftUI

// Building blocks --------------------------------------------------------------

let noteYellow = Color(red: 1.00, green: 0.88, blue: 0.40)
let noteShade  = Color(red: 0.93, green: 0.76, blue: 0.27)
let ink        = Color(red: 0.33, green: 0.25, blue: 0.20)
let pinRed     = Color(red: 0.95, green: 0.33, blue: 0.33)
let pinDark    = Color(red: 0.78, green: 0.20, blue: 0.24)

/// macOS app-icon tile: rounded square on a 1024 canvas with a soft shadow.
struct Tile<Content: View>: View {
    let bg: [Color]
    @ViewBuilder let content: Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: bg, startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)
            content
        }
        .frame(width: 1024, height: 1024)
    }
}

/// A square sticky note with a folded bottom-right corner.
struct StickyNote: View {
    var size: CGFloat = 520
    var body: some View {
        let fold = size * 0.17
        ZStack(alignment: .bottomTrailing) {
            NoteShape(fold: fold)
                .fill(LinearGradient(colors: [noteYellow, Color(red: 1, green: 0.84, blue: 0.33)],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.18), radius: 10, x: 4, y: 10)
            FoldShape(fold: fold)
                .fill(noteShade)
                .frame(width: fold, height: fold)
        }
        .frame(width: size, height: size)
    }
}

struct NoteShape: Shape {
    let fold: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.origin)
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
        p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct FoldShape: Shape {   // the turned-up corner triangle
    let fold: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Round thumbtack head seen from the front, with a glossy highlight.
struct TackHead: View {
    var size: CGFloat = 150
    var face = false
    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [pinRed, pinDark], center: .init(x: 0.38, y: 0.32),
                                     startRadius: size * 0.05, endRadius: size * 0.62))
                .shadow(color: .black.opacity(0.28), radius: size * 0.06, x: size * 0.03, y: size * 0.07)
            Ellipse()
                .fill(.white.opacity(0.55))
                .frame(width: size * 0.30, height: size * 0.18)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.20, y: -size * 0.24)
            if face {
                HStack(spacing: size * 0.20) {
                    Capsule().fill(Color(red: 0.25, green: 0.08, blue: 0.10)).frame(width: size * 0.09, height: size * 0.15)
                    Capsule().fill(Color(red: 0.25, green: 0.08, blue: 0.10)).frame(width: size * 0.09, height: size * 0.15)
                }
                .offset(y: size * 0.02)
                HStack(spacing: size * 0.42) {
                    Circle().fill(Color.pink.opacity(0.55)).frame(width: size * 0.13)
                    Circle().fill(Color.pink.opacity(0.55)).frame(width: size * 0.13)
                }
                .offset(y: size * 0.15)
                Smile().stroke(Color(red: 0.25, green: 0.08, blue: 0.10),
                               style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .frame(width: size * 0.16, height: size * 0.07)
                    .offset(y: size * 0.17)
            }
        }
        .frame(width: size, height: size)
    }
}

struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY * 1.6))
        return p
    }
}

struct CheckRow: View {
    var done: Bool
    var width: CGFloat
    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(ink.opacity(0.55), lineWidth: 9).frame(width: 46, height: 46)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 30, weight: .black)).foregroundStyle(ink)
                }
            }
            Capsule().fill(ink.opacity(done ? 0.25 : 0.45)).frame(width: width, height: 16)
        }
    }
}

// Tackie's app icon: a happy sticky note pinned with a red tack, on peach.
struct AppIcon: View {
    var body: some View {
        Tile(bg: [Color(red: 1.0, green: 0.93, blue: 0.86), Color(red: 1.0, green: 0.83, blue: 0.74)]) {
            ZStack {
                StickyNote(size: 560)
                // face on the note
                VStack(spacing: 30) {
                    HStack(spacing: 120) {
                        Capsule().fill(ink).frame(width: 34, height: 58)
                        Capsule().fill(ink).frame(width: 34, height: 58)
                    }
                    Smile().stroke(ink, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                        .frame(width: 90, height: 36)
                }
                .offset(y: 20)
                HStack(spacing: 190) {
                    Circle().fill(Color.pink.opacity(0.45)).frame(width: 60)
                    Circle().fill(Color.pink.opacity(0.45)).frame(width: 60)
                }
                .offset(y: 80)
                TackHead(size: 140).offset(y: -265)
            }
            .rotationEffect(.degrees(-4))
            .offset(y: 25)
        }
    }
}
