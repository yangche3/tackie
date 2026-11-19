import SwiftUI
import AppKit

// Renders AppIcon at every size macOS wants into the .iconset folder given as the argument.
@MainActor func write(size: Int, to url: URL) {
    let renderer = ImageRenderer(content: AppIcon())
    renderer.scale = CGFloat(size) / 1024
    guard let cg = renderer.cgImage else { return }
    try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: url)
}

MainActor.assumeIsolated {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for base in [16, 32, 128, 256, 512] {
        write(size: base, to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
        write(size: base * 2, to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
    }
}
