import QuartzCore

// The lights as Core Animation layers.
//
// The cable and the switched-off bulbs are drawn into pictures; each lit bulb is its own small
// picture sitting exactly on top of its switched-off self. Lit bulbs of the same colour share a
// parent layer, so the Festivizer blink is a few opacity changes per window each beat, and Core
// Animation does the fading without the app drawing anything.
//
// Core Animation's coordinates on macOS have y pointing up, while BulbArt and WrapGeometry use y
// down, so every frame is flipped on the way in (`flipped`).

/// A rectangle measured with y down from the top of a box `height` tall, measured with y up instead.
private func flipped(_ frame: CGRect, in height: CGFloat) -> CGRect {
    CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
}

private func groupLayers(_ bounds: CGRect) -> [CALayer] {
    (0..<3).map { _ in
        let layer = CALayer()
        layer.frame = bounds
        return layer
    }
}

private func lightGroups(_ groups: [CALayer], beat: Int, pattern: LightPattern, animated: Bool) {
    CATransaction.begin()
    if animated {
        CATransaction.setAnimationDuration(FestivizerPattern.fade)
    } else {
        CATransaction.setDisableActions(true)
    }
    for (i, layer) in groups.enumerated() {
        layer.opacity = FestivizerPattern.isLit(group: i % 3, beat: beat, pattern: pattern) ? 1 : 0
    }
    CATransaction.commit()
}

/// Everything along one window's top edge. From the bottom up: the back of the coil and its
/// bulbs (Wrapped Around only), their lit versions, the cable in front and its bulbs, and their
/// lit versions.
final class StripLayers {
    let root = CALayer()
    private var litGroups: [CALayer] = []

    init(geometry g: WrapGeometry, theme: Theme, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let rect = g.stripRect
        root.frame = CGRect(origin: .zero, size: rect.size)

        func picture(_ image: CGImage?) -> CALayer {
            let layer = CALayer()
            layer.frame = root.bounds
            layer.contents = image
            layer.contentsScale = scale
            return layer
        }

        let litBehind = groupLayers(root.bounds)
        let litFront = groupLayers(root.bounds)
        if !g.backRuns.isEmpty || g.bulbs.contains(where: \.behind) {
            root.addSublayer(picture(BulbArt.strip(g, theme: theme, behind: true, scale: scale)))
        }
        litBehind.forEach(root.addSublayer)
        root.addSublayer(picture(BulbArt.strip(g, theme: theme, behind: false, scale: scale)))
        litFront.forEach(root.addSublayer)

        for bulb in g.bulbs {
            let (image, frame) = BulbArt.bulbPicture(bulb, lit: true, theme: theme, origin: rect.origin, scale: scale)
            let layer = CALayer()
            layer.contents = image
            layer.contentsScale = scale
            layer.frame = flipped(frame, in: rect.height)
            (bulb.behind ? litBehind : litFront)[bulb.group].addSublayer(layer)
        }
        litGroups = litBehind + litFront
        CATransaction.commit()
    }

    func light(beat: Int, pattern: LightPattern, animated: Bool) {
        lightGroups(litGroups, beat: beat, pattern: pattern, animated: animated)
    }
}

/// The free end of the cable hanging off a window's corner. Redrawn, crisply, on every physics
/// step while it swings; nothing is drawn while it's still.
final class TailLayers {
    let root = CALayer()
    private let wire = CALayer()
    private var unlit: [CALayer] = []
    private var lit: [CALayer] = []
    private let litGroups: [CALayer]
    private let tail: WrapGeometry.Tail
    private let twist: WrapGeometry.Twist
    private let theme: Theme
    private let scale: CGFloat

    init(tail: WrapGeometry.Tail, twist: WrapGeometry.Twist, theme: Theme, scale: CGFloat) {
        self.tail = tail
        self.twist = twist
        self.theme = theme
        self.scale = scale
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        root.frame = CGRect(origin: .zero, size: tail.rect.size)
        wire.frame = root.bounds
        wire.contentsScale = scale
        root.addSublayer(wire)

        litGroups = groupLayers(root.bounds)
        for j in tail.bulbNodes.indices {
            let off = CALayer(), on = CALayer()
            off.contentsScale = scale
            on.contentsScale = scale
            root.addSublayer(off)
            litGroups[(tail.firstGroup + j) % 3].addSublayer(on)
            unlit.append(off)
            lit.append(on)
        }
        litGroups.forEach(root.addSublayer)
        CATransaction.commit()
    }

    /// Redraw for the chain's current shape. `points` and `rect` (the tail overlay's rectangle)
    /// share one y-down coordinate space; it doesn't matter which.
    func layout(points: [CGPoint], in rect: CGRect) {
        guard points.count >= 2 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let curve = WrapGeometry.cable(WrapGeometry.smoothCurve(through: points))
        wire.contents = BulbArt.tailWire(curve, twist: twist, colour: theme.wire, rect: rect, scale: scale)

        // Bulbs stick out to alternate sides of the hanging wire, splayed by different amounts.
        for (j, node) in tail.bulbNodes.enumerated() where node < points.count {
            let a = points[node - 1], b = points[node]
            let along = atan2(b.y - a.y, b.x - a.x)
            let tilt = (j % 2 == 0 ? 1 : -1) * (1.0 + 0.4 * WrapGeometry.noise(j, 7))
            let bulb = WrapGeometry.Bulb(attach: b, angle: along + tilt,
                                         length: tail.bulbLength * (0.85 + 0.3 * WrapGeometry.noise(j, 8)),
                                         group: (tail.firstGroup + j) % 3)
            for (layer, isLit) in [(unlit[j], false), (lit[j], true)] {
                let (image, frame) = BulbArt.bulbPicture(bulb, lit: isLit, theme: theme, origin: rect.origin, scale: scale)
                layer.contents = image
                layer.frame = flipped(frame, in: rect.height)
            }
        }
        CATransaction.commit()
    }

    func light(beat: Int, pattern: LightPattern, animated: Bool) {
        lightGroups(litGroups, beat: beat, pattern: pattern, animated: animated)
    }
}
