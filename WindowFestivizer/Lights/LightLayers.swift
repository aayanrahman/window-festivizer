import QuartzCore

/// One window's lights as Core Animation layers.
///
/// The cable and every bulb switched off are one picture at the bottom. Each lit bulb is its own
/// small picture sitting exactly on top of its switched-off self, and the lit bulbs of each colour
/// share a parent layer. So the Festivizer blink is three opacity changes per window each beat,
/// and Core Animation does the fading without the app doing any drawing.
///
/// Core Animation's coordinates on macOS have y pointing up; BulbArt and WrapGeometry use y down,
/// so frames are flipped on the way in.
final class StripLayers {
    let root = CALayer()
    private var litGroups: [CALayer] = []

    init(geometry g: WrapGeometry, theme: Theme, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let size = g.stripRect.size
        root.frame = CGRect(origin: .zero, size: size)

        let base = CALayer()
        base.frame = root.bounds
        base.contents = BulbArt.base(g, theme: theme, scale: scale)
        base.contentsScale = scale
        root.addSublayer(base)

        for _ in 0..<3 {
            let group = CALayer()
            group.frame = root.bounds
            root.addSublayer(group)
            litGroups.append(group)
        }
        for bulb in g.bulbs {
            let (picture, frame) = BulbArt.litBulb(bulb, in: g.stripRect, theme: theme, scale: scale)
            let layer = CALayer()
            layer.contents = picture
            layer.contentsScale = scale
            layer.frame = CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
            litGroups[bulb.group].addSublayer(layer)
        }
        CATransaction.commit()
    }

    /// Switch each colour on or off for this beat of the pattern.
    func light(beat: Int, pattern: LightPattern, animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(FestivizerPattern.fade)
        } else {
            CATransaction.setDisableActions(true)
        }
        for (group, layer) in litGroups.enumerated() {
            layer.opacity = FestivizerPattern.isLit(group: group, beat: beat, pattern: pattern) ? 1 : 0
        }
        CATransaction.commit()
    }
}
