#if WIDGET_PREVIEW_RENDER
import AppKit
import SwiftUI
import WidgetKit

@main
@MainActor
enum WidgetPreviewRender {
    static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/tokenpanel-widgets")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let provider = UsageTimelineProvider()
        let all = provider.sampleEntry(providers: Array(ProviderID.allCases))
        let grok = provider.sampleEntry(providers: [.grok])
        let pair = provider.sampleEntry(providers: [.cursor, .claude])

        let jobs: [(String, UsageEntry, WidgetFamily, CGSize)] = [
            ("small-all", all, .systemSmall, CGSize(width: 170, height: 170)),
            ("small-grok", grok, .systemSmall, CGSize(width: 170, height: 170)),
            ("medium-all", all, .systemMedium, CGSize(width: 364, height: 170)),
            ("medium-pair", pair, .systemMedium, CGSize(width: 364, height: 170)),
            ("large-grok", grok, .systemLarge, CGSize(width: 364, height: 382)),
            ("large-all", all, .systemLarge, CGSize(width: 364, height: 382)),
            ("xlarge-all", all, .systemExtraLarge, CGSize(width: 752, height: 382)),
        ]

        for job in jobs {
            render(job.1, family: job.2, size: job.3, to: out.appendingPathComponent("\(job.0).png"))
        }
        print("wrote \(jobs.count) previews to \(out.path)")
    }

    private static func render(_ entry: UsageEntry, family: WidgetFamily, size: CGSize, to url: URL) {
        let view = UsageWidgetView(entry: entry, familyOverride: family)
            .environment(\.colorScheme, .light)
            .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            fputs("failed \(url.lastPathComponent)\n", stderr)
            return
        }
        try? png.write(to: url)
    }
}
#endif
