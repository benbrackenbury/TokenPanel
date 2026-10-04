import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct ProviderLogo: View {
    var provider: ProviderID
    var size: CGFloat = 22

    var body: some View {
        logoImage
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(provider.displayName)
    }

    private var logoImage: Image {
        #if WIDGET_PREVIEW_RENDER
        if let path = ProcessInfo.processInfo.environment["TOKENPANEL_LOGO_\(provider.rawValue.uppercased())"],
           let nsImage = NSImage(contentsOfFile: path) {
            return Image(nsImage: nsImage)
        }
        #endif
        return Image(provider.logoName)
    }
}

#if canImport(AppKit)
extension ProviderID {
    /// MenuBarExtra uses the NSImage's native size, not SwiftUI's frame.
    func statusItemImage(points: CGFloat = 18) -> NSImage {
        glyphImage(points: points, template: true)
    }

    func glyphImage(points: CGFloat, template: Bool) -> NSImage {
        let dest = NSSize(width: points, height: points)
        guard let cg = cgLogo() else { return NSImage(size: dest) }
        let image = NSImage(cgImage: cg, size: dest)
        image.isTemplate = template
        return image
    }

    fileprivate func cgLogo() -> CGImage? {
        let base = NSImage(resource: ImageResource(name: logoName, bundle: .main))
        guard base.size.width > 0, base.size.height > 0 else { return nil }
        base.isTemplate = false
        var proposed = NSRect(origin: .zero, size: base.size)
        return base.cgImage(forProposedRect: &proposed, context: nil, hints: nil)
    }
}

enum MenuBarCluster {
    static func image(providers: [ProviderID], titles: [String]) -> NSImage {
        let icon: CGFloat = 16
        let gap: CGFloat = 8
        let inner: CGFloat = 3
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        var width: CGFloat = 0
        for (index, title) in titles.enumerated() {
            if index > 0 { width += gap }
            width += icon
            if !title.isEmpty {
                width += inner + (title as NSString).size(withAttributes: attrs).width
            }
        }

        let size = NSSize(width: max(width, icon), height: icon)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((size.width * scale).rounded())),
            pixelsHigh: max(1, Int((size.height * scale).rounded())),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: size)
        }
        rep.size = size

        // Bitmap, not NSCustomImageRep. MenuBarExtra often skips nested drawing handlers.
        let glyphs = providers.map { $0.glyphImage(points: icon, template: false) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        var x: CGFloat = 0
        for (index, glyph) in glyphs.enumerated() {
            if index > 0 { x += gap }
            glyph.draw(
                in: NSRect(x: x, y: 0, width: icon, height: icon),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            x += icon
            let title = titles[index]
            if !title.isEmpty {
                x += inner
                let textSize = (title as NSString).size(withAttributes: attrs)
                let y = (icon - textSize.height) / 2
                (title as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                x += textSize.width
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }
}
#endif
