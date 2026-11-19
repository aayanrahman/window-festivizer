import AppKit
import UniformTypeIdentifiers

/// Developer option: `WindowFestivizer --render out.png`.
///
/// Builds the real light layers (StripLayers and TailLayers, exactly as the app uses them), draws
/// them onto pretend windows, and saves the picture as a PNG. Your real windows aren't touched, so
/// it's a quick way to check a change to the art. Tails are shown hanging at rest.
///
/// Rows, top to bottom: Wrapped Around through the three beats of the Festivizer pattern, Laid on
/// Top, each other theme in alternating styles on dark and light windows, then Slim and Chunky.
enum PreviewRenderer {
    private struct Row {
        let label: String
        let style: WrapStyle
        let theme: Theme
        var wrap: WrapSize = .regular
        let beat: Int
        let darkWindow: Bool
    }

    static func render(to path: String) {
        let scale: CGFloat = 2
        let windowSize = CGSize(width: 640, height: 84)
        let rows = [
            Row(label: "Wrapped Around, beat 1 (green off)", style: .wrapped, theme: .festivizer, beat: 0, darkWindow: true),
            Row(label: "Wrapped Around, beat 2 (blue off)", style: .wrapped, theme: .festivizer, beat: 1, darkWindow: true),
            Row(label: "Wrapped Around, beat 3 (yellow off)", style: .wrapped, theme: .festivizer, beat: 2, darkWindow: true),
            Row(label: "Laid on Top", style: .laidOnTop, theme: .festivizer, beat: 0, darkWindow: true),
            Row(label: "Classic, Wrapped Around", style: .wrapped, theme: .classic, beat: 1, darkWindow: false),
            Row(label: "RED, Laid on Top", style: .laidOnTop, theme: .red, beat: 2, darkWindow: true),
            Row(label: "BLU, Wrapped Around", style: .wrapped, theme: .blu, beat: 0, darkWindow: false),
            Row(label: "Warm White, Wrapped Around", style: .wrapped, theme: .warmWhite, beat: 1, darkWindow: true),
            Row(label: "Pastel, Laid on Top", style: .laidOnTop, theme: .pastel, beat: 2, darkWindow: false),
            Row(label: "Slim", style: .wrapped, theme: .festivizer, wrap: .slim, beat: 0, darkWindow: true),
            Row(label: "Chunky", style: .wrapped, theme: .classic, wrap: .chunky, beat: 2, darkWindow: false),
        ]
        let rowHeight: CGFloat = 190
        let margin: CGFloat = 48
        let canvas = CGSize(width: windowSize.width + 2 * margin + 110, height: rowHeight * CGFloat(rows.count))

        guard let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: BulbArt.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        // This picture uses y up, the same as Core Animation, so layers render the right way round.
        ctx.setFillColor(RGB(0x3A8FD9).cg())
        ctx.fill(CGRect(origin: .zero, size: canvas))

        for (r, row) in rows.enumerated() {
            let rowTop = canvas.height - CGFloat(r) * rowHeight
            drawLabel(row.label, at: CGPoint(x: margin, y: rowTop - 28), ctx)
            // The pretend window's top-left corner.
            let corner = CGPoint(x: margin, y: rowTop - 72)
            drawMockWindow(ctx, corner: corner, size: windowSize, dark: row.darkWindow)

            let g = WrapGeometry(windowSize: windowSize, style: row.style, scale: row.wrap.scale, tail: true)
            let strip = StripLayers(geometry: g, theme: row.theme, scale: scale)
            strip.light(beat: row.beat, pattern: .festivizer, animated: false)
            draw(strip.root, at: g.stripRect, corner: corner, ctx)

            if let t = g.tail {
                let chain = SwingingTail(anchor: t.anchor, lead: t.lead, segments: t.segments, segmentLength: t.segmentLength)
                let tail = TailLayers(tail: t, twist: g.twist, theme: row.theme, scale: scale)
                tail.layout(points: chain.points, in: t.rect)
                tail.light(beat: row.beat, pattern: .festivizer, animated: false)
                draw(tail.root, at: t.rect, corner: corner, ctx)
            }
        }

        guard let image = ctx.makeImage(),
              let out = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("couldn't write \(path)\n".utf8))
            return
        }
        CGImageDestinationAddImage(out, image, nil)
        CGImageDestinationFinalize(out)
        print("Saved \(path)")
    }

    /// Render a layer tree covering `rect` (window-local, y down) of the pretend window whose
    /// top-left corner is at `corner` in the picture.
    private static func draw(_ layer: CALayer, at rect: CGRect, corner: CGPoint, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: corner.x + rect.minX, y: corner.y - rect.maxY)
        layer.render(in: ctx)
        ctx.restoreGState()
    }

    /// A rough macOS window: rounded corners, a title bar with the three buttons, a few lines of "text".
    private static func drawMockWindow(_ ctx: CGContext, corner: CGPoint, size: CGSize, dark: Bool) {
        let frame = CGRect(x: corner.x, y: corner.y - size.height, width: size.width, height: size.height)
        let radius = WrapGeometry.cornerRadius
        let body = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: RGB(0).cg(0.35))
        ctx.addPath(body)
        ctx.setFillColor((dark ? RGB(0x1E1E20) : RGB(0xF6F6F8)).cg())
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        ctx.setFillColor((dark ? RGB(0x2C2C30) : RGB(0xE6E6EA)).cg())
        ctx.fill(titleBar)
        ctx.setFillColor((dark ? RGB(0xFFFFFF) : RGB(0x000000)).cg(0.12))
        for (i, width) in [frame.width * 0.62, frame.width * 0.48].enumerated() {
            ctx.fill(CGRect(x: frame.minX + 20, y: titleBar.minY - 20 - CGFloat(i) * 16, width: width, height: 7))
        }
        ctx.restoreGState()

        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            ctx.setFillColor(RGB(hex).cg())
            ctx.fillEllipse(in: CGRect(x: frame.minX + 14 + CGFloat(i) * 20, y: titleBar.midY - 6, width: 12, height: 12))
        }
    }

    private static func drawLabel(_ text: String, at point: CGPoint, _ ctx: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }
}
