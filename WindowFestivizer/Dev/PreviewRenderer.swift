import AppKit
import UniformTypeIdentifiers

/// Developer option: `WindowFestivizer --render out.png`.
///
/// Builds the real light layers (StripLayers and TailLayers, exactly as the app uses them), draws
/// them onto pretend windows, and saves the picture as a PNG. Your real windows aren't touched, so
/// it's a quick way to check a change to the art.
///
/// Rows, top to bottom: the three beats of the Festivizer pattern, the other themes, then the
/// Regular and Chunky sizes.
enum PreviewRenderer {
    private struct Row {
        let label: String
        let theme: Theme
        let wrap: WrapSize
        let beat: Int
        let darkWindow: Bool
    }

    static func render(to path: String) {
        let scale: CGFloat = 2
        let windowSize = CGSize(width: 640, height: 96)
        let rows = [
            Row(label: "Festivizer, beat 1 (green off)", theme: .festivizer, wrap: .slim, beat: 0, darkWindow: true),
            Row(label: "Festivizer, beat 2 (blue off)", theme: .festivizer, wrap: .slim, beat: 1, darkWindow: true),
            Row(label: "Festivizer, beat 3 (yellow off)", theme: .festivizer, wrap: .slim, beat: 2, darkWindow: true),
            Row(label: "RED", theme: .red, wrap: .slim, beat: 0, darkWindow: false),
            Row(label: "BLU", theme: .blu, wrap: .slim, beat: 1, darkWindow: true),
            Row(label: "Classic", theme: .classic, wrap: .slim, beat: 2, darkWindow: false),
            Row(label: "Regular size", theme: .festivizer, wrap: .regular, beat: 0, darkWindow: true),
            Row(label: "Chunky size", theme: .festivizer, wrap: .chunky, beat: 0, darkWindow: false),
        ]
        let rowHeight: CGFloat = 170
        let margin: CGFloat = 40
        let canvas = CGSize(width: windowSize.width + 2 * margin + 120, height: rowHeight * CGFloat(rows.count))

        guard let ctx = CGContext(data: nil, width: Int(canvas.width * scale), height: Int(canvas.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: BulbArt.sRGB,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        // This picture uses y up, the same as Core Animation, so layers render the right way round.
        ctx.setFillColor(RGB(0x2C5E63).cg())
        ctx.fill(CGRect(origin: .zero, size: canvas))

        for (r, row) in rows.enumerated() {
            let rowTop = canvas.height - CGFloat(r) * rowHeight
            drawLabel(row.label, at: CGPoint(x: margin, y: rowTop - 26), ctx)
            // The pretend window's top-left corner.
            let corner = CGPoint(x: margin, y: rowTop - 62)
            drawMockWindow(ctx, corner: corner, size: windowSize, dark: row.darkWindow)

            let g = WrapGeometry(windowSize: windowSize, radius: row.wrap.radius)
            let strip = StripLayers(geometry: g, theme: row.theme, scale: scale)
            strip.bank.light(beat: row.beat, pattern: .festivizer, animated: false)
            draw(strip.root, windowRect: g.stripRect, corner: corner, ctx)

            // The tail, caught mid-swing.
            let tail = TailLayers(geometry: g, theme: row.theme, scale: scale)
            let points = (0...g.tailSegments).map { n -> CGPoint in
                let t = CGFloat(n)
                return CGPoint(x: g.tailAnchor.x + 2.2 * t * t * 0.35, y: g.tailAnchor.y + t * g.tailSegmentLength * 0.97)
            }
            tail.layout(points: points, in: g.tailRect)
            tail.bank.light(beat: row.beat, pattern: .festivizer, animated: false)
            draw(tail.root, windowRect: g.tailRect, corner: corner, ctx)
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

    /// Render a layer tree that covers `windowRect` (window-local, y down) of a pretend window
    /// whose top-left corner is at `corner` in the picture.
    private static func draw(_ layer: CALayer, windowRect: CGRect, corner: CGPoint, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: corner.x + windowRect.minX, y: corner.y - windowRect.maxY)
        layer.render(in: ctx)
        ctx.restoreGState()
    }

    /// A rough macOS window: rounded corners, a title bar with the three buttons, a few lines of "text".
    private static func drawMockWindow(_ ctx: CGContext, corner: CGPoint, size: CGSize, dark: Bool) {
        let frame = CGRect(x: corner.x, y: corner.y - size.height, width: size.width, height: size.height)
        let body = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)

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
        for (i, width) in [frame.width * 0.62, frame.width * 0.48, frame.width * 0.55].enumerated() {
            ctx.fill(CGRect(x: frame.minX + 20, y: titleBar.minY - 22 - CGFloat(i) * 16, width: width, height: 7))
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
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }
}
