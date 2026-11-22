import CoreGraphics
import Foundation

/// Draws the cable and the bulbs with Core Graphics.
///
/// There are no picture files in this app. Just as Window Scarves knits its scarves in code, the
/// lights are drawn from a few curves and gradients. The style follows TF2's painted look:
/// straight-sided capsule bulbs with a pointed tip and a pale facet down one side, hottest near the
/// socket, nearly black when off, with a thin dark outline, black sockets, and no blurry halos.
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

    /// What off bulbs fade towards: nearly black, as in TF2, with just a hint of their colour left.
    private static let offGlass = RGB(0x15181A)

    // MARK: Pictures

    /// One layer of a window's strip, every bulb switched off, as a picture the size of
    /// `g.stripRect`. `behind` picks the back of the coil (shown only above the window's top edge)
    /// or everything in front.
    static func strip(_ g: WrapGeometry, theme: Theme, behind: Bool, scale: CGFloat) -> CGImage? {
        let rect = g.stripRect
        return image(size: rect.size, scale: scale) { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)   // draw in window coordinates
            if behind { ctx.clip(to: aboveTheWindow) }
            // One small, tight shadow for everything, so it sits on the window rather than floats.
            shadow(ctx, down: 0.6, blur: 1.2, alpha: 0.35, scale: scale)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            if behind {
                drawCable(ctx, g.backRuns, twist: g.twist, colour: theme.wire.darker(0.3))
            } else {
                drawCable(ctx, g.frontRuns, twist: g.twist, colour: theme.wire, fades: g.fades)
            }
            for bulb in g.bulbs where bulb.behind == behind {
                drawBulb(ctx, bulb, colour: theme.colours[bulb.group], socket: theme.wire, lit: false)
            }
            ctx.endTransparencyLayer()
        }
    }

    /// One bulb in its own small picture, lit or not. `origin` is the top-left corner of the layer
    /// it goes in, in the same coordinates as the bulb. The returned frame is relative to that
    /// corner (y down), with edges on whole pixels so Core Animation never has to resample it.
    static func bulbPicture(_ bulb: WrapGeometry.Bulb, lit: Bool, theme: Theme, origin: CGPoint,
                            scale: CGFloat) -> (image: CGImage?, frame: CGRect) {
        var box = bounds(of: bulb, pad: lit ? bulb.length * 0.4 : 3)
        if bulb.behind { box.size.height = max(1, min(box.maxY, 1) - box.minY) }
        let frame = snap(box.offsetBy(dx: -origin.x, dy: -origin.y), scale)
        let picture = image(size: frame.size, scale: scale) { ctx in
            ctx.translateBy(x: -(frame.minX + origin.x), y: -(frame.minY + origin.y))
            if bulb.behind { ctx.clip(to: aboveTheWindow) }
            let colour = theme.colours[bulb.group]
            if lit {
                drawGlow(ctx, bulb, colour: colour)
                drawBulb(ctx, bulb, colour: colour, socket: theme.wire, lit: true)
            } else {
                shadow(ctx, down: 0.6, blur: 1.2, alpha: 0.35, scale: scale)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                drawBulb(ctx, bulb, colour: colour, socket: theme.wire, lit: false)
                ctx.endTransparencyLayer()
            }
        }
        return (picture, frame)
    }

    /// The tail's cable, drawn into a picture the size of `rect` (same coordinates as `cable`).
    static func tailWire(_ cable: [WrapGeometry.CablePoint], twist: WrapGeometry.Twist, colour: RGB,
                         rect: CGRect, scale: CGFloat) -> CGImage? {
        image(size: rect.size, scale: scale) { ctx in
            ctx.translateBy(x: -rect.minX, y: -rect.minY)
            shadow(ctx, down: 0.6, blur: 1.2, alpha: 0.35, scale: scale)
            drawCable(ctx, [cable], twist: twist, colour: colour)
        }
    }

    /// The rectangle a bulb covers, plus `pad` all round (y down).
    static func bounds(of bulb: WrapGeometry.Bulb, pad: CGFloat) -> CGRect {
        let tip = CGPoint(x: bulb.attach.x + cos(bulb.angle) * bulb.length,
                          y: bulb.attach.y + sin(bulb.angle) * bulb.length)
        let half = bulb.length * widthRatio / 2 + pad
        return CGRect(x: min(bulb.attach.x, tip.x) - half, y: min(bulb.attach.y, tip.y) - half,
                      width: abs(tip.x - bulb.attach.x) + 2 * half, height: abs(tip.y - bulb.attach.y) + 2 * half)
    }

    /// Everything above the window's top edge (y < 0 in window coordinates), where the back of the
    /// coil can be seen.
    private static let aboveTheWindow = CGRect(x: -100_000, y: -100_000, width: 200_000, height: 100_000)

    // MARK: Bulbs

    /// Draws one bulb with its socket at `bulb.attach`, pointing along `bulb.angle`.
    static func drawBulb(_ ctx: CGContext, _ bulb: WrapGeometry.Bulb, colour c: RGB, socket wire: RGB, lit: Bool) {
        let L = bulb.length
        let W = L * widthRatio
        let socketLength = L * 0.3
        let socketWidth = W * 0.86
        let glassTop = socketLength * 0.85   // tucked up inside the socket
        let shoulder = L * 0.7               // where the straight sides end and the point begins

        ctx.saveGState()
        ctx.translateBy(x: bulb.attach.x, y: bulb.attach.y)
        // From here on the bulb points straight down the +y axis, socket at the origin.
        ctx.rotate(by: bulb.angle - .pi / 2)

        // The glass: a capsule with straight sides, narrowing slightly at the socket, then a cone
        // to a point that's just barely rounded.
        let glass = CGMutablePath()
        glass.move(to: CGPoint(x: -socketWidth * 0.45, y: glassTop))
        glass.addLine(to: CGPoint(x: -W / 2, y: glassTop + L * 0.08))
        glass.addLine(to: CGPoint(x: -W / 2, y: shoulder))
        glass.addLine(to: CGPoint(x: -W * 0.09, y: L - W * 0.1))
        glass.addQuadCurve(to: CGPoint(x: W * 0.09, y: L - W * 0.1), control: CGPoint(x: 0, y: L + W * 0.04))
        glass.addLine(to: CGPoint(x: W / 2, y: shoulder))
        glass.addLine(to: CGPoint(x: W / 2, y: glassTop + L * 0.08))
        glass.addLine(to: CGPoint(x: socketWidth * 0.45, y: glassTop))
        glass.closeSubpath()

        // Fill. Lit: hottest by the filament near the socket, then the full colour to the tip.
        // Off: almost black, keeping just a hint of the colour.
        let stops: [RGB] = lit
            ? [c.lighter(0.6), c.lighter(0.15), c, c.darker(0.08)]
            : [c.mix(offGlass, 0.72), c.mix(offGlass, 0.78), c.mix(offGlass, 0.82), c.mix(offGlass, 0.85)]
        let fill = CGGradient(colorsSpace: sRGB, colors: stops.map { $0.cg() } as CFArray,
                              locations: [0, 0.3, 0.7, 1])!
        ctx.saveGState()
        ctx.addPath(glass)
        ctx.clip()
        ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: glassTop), end: CGPoint(x: 0, y: L), options: [])
        // Facets: a pale flat band down the left side and a shaded one down the right, which is
        // what makes TF2's bulbs read as cut glass rather than smooth plastic.
        ctx.setFillColor(RGB(0xFFFFFF).cg(lit ? 0.4 : 0.1))
        ctx.fill(CGRect(x: -W * 0.3, y: glassTop, width: W * 0.2, height: L - glassTop))
        ctx.setFillColor(RGB(0x000000).cg(lit ? 0.16 : 0.25))
        ctx.fill(CGRect(x: W * 0.22, y: glassTop, width: W * 0.3, height: L - glassTop))
        if lit {
            // The hot core, near the socket.
            ctx.setFillColor(RGB(0xFFFFFF).cg(0.5))
            ctx.fillEllipse(in: CGRect(x: -W * 0.1, y: glassTop + L * 0.04, width: W * 0.2, height: L * 0.3))
        }
        ctx.restoreGState()

        // The painted outline.
        ctx.addPath(glass)
        ctx.setStrokeColor((lit ? c.darker(0.55) : RGB(0x000000)).cg(lit ? 1 : 0.6))
        ctx.setLineWidth(max(0.6, L * 0.045))
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // The socket: a small black cylinder with a ring and a sheen.
        let socketColour = wire.darker(0.25)
        let socketRect = CGRect(x: -socketWidth / 2, y: 0, width: socketWidth, height: socketLength)
        let socket = CGPath(roundedRect: socketRect, cornerWidth: socketWidth * 0.25,
                            cornerHeight: socketWidth * 0.25, transform: nil)
        ctx.addPath(socket)
        ctx.setFillColor(socketColour.cg())
        ctx.fillPath()
        ctx.setFillColor(socketColour.lighter(0.18).cg())
        ctx.fill(CGRect(x: socketRect.minX, y: socketLength * 0.6, width: socketWidth, height: max(0.5, L * 0.035)))
        ctx.setFillColor(RGB(0xFFFFFF).cg(0.28))
        ctx.fill(CGRect(x: socketRect.minX + socketWidth * 0.2, y: socketLength * 0.1,
                        width: max(0.5, socketWidth * 0.14), height: socketLength * 0.42))
        ctx.addPath(socket)
        ctx.setStrokeColor(RGB(0x000000).cg(0.7))
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        ctx.restoreGState()
    }

    /// A faint, tight wash of colour around a lit bulb's glass.
    private static func drawGlow(_ ctx: CGContext, _ bulb: WrapGeometry.Bulb, colour: RGB) {
        guard glowStrength > 0 else { return }
        let centre = CGPoint(x: bulb.attach.x + cos(bulb.angle) * bulb.length * 0.6,
                             y: bulb.attach.y + sin(bulb.angle) * bulb.length * 0.6)
        let wash = CGGradient(colorsSpace: sRGB, colors: [colour.cg(glowStrength), colour.cg(0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(wash, startCenter: centre, startRadius: 0, endCenter: centre,
                               endRadius: bulb.length * 0.55, options: [])
    }

    // MARK: Cable

    /// The cable: two strands twisted round each other, like real string-light wire.
    ///
    /// Each strand weaves either side of the centre line. Where a strand is behind the other it's
    /// drawn first and darker; where it's in front it's drawn on top with a thin sheen. `fades`
    /// then rub out the ends where the cable goes round the back of the window.
    static func drawCable(_ ctx: CGContext, _ runs: [[WrapGeometry.CablePoint]], twist t: WrapGeometry.Twist,
                          colour: RGB, fades: [WrapGeometry.Fade] = []) {
        guard !runs.isEmpty else { return }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        typealias StrandPoint = (p: CGPoint, normal: CGVector, depth: CGFloat)
        // Where strand `j` is at each point of `run`, and how far in front of the other strand.
        func strand(_ run: [WrapGeometry.CablePoint], _ j: Int) -> [StrandPoint] {
            run.map { point in
                // A slow wobble in the twist, so it looks wound by hand rather than by machine.
                let phase = 2 * .pi * point.s / t.period + CGFloat(j) * .pi + 0.35 * sin(point.s * 0.045)
                let offset = t.amplitude * sin(phase)
                return (CGPoint(x: point.p.x + point.normal.dx * offset, y: point.p.y + point.normal.dy * offset),
                        point.normal, cos(phase))
            }
        }
        let strands = runs.flatMap { [strand($0, 0), strand($0, 1)] }

        /// Strokes the stretches of a strand whose depth passes `keep`, nudged `lift` points along the normal.
        func strokeRuns(_ points: [StrandPoint], where keep: (CGFloat) -> Bool, lift: CGFloat = 0) {
            var stretch: [CGPoint] = []
            func flush() {
                if stretch.count > 1 { ctx.addLines(between: stretch) }
                stretch.removeAll(keepingCapacity: true)
            }
            for point in points {
                if keep(point.depth) {
                    stretch.append(CGPoint(x: point.p.x + point.normal.dx * lift, y: point.p.y + point.normal.dy * lift))
                } else {
                    flush()
                }
            }
            flush()
            ctx.strokePath()
        }

        // The halves of each strand that pass behind the other.
        ctx.setStrokeColor(colour.darker(0.4).cg())
        ctx.setLineWidth(t.strandWidth)
        for s in strands { strokeRuns(s, where: { $0 < 0 }) }
        // The halves in front.
        ctx.setStrokeColor(colour.cg())
        for s in strands { strokeRuns(s, where: { $0 >= 0 }) }
        // A thin sheen along the front halves, where the light catches them.
        ctx.setStrokeColor(colour.lighter(0.4).cg(0.55))
        ctx.setLineWidth(t.strandWidth * 0.35)
        for s in strands { strokeRuns(s, where: { $0 > 0.35 }, lift: t.strandWidth * 0.2) }

        // Each fade rubs the cable out towards one end, along the line from `to` to `from`.
        let fade = CGGradient(colorsSpace: sRGB, colors: [RGB(0).cg(0), RGB(0).cg(1)] as CFArray, locations: [0, 1])!
        let pad = t.amplitude + t.strandWidth + 2
        ctx.setBlendMode(.destinationIn)
        for f in fades {
            ctx.saveGState()
            let box = CGRect(x: min(f.from.x, f.to.x), y: min(f.from.y, f.to.y),
                             width: abs(f.from.x - f.to.x), height: abs(f.from.y - f.to.y)).insetBy(dx: -pad, dy: -pad)
            ctx.clip(to: box)
            ctx.drawLinearGradient(fade, start: f.from, end: f.to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
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

    /// `r` grown outward to the nearest whole pixels.
    private static func snap(_ r: CGRect, _ scale: CGFloat) -> CGRect {
        let x0 = floor(r.minX * scale) / scale, y0 = floor(r.minY * scale) / scale
        let x1 = ceil(r.maxX * scale) / scale, y1 = ceil(r.maxY * scale) / scale
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// A drop shadow `down` points below. Shadow offsets are measured in pixels with y up,
    /// whatever the drawing transform, hence the scale and the minus sign.
    private static func shadow(_ ctx: CGContext, down: CGFloat, blur: CGFloat, alpha: CGFloat, scale: CGFloat) {
        ctx.setShadow(offset: CGSize(width: 0, height: -down * scale), blur: blur * scale, color: RGB(0).cg(alpha))
    }
}
