import CoreGraphics
import Foundation

/// Draws the bulbs, their glow and the wire with Core Graphics.
///
/// There are no picture files in this app. Just as Window Scarves knits its scarves in code,
/// every bulb here is drawn from a few curves and gradients, once per colour and size, and the
/// result is shared by every window.
///
/// Drawing happens with y pointing down (see `image`), to match WrapGeometry.
enum BulbArt {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The size and layout of one bulb sprite. In its sprite a bulb points straight down, with
    /// its socket at the top.
    struct Metrics {
        let length: CGFloat
        let width: CGFloat
        let socket: CGFloat
        let pad: CGFloat

        init(length: CGFloat) {
            self.length = length
            width = length * 0.52
            socket = length * 0.3
            pad = max(2, (length * 0.2).rounded())
        }

        var canvas: CGSize {
            CGSize(width: (width + 2 * pad).rounded(.up), height: (length + 2 * pad).rounded(.up))
        }

        /// The top of the socket, where the bulb clips onto the wire.
        var attach: CGPoint { CGPoint(x: canvas.width / 2, y: pad) }

        /// From the attach point to the middle of the glass, where the glow is centred.
        var glassCentre: CGFloat { socket + (length - socket) * 0.45 }
    }

    enum Look { case unlit, lit }

    private static var cache: [String: CGImage] = [:]

    static func clearCache() { cache.removeAll() }

    // MARK: Bulbs

    static func bulb(_ colour: RGB, _ look: Look, length: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "bulb \(colour) \(look) \(length) \(scale)"
        if let cached = cache[key] { return cached }
        let metrics = Metrics(length: length)
        let made = image(size: metrics.canvas, scale: scale) { ctx in
            drawBulb(ctx, metrics, colour, look, scale: scale)
        }
        cache[key] = made
        return made
    }

    private static func drawBulb(_ ctx: CGContext, _ m: Metrics, _ c: RGB, _ look: Look, scale: CGFloat) {
        let cx = m.attach.x, top = m.attach.y
        let W = m.width
        let socketWidth = W * 0.62
        let glassTop = top + m.socket * 0.8   // tucked up inside the socket
        let tip = top + m.length
        let gl = tip - glassTop               // length of the glass

        // The glass: narrow at the socket, swelling out, then tapering to a rounded point.
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: cx - socketWidth * 0.45, y: glassTop))
        glass.addCurve(to: CGPoint(x: cx - W / 2, y: glassTop + gl * 0.38),
                       control1: CGPoint(x: cx - socketWidth * 0.5, y: glassTop + gl * 0.12),
                       control2: CGPoint(x: cx - W / 2, y: glassTop + gl * 0.2))
        glass.addCurve(to: CGPoint(x: cx, y: tip),
                       control1: CGPoint(x: cx - W / 2, y: glassTop + gl * 0.72),
                       control2: CGPoint(x: cx - W * 0.14, y: tip - gl * 0.02))
        glass.addCurve(to: CGPoint(x: cx + W / 2, y: glassTop + gl * 0.38),
                       control1: CGPoint(x: cx + W * 0.14, y: tip - gl * 0.02),
                       control2: CGPoint(x: cx + W / 2, y: glassTop + gl * 0.72))
        glass.addCurve(to: CGPoint(x: cx + socketWidth * 0.45, y: glassTop),
                       control1: CGPoint(x: cx + W / 2, y: glassTop + gl * 0.2),
                       control2: CGPoint(x: cx + socketWidth * 0.5, y: glassTop + gl * 0.12))
        glass.closeSubpath()

        let socketRect = CGRect(x: cx - socketWidth / 2, y: top, width: socketWidth, height: m.socket)
        let socket = CGPath(roundedRect: socketRect, cornerWidth: socketWidth * 0.22,
                            cornerHeight: socketWidth * 0.22, transform: nil)

        // Only unlit bulbs cast the drop shadow: a lit bulb is drawn exactly on top of an unlit one.
        if look == .unlit {
            ctx.saveGState()
            shadow(ctx, down: 0.8, blur: 1.6, alpha: 0.45, scale: scale)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            ctx.addPath(glass)
            ctx.setFillColor(c.darker(0.6).cg())
            ctx.fillPath()
            ctx.addPath(socket)
            ctx.setFillColor(RGB(0x15190F).cg())
            ctx.fillPath()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        // The glass: brighter down the middle, like light through coloured glass.
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        let edge = look == .lit ? c.darker(0.12) : c.darker(0.62)
        let middle = look == .lit ? c.lighter(0.45) : c.darker(0.42)
        let across = CGGradient(colorsSpace: sRGB, colors: [edge.cg(), middle.cg(), edge.cg()] as CFArray,
                                locations: [0, 0.45, 1])!
        ctx.drawLinearGradient(across, start: CGPoint(x: cx - W / 2, y: 0), end: CGPoint(x: cx + W / 2, y: 0), options: [])
        if look == .lit {
            // The hot glow of the filament inside.
            let core = CGGradient(colorsSpace: sRGB, colors: [RGB(0xFFFFFF).cg(0.9), c.lighter(0.6).cg(0)] as CFArray,
                                  locations: [0, 1])!
            let centre = CGPoint(x: cx, y: glassTop + gl * 0.42)
            ctx.drawRadialGradient(core, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: W * 0.42, options: [])
        }
        // A thin highlight down the left side.
        ctx.setFillColor(RGB(0xFFFFFF).cg(look == .lit ? 0.5 : 0.18))
        ctx.fillEllipse(in: CGRect(x: cx - W * 0.33, y: glassTop + gl * 0.16, width: W * 0.14, height: gl * 0.42))
        ctx.restoreGState()

        // A faint outline keeps pale bulbs readable on light title bars.
        ctx.addPath(glass)
        ctx.setStrokeColor(RGB(0x000000).cg(0.28))
        ctx.setLineWidth(0.6)
        ctx.strokePath()

        // The socket, with a couple of ridges.
        ctx.addPath(socket)
        ctx.setFillColor(RGB(0x171C14).cg())
        ctx.fillPath()
        ctx.setFillColor(RGB(0xFFFFFF).cg(0.16))
        for f: CGFloat in [0.35, 0.65] {
            ctx.fill(CGRect(x: cx - socketWidth * 0.38, y: top + m.socket * f,
                            width: socketWidth * 0.76, height: max(0.5, m.socket * 0.08)))
        }
    }

    // MARK: Glow

    /// A soft coloured halo, `radius` points across from its centre to where it fades out.
    static func glow(_ colour: RGB, radius: CGFloat, scale: CGFloat) -> CGImage? {
        let key = "glow \(colour) \(radius) \(scale)"
        if let cached = cache[key] { return cached }
        let made = image(size: CGSize(width: radius * 2, height: radius * 2), scale: scale) { ctx in
            let gradient = CGGradient(colorsSpace: sRGB,
                                      colors: [colour.lighter(0.2).cg(0.55), colour.cg(0.2), colour.cg(0)] as CFArray,
                                      locations: [0, 0.45, 1])!
            let centre = CGPoint(x: radius, y: radius)
            ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre,
                                   endRadius: radius, options: [])
        }
        cache[key] = made
        return made
    }

    // MARK: Wire

    /// The wire for one window's wrap, drawn into a single picture the size of `stripRect`.
    static func wire(_ g: WrapGeometry, colour: RGB, scale: CGFloat) -> CGImage? {
        let rect = g.stripRect
        return image(size: rect.size, scale: scale) { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)   // so we can draw in window coordinates
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            // One shadow for the whole wire, applied when the layer below is finished.
            shadow(ctx, down: 1, blur: 1.5, alpha: 0.4, scale: scale)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            let fade = CGGradient(colorsSpace: sRGB,
                                  colors: [RGB(0).cg(0), RGB(0).cg(1), RGB(0).cg(1), RGB(0).cg(0)] as CFArray,
                                  locations: [0, 0.15, 0.85, 1])!
            for arc in g.arcs {
                guard let first = arc.first, let last = arc.last else { continue }
                // Each arc gets its own layer, so its ends can be faded without touching its neighbours.
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)

                ctx.addLines(between: arc.map(\.p))
                ctx.setStrokeColor(colour.cg())
                ctx.setLineWidth(g.wireWidth)
                ctx.strokePath()

                // A thin shine along the top of the wire.
                let lift = g.wireWidth * 0.25
                ctx.addLines(between: arc.map { CGPoint(x: $0.p.x, y: $0.p.y - lift) })
                ctx.setStrokeColor(colour.lighter(0.4).cg(0.6))
                ctx.setLineWidth(g.wireWidth * 0.35)
                ctx.strokePath()

                // Fade both ends, where the wire rounds the pole and goes behind it. Along one arc,
                // x moves steadily with θ, so a left-to-right gradient does the job.
                ctx.saveGState()
                let pad = g.wireWidth * 2
                ctx.clip(to: CGRect(x: first.p.x - pad, y: rect.minY, width: last.p.x - first.p.x + 2 * pad, height: rect.height))
                ctx.setBlendMode(.destinationIn)
                ctx.drawLinearGradient(fade, start: CGPoint(x: first.p.x, y: 0), end: CGPoint(x: last.p.x, y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                ctx.restoreGState()

                ctx.endTransparencyLayer()
            }
            ctx.endTransparencyLayer()
        }
    }

    // MARK: Helpers

    /// A transparent bitmap `size` points big, drawn with y pointing down.
    static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded(.up)))
        let height = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()
    }

    /// A drop shadow `down` points below. Shadow offsets are measured in pixels with y up,
    /// whatever the drawing transform, hence the scale and the minus sign.
    private static func shadow(_ ctx: CGContext, down: CGFloat, blur: CGFloat, alpha: CGFloat, scale: CGFloat) {
        ctx.setShadow(offset: CGSize(width: 0, height: -down * scale), blur: blur * scale, color: RGB(0).cg(alpha))
    }
}
