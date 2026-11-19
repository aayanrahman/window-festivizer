import QuartzCore

// The lights as Core Animation layers.
//
// Layers here use Core Animation's usual macOS coordinates: origin at the bottom-left, y up.
// WrapGeometry works with y down, so points are flipped on the way in (see `StripLayers.init`
// and `TailLayers.layout`).

/// A set of bulbs.
///
/// Each bulb is three small layers showing sprites drawn once by BulbArt: its glow, its glass
/// switched off, and its glass switched on. The "on" glass and glow for each colour live in a
/// shared parent layer, so the Festivizer blink is just a few opacity changes per window each beat.
/// Core Animation does the fading, so the app itself barely wakes up.
final class BulbBank {
    /// Goes behind the wire.
    let glowLayer = CALayer()
    /// Goes in front of the wire.
    let bodyLayer = CALayer()

    private let unlitGroup = CALayer()
    private var litGroups: [CALayer] = []
    private var glowGroups: [CALayer] = []
    private var bulbs: [(unlit: CALayer, lit: CALayer, glow: CALayer)] = []
    private let metrics: BulbArt.Metrics

    /// `groups` lists each bulb's colour (0, 1 or 2), in order.
    init(theme: Theme, groups: [Int], length: CGFloat, glowRadius: CGFloat, scale: CGFloat) {
        metrics = BulbArt.Metrics(length: length)
        bodyLayer.addSublayer(unlitGroup)
        for _ in 0..<3 {
            let glows = CALayer(), lits = CALayer()
            glowLayer.addSublayer(glows)
            bodyLayer.addSublayer(lits)
            glowGroups.append(glows)
            litGroups.append(lits)
        }

        let canvas = metrics.canvas
        let glowSize = CGSize(width: glowRadius * 2, height: glowRadius * 2)
        // The sprite turns about its attach point (the top of the socket), not its centre.
        let pivot = CGPoint(x: 0.5, y: 1 - metrics.attach.y / canvas.height)
        for group in groups {
            let colour = theme.colours[group]
            let unlit = BulbBank.sprite(BulbArt.bulb(colour, .unlit, length: length, scale: scale), canvas, scale)
            let lit = BulbBank.sprite(BulbArt.bulb(colour, .lit, length: length, scale: scale), canvas, scale)
            let glow = BulbBank.sprite(BulbArt.glow(colour, radius: glowRadius, scale: scale), glowSize, scale)
            unlit.anchorPoint = pivot
            lit.anchorPoint = pivot
            unlitGroup.addSublayer(unlit)
            litGroups[group].addSublayer(lit)
            glowGroups[group].addSublayer(glow)
            bulbs.append((unlit, lit, glow))
        }
    }

    /// Make every container cover `bounds`.
    func setBounds(_ bounds: CGRect) {
        for layer in [glowLayer, bodyLayer, unlitGroup] + litGroups + glowGroups {
            layer.frame = bounds
        }
    }

    /// Put bulb `i` with its socket at `attach`, pointing along `angle` (radians, y up).
    /// Call inside a transaction with actions disabled, or Core Animation will slide it there.
    func place(_ i: Int, attach: CGPoint, angle: CGFloat) {
        let bulb = bulbs[i]
        // Sprites point straight down, which is an angle of −π/2 with y up.
        let spin = CATransform3DMakeRotation(angle + .pi / 2, 0, 0, 1)
        for layer in [bulb.unlit, bulb.lit] {
            layer.position = attach
            layer.transform = spin
        }
        let reach = metrics.glassCentre
        bulb.glow.position = CGPoint(x: attach.x + cos(angle) * reach, y: attach.y + sin(angle) * reach)
    }

    /// Switch each colour on or off for this beat of the pattern.
    func light(beat: Int, pattern: LightPattern, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(FestivizerPattern.fade)
        } else {
            CATransaction.setDisableActions(true)
        }
        for group in 0..<3 {
            let on: Float = FestivizerPattern.isLit(group: group, beat: beat, pattern: pattern) ? 1 : 0
            litGroups[group].opacity = on
            glowGroups[group].opacity = on
        }
        CATransaction.commit()
    }

    private static func sprite(_ image: CGImage?, _ size: CGSize, _ scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.contents = image
        layer.contentsScale = scale
        layer.bounds = CGRect(origin: .zero, size: size)
        return layer
    }
}

/// Everything along one window's top edge: glow, then wire, then bulbs.
final class StripLayers {
    let root = CALayer()
    let bank: BulbBank

    init(geometry g: WrapGeometry, theme: Theme, scale: CGFloat) {
        bank = BulbBank(theme: theme, groups: g.bulbs.map(\.group), length: g.bulbLength,
                        glowRadius: g.glowRadius, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rect = g.stripRect
        root.frame = CGRect(origin: .zero, size: rect.size)
        bank.setBounds(root.bounds)

        let wire = CALayer()
        wire.frame = root.bounds
        wire.contents = BulbArt.wire(g, colour: theme.wire, scale: scale)
        wire.contentsScale = scale

        root.addSublayer(bank.glowLayer)
        root.addSublayer(wire)
        root.addSublayer(bank.bodyLayer)

        // Window-local (y down) → this layer (y up, origin at the strip's bottom-left).
        for (i, bulb) in g.bulbs.enumerated() {
            bank.place(i, attach: CGPoint(x: bulb.attach.x - rect.minX, y: rect.maxY - bulb.attach.y),
                       angle: -bulb.angle)
        }
        CATransaction.commit()
    }
}

/// The short string of lights hanging off a window's right corner. Redrawn every physics step.
final class TailLayers {
    let root = CALayer()
    let bank: BulbBank
    private let wire = CAShapeLayer()
    private let nodes: [Int]

    init(geometry g: WrapGeometry, theme: Theme, scale: CGFloat) {
        nodes = g.tailBulbs.map(\.node)
        bank = BulbBank(theme: theme, groups: g.tailBulbs.map(\.group), length: g.bulbLength,
                        glowRadius: g.glowRadius, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        root.frame = CGRect(origin: .zero, size: g.tailRect.size)
        bank.setBounds(root.bounds)

        wire.frame = root.bounds
        wire.fillColor = nil
        wire.strokeColor = theme.wire.cg()
        wire.lineWidth = g.wireWidth
        wire.lineCap = .round
        wire.lineJoin = .round
        wire.shadowColor = RGB(0).cg()
        wire.shadowOpacity = 0.4
        wire.shadowRadius = 0.75
        wire.shadowOffset = CGSize(width: 0, height: -1)

        root.addSublayer(bank.glowLayer)
        root.addSublayer(wire)
        root.addSublayer(bank.bodyLayer)
        CATransaction.commit()
    }

    /// Redraw for the chain's current shape. `points` and `rect` (the overlay's rectangle) must be
    /// in the same y-down coordinates; it doesn't matter which.
    func layout(points: [CGPoint], in rect: CGRect) {
        guard points.count >= 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - rect.minX, y: rect.maxY - p.y) }

        // A smooth curve through the chain: curve towards each point, ending halfway to the next.
        let path = CGMutablePath()
        path.move(to: up(points[0]))
        for i in 1..<(points.count - 1) {
            let a = up(points[i]), b = up(points[i + 1])
            path.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        path.addLine(to: up(points[points.count - 1]))
        wire.path = path

        // Bulbs stick out to alternate sides of the hanging wire.
        for (j, node) in nodes.enumerated() where node < points.count {
            let a = points[node - 1], b = points[node]
            let along = atan2(b.y - a.y, b.x - a.x)
            let tilt: CGFloat = j % 2 == 0 ? 0.9 : -0.9
            bank.place(j, attach: up(b), angle: -(along + tilt))
        }
        CATransaction.commit()
    }
}
