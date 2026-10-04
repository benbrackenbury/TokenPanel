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
        guard let base = NSImage(named: logoName)?.copy() as? NSImage else {
            return NSImage(size: dest)
        }
        base.isTemplate = false
        let image = NSImage(size: dest, flipped: false) { rect in
            base.draw(in: rect)
            return true
        }
        image.isTemplate = template
        return image
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

        // Load glyphs before the drawing block. NSImage(named:) inside it
        // can return nil (or the image being created).
        let glyphs = providers.map { $0.glyphImage(points: icon, template: false) }
        let size = NSSize(width: max(width, icon), height: icon)
        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, glyph) in glyphs.enumerated() {
                if index > 0 { x += gap }
                glyph.draw(in: NSRect(x: x, y: 0, width: icon, height: icon))
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
            return true
        }
        image.isTemplate = true
        return image
    }
}
#endif
