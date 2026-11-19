import CoreGraphics
import Foundation

/// Draws the cable and the bulbs with Core Graphics.
///
/// There are no picture files in this app. Just as Window Scarves knits its scarves in code, the
/// lights are drawn from a few curves and gradients. The style follows TF2's painted look: slim
/// pointed bulbs that are hottest near the socket and richest in colour at the tip, a thin dark
/// outline, flat dark-green sockets, and no blurry halos.
///
/// Crispness: every bulb is drawn as vector shapes at its final position and angle, straight onto
/// a bitmap whose edges sit on whole pixels. Nothing is drawn once and then rotated or scaled
/// afterwards, which is what makes sprites look soft.
///
/// Drawing happens with y pointing down (see `image`), to match WrapGeometry.
enum BulbArt {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A bulb's widest point, as a fraction of its length. TF2's bulbs are slim.
    static let widthRatio: CGFloat = 0.36

    /// How strongly a lit bulb tints the area right around it. Kept small so edges stay sharp;
    /// 0 turns it off.
    static let glowStrength: CGFloat = 0.22

    /// What off bulbs fade towards: a dark slate, so they still read as coloured glass.
    private static let offGlass = RGB(0x2B3036)

    // MARK: Pictures

    /// The cable plus every bulb switched off, as one picture the size of `g.stripRect`.
    static func base(_ g: WrapGeometry, theme: Theme, scale: CGFloat) -> CGImage? {
        let rect = g.stripRect
        return image(size: rect.size, scale: scale) { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)   // draw in window coordinates
            // One small, tight shadow for everything, so it sits on the window rather than floats.
            shadow(ctx, down: 0.6, blur: 1.2, alpha: 0.35, scale: scale)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            drawCable(ctx, g, colour: theme.wire)
            for bulb in g.bulbs {
                drawBulb(ctx, bulb, colour: theme.colours[bulb.group], socket: theme.wire, lit: false)
            }
            ctx.endTransparencyLayer()
        }
    }

    /// One bulb switched on, drawn into its own small picture that sits exactly over the same bulb
    /// in `base`. `frame` is where the picture goes, in strip coordinates (y down), and its edges
    /// are on whole pixels so Core Animation never has to resample it.
    static func litBulb(_ bulb: WrapGeometry.Bulb, in strip: CGRect, theme: Theme,
                        scale: CGFloat) -> (image: CGImage?, frame: CGRect) {
        let box = bounds(of: bulb, pad: bulb.length * 0.4).offsetBy(dx: -strip.minX, dy: -strip.minY)
        let frame = CGRect(x: floor(box.minX * scale) / scale, y: floor(box.minY * scale) / scale,
                           width: (ceil(box.maxX * scale) - floor(box.minX * scale)) / scale,
                           height: (ceil(box.maxY * scale) - floor(box.minY * scale)) / scale)
        let picture = image(size: frame.size, scale: scale) { ctx in
            ctx.translateBy(x: -(frame.minX + strip.minX), y: -(frame.minY + strip.minY))
            let colour = theme.colours[bulb.group]
            drawGlow(ctx, bulb, colour: colour)
            drawBulb(ctx, bulb, colour: colour, socket: theme.wire, lit: true)
        }
        return (picture, frame)
    }

    /// The rectangle a bulb covers, plus `pad` all round (window-local, y down).
    static func bounds(of bulb: WrapGeometry.Bulb, pad: CGFloat) -> CGRect {
        let tip = CGPoint(x: bulb.attach.x + cos(bulb.angle) * bulb.length,
                          y: bulb.attach.y + sin(bulb.angle) * bulb.length)
        let half = bulb.length * widthRatio / 2 + pad
        return CGRect(x: min(bulb.attach.x, tip.x) - half, y: min(bulb.attach.y, tip.y) - half,
                      width: abs(tip.x - bulb.attach.x) + 2 * half, height: abs(tip.y - bulb.attach.y) + 2 * half)
    }

    // MARK: Bulbs

    /// Draws one bulb with its socket at `bulb.attach`, pointing along `bulb.angle`.
    static func drawBulb(_ ctx: CGContext, _ bulb: WrapGeometry.Bulb, colour c: RGB, socket wire: RGB, lit: Bool) {
        let L = bulb.length
        let W = L * widthRatio
        let socketLength = L * 0.3
        let socketWidth = W * 0.8
        let glassTop = socketLength * 0.82   // tucked up inside the socket
        let gl = L - glassTop                // length of the glass

        ctx.saveGState()
        ctx.translateBy(x: bulb.attach.x, y: bulb.attach.y)
        // From here on the bulb points straight down the +y axis, socket at the origin.
        ctx.rotate(by: bulb.angle - .pi / 2)

        // The glass: a slim teardrop, widest a third of the way down, tapering to a soft point.
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: -socketWidth * 0.42, y: glassTop))
        glass.addCurve(to: CGPoint(x: -W / 2, y: glassTop + gl * 0.32),
                       control1: CGPoint(x: -socketWidth * 0.5, y: glassTop + gl * 0.1),
                       control2: CGPoint(x: -W / 2, y: glassTop + gl * 0.18))
        glass.addCurve(to: CGPoint(x: 0, y: L),
                       control1: CGPoint(x: -W / 2, y: glassTop + gl * 0.62),
                       control2: CGPoint(x: -W * 0.12, y: L - gl * 0.02))
        glass.addCurve(to: CGPoint(x: W / 2, y: glassTop + gl * 0.32),
                       control1: CGPoint(x: W * 0.12, y: L - gl * 0.02),
                       control2: CGPoint(x: W / 2, y: glassTop + gl * 0.62))
        glass.addCurve(to: CGPoint(x: socketWidth * 0.42, y: glassTop),
                       control1: CGPoint(x: W / 2, y: glassTop + gl * 0.18),
                       control2: CGPoint(x: socketWidth * 0.5, y: glassTop + gl * 0.1))
        glass.closeSubpath()

        // Fill. Lit: hottest by the filament near the socket, richest colour at the tip.
        // Off: the same glass, darkened towards slate.
        let stops: [RGB] = lit
            ? [c.lighter(0.7), c.lighter(0.25), c, c.darker(0.12)]
            : [c.mix(offGlass, 0.5), c.mix(offGlass, 0.6), c.mix(offGlass, 0.68), c.mix(offGlass, 0.74)]
        let fill = CGGradient(colorsSpace: sRGB, colors: stops.map { $0.cg() } as CFArray,
                              locations: [0, 0.3, 0.75, 1])!
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: glassTop), end: CGPoint(x: 0, y: L), options: [])
        if lit {
            // A pale core down the middle, where the light is strongest.
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.45))
            ctx.fillEllipse(in: CGRect(x: -W * 0.12, y: glassTop + gl * 0.04, width: W * 0.24, height: gl * 0.42))
        }
        // A short glint down one side.
        ctx.setFillColor(RGB(0xFFFFFF).cg(lit ? 0.75 : 0.22))
        ctx.fillEllipse(in: CGRect(x: -W * 0.31, y: glassTop + gl * 0.16, width: W * 0.13, height: gl * 0.3))
        ctx.restoreGState()

        // The painted outline.
        ctx.addPath(glass)
        ctx.setStrokeColor((lit ? c.darker(0.55) : c.mix(offGlass, 0.85).darker(0.3)).cg())
        ctx.setLineWidth(max(0.6, L * 0.05))
        ctx.strokePath()

        // The socket: a small dark cylinder in the wire's colour, with a band and a sheen.
        let socketRect = CGRect(x: -socketWidth / 2, y: 0, width: socketWidth, height: socketLength)
        let socket = CGPath(roundedRect: socketRect, cornerWidth: socketWidth * 0.3,
                            cornerHeight: socketWidth * 0.3, transform: nil)
        ctx.addPath(socket)
        ctx.setFillColor(wire.lighter(0.06).cg())
        ctx.fillPath()
        ctx.setFillColor(wire.darker(0.35).cg())
        ctx.fill(CGRect(x: socketRect.minX, y: socketLength * 0.62, width: socketWidth, height: max(0.5, L * 0.04)))
        ctx.setFillColor(wire.lighter(0.35).cg(0.6))
        ctx.fill(CGRect(x: socketRect.minX + socketWidth * 0.18, y: socketLength * 0.12,
                        width: max(0.5, socketWidth * 0.14), height: socketLength * 0.4))
        ctx.addPath(socket)
        ctx.setStrokeColor(wire.darker(0.45).cg())
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        ctx.restoreGState()
    }

    /// A faint, tight wash of colour around a lit bulb's glass.
    private static func drawGlow(_ ctx: CGContext, _ bulb: WrapGeometry.Bulb, colour: RGB) {
        guard glowStrength > 0 else { return }
        let reach = bulb.length * 0.55
        let centre = CGPoint(x: bulb.attach.x + cos(bulb.angle) * bulb.length * 0.6,
                             y: bulb.attach.y + sin(bulb.angle) * bulb.length * 0.6)
        let wash = CGGradient(colorsSpace: sRGB, colors: [colour.cg(glowStrength), colour.cg(0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(wash, startCenter: centre, startRadius: 0, endCenter: centre,
                               endRadius: reach, options: [])
    }

    // MARK: Cable

    /// The cable: two strands twisted round each other, like real string-light wire.
    ///
    /// Each strand weaves either side of the centre line. Where a strand is behind the other it's
    /// drawn first and darker; where it's in front it's drawn on top with a thin sheen. At both
    /// ends the cable fades, as if it carried on round the back of the window.
    static func drawCable(_ ctx: CGContext, _ g: WrapGeometry, colour: RGB) {
        guard let first = g.cable.first, let last = g.cable.last else { return }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Where each strand is at each cable point, and whether it's the front one there.
        func strand(_ j: Int) -> [(p: CGPoint, depth: CGFloat)] {
            g.cable.map { point in
                // A slow wobble in the twist, so it looks wound by hand rather than by machine.
                let phase = 2 * .pi * point.s / g.twistPeriod + CGFloat(j) * .pi + 0.35 * sin(point.s * 0.045)
                let offset = g.twistAmplitude * sin(phase)
                return (CGPoint(x: point.p.x + point.outward.dx * offset, y: point.p.y + point.outward.dy * offset),
                        cos(phase))
            }
        }
        let strands = [strand(0), strand(1)]

        /// Strokes the stretches of a strand whose depth passes `keep`, nudged `outward` points away
        /// from the window.
        func strokeRuns(_ points: [(p: CGPoint, depth: CGFloat)], where keep: (CGFloat) -> Bool,
                        outward: CGFloat = 0) {
            var run: [CGPoint] = []
            func flush() {
                if run.count > 1 { ctx.addLines(between: run) }
                run.removeAll(keepingCapacity: true)
            }
            for (i, point) in points.enumerated() {
                if keep(point.depth) {
                    let n = g.cable[i].outward
                    run.append(CGPoint(x: point.p.x + n.dx * outward, y: point.p.y + n.dy * outward))
                } else {
                    flush()
                }
            }
            flush()
            ctx.strokePath()
        }

        // The halves of each strand that pass behind the other.
        ctx.setStrokeColor(colour.darker(0.4).cg())
        ctx.setLineWidth(g.strandWidth)
        for s in strands { strokeRuns(s, where: { $0 < 0 }) }
        // The halves in front.
        ctx.setStrokeColor(colour.cg())
        for s in strands { strokeRuns(s, where: { $0 >= 0 }) }
        // A thin sheen along the outer side of the front halves, where the light catches them.
        ctx.setStrokeColor(colour.lighter(0.4).cg(0.55))
        ctx.setLineWidth(g.strandWidth * 0.35)
        for s in strands { strokeRuns(s, where: { $0 > 0.35 }, outward: g.strandWidth * 0.2) }

        // Fade both ends. The ends run straight down the window's sides, so a gradient between the
        // end point and the point `fadeLength` in from it does the job.
        let inner = (start: g.cable.first { $0.s >= g.fadeLength }?.p ?? first.p,
                     end: g.cable.last { $0.s <= last.s - g.fadeLength }?.p ?? last.p)
        let fade = CGGradient(colorsSpace: sRGB, colors: [RGB(0).cg(0), RGB(0).cg(1)] as CFArray, locations: [0, 1])!
        let pad = g.twistAmplitude + g.strandWidth + 2
        ctx.setBlendMode(.destinationIn)
        for (end, inside) in [(first.p, inner.start), (last.p, inner.end)] {
            ctx.saveGState()
            let box = CGRect(x: min(end.x, inside.x), y: min(end.y, inside.y),
                             width: abs(end.x - inside.x), height: abs(end.y - inside.y)).insetBy(dx: -pad, dy: -pad)
            ctx.clip(to: box)
            ctx.drawLinearGradient(fade, start: end, end: inside, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        ctx.setBlendMode(.normal)
        ctx.endTransparencyLayer()
    }

    // MARK: Helpers

    /// A transparent bitmap `size` points big, drawn with y pointing down.
    static func image(size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) -> CGImage? {
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
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
