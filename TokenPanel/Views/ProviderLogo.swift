import SwiftUI
#if canImport(AppKit)
import AppKit
import CoreText
import ImageIO
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
        guard let base = NSImage(named: logoName),
              let tiff = base.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiff as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
        let pixelsWide = max(1, Int((size.width * scale).rounded()))
        let pixelsHigh = max(1, Int((size.height * scale).rounded()))
        // Core Graphics only. NSGraphicsContext during MenuBarExtra setup traps (0.3.3 crash).
        guard let ctx = CGContext(
            data: nil,
            width: pixelsWide,
            height: pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: size)
        }
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high

        var x: CGFloat = 0
        for (index, provider) in providers.enumerated() {
            if index > 0 { x += gap }
            if let cg = provider.cgLogo() {
                ctx.draw(cg, in: CGRect(x: x, y: 0, width: icon, height: icon))
            }
            x += icon
            let title = index < titles.count ? titles[index] : ""
            if !title.isEmpty {
                x += inner
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: title, attributes: attrs))
                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                var leading: CGFloat = 0
                let textWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
                ctx.textPosition = CGPoint(x: x, y: (icon - (ascent + descent)) / 2 + descent)
                CTLineDraw(line, ctx)
                x += textWidth
            }
        }

        guard let cgImage = ctx.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: cgImage, size: size)
        image.isTemplate = true
        return image
    }
}
#endif
