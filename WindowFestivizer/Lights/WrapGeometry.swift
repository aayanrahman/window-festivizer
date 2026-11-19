import CoreGraphics
import Foundation

/// Where the cable and the bulbs go for one window, worked out from the window's size alone.
///
/// The cable is laid along the window's outline like a scarf: it comes up the left side, round the
/// top-left corner, along the top edge, round the top-right corner and a little way down the right
/// side, fading out at both ends as if it carried on round the back. Its centre line sits exactly
/// on the window's edge, so it never covers the red, yellow and green buttons.
///
/// Bulbs clip onto the cable at slightly uneven spacing and splay at slightly uneven angles. Most
/// point outward, away from the window; along the top edge some hang down over the title bar.
/// The unevenness comes from a hash of each bulb's number, so a window always looks the same.
///
/// Everything here is window-local: origin at the window's top-left corner, y pointing down.
struct WrapGeometry {
    /// A point on the cable's centre line. The outline is sampled about once per point.
    struct CablePoint {
        var p: CGPoint
        /// Unit vector pointing away from the window: up along the top edge, sideways down the sides.
        var outward: CGVector
        /// Distance along the cable from its start.
        var s: CGFloat
    }

    struct Bulb {
        /// Where the bulb's socket clips onto the cable.
        var attach: CGPoint
        /// The direction the bulb points, in radians. y is down, so -π/2 is straight up.
        var angle: CGFloat
        var length: CGFloat
        /// Which of the theme's three colours it is: 0, 1 or 2.
        var group: Int
    }

    let cable: [CablePoint]
    /// Width of each of the cable's two twisted strands.
    let strandWidth: CGFloat
    /// How far each strand swings either side of the centre line as the pair twists.
    let twistAmplitude: CGFloat
    /// Length of cable for one full twist.
    let twistPeriod: CGFloat
    /// The cable fades out over this length at each end.
    let fadeLength: CGFloat
    let bulbs: [Bulb]
    /// What the overlay window covers: the cable and every bulb, with a little room for shadows.
    let stripRect: CGRect

    /// Roughly the corner radius of a macOS window. The cable straddles the edge, so being a few
    /// points off for some windows doesn't show.
    static let cornerRadius: CGFloat = 12
    /// Bulbs only hang down over the title bar to the right of this, clear of the window buttons.
    static let buttonsWidth: CGFloat = 84

    init(windowSize size: CGSize, scale k: CGFloat) {
        strandWidth = 1.8 * k
        twistAmplitude = 0.55 * strandWidth
        twistPeriod = 7 * k
        fadeLength = 12 * k
        let drop = 16 * k   // how far the cable runs down each side before it's gone
        let radius = min(Self.cornerRadius, size.width / 4, size.height / 4)
        let cable = Self.outline(size: size, cornerRadius: radius, drop: drop)
        self.cable = cable

        var bulbs: [Bulb] = []
        let baseLength = (12 * k).rounded()
        let last = (cable.last?.s ?? 0) - fadeLength - 2
        var s = fadeLength + 2
        var index = 0
        var pointsOut = true
        var cursor = 0
        while s < last {
            while cursor + 1 < cable.count && cable[cursor].s < s { cursor += 1 }
            let at = cable[cursor]
            let n = (side: Self.noise(index, 1), angle: Self.noise(index, 2),
                     length: Self.noise(index, 3), gap: Self.noise(index, 4))

            // Along the top edge, past the buttons, bulbs mostly alternate between pointing up and
            // hanging down, with the odd repeat so the rhythm isn't perfect. Elsewhere they point out.
            if n.side > 0.22 { pointsOut.toggle() }
            let canHang = at.outward.dy < -0.999 && at.p.x > Self.buttonsWidth
            let out = pointsOut || !canHang
            let straight = atan2(at.outward.dy, at.outward.dx) + (out ? 0 : .pi)
            // The socket clips onto the side of the cable the bulb points from.
            let lift = twistAmplitude * 0.6 * (out ? 1 : -1)
            bulbs.append(Bulb(attach: CGPoint(x: at.p.x + at.outward.dx * lift, y: at.p.y + at.outward.dy * lift),
                              angle: straight + (n.angle - 0.5) * 1.0,
                              length: baseLength * (0.9 + 0.2 * n.length),
                              group: index % 3))
            s += baseLength * (1.55 + 0.9 * n.gap)
            index += 1
        }
        self.bulbs = bulbs

        // Cover the cable (both strands at full swing) and every bulb, plus room for shadows.
        let reach = twistAmplitude + strandWidth + 2
        var rect = CGRect.null
        for point in cable { rect = rect.union(CGRect(x: point.p.x, y: point.p.y, width: 0, height: 0)) }
        rect = rect.insetBy(dx: -reach, dy: -reach)
        for bulb in bulbs { rect = rect.union(BulbArt.bounds(of: bulb, pad: 2)) }
        stripRect = rect.integral
    }

    /// The window's outline, from partway down the left side, over the top, to partway down the
    /// right side, about one point apart.
    private static func outline(size: CGSize, cornerRadius r: CGFloat, drop: CGFloat) -> [CablePoint] {
        var points: [CablePoint] = []
        var s: CGFloat = 0
        func add(_ p: CGPoint, _ outward: CGVector) {
            if let previous = points.last { s += hypot(p.x - previous.p.x, p.y - previous.p.y) }
            points.append(CablePoint(p: p, outward: outward, s: s))
        }
        let w = size.width
        let arcSteps = max(4, Int((r * .pi / 2).rounded(.up)))

        // Up the left side.
        for y in stride(from: r + drop, to: r, by: -1) { add(CGPoint(x: 0, y: y), CGVector(dx: -1, dy: 0)) }
        // Round the top-left corner: angles π to 3π/2 (y down, so 3π/2 points up).
        for i in 0...arcSteps {
            let a = .pi + .pi / 2 * CGFloat(i) / CGFloat(arcSteps)
            add(CGPoint(x: r + r * cos(a), y: r + r * sin(a)), CGVector(dx: cos(a), dy: sin(a)))
        }
        // Along the top.
        for x in stride(from: r + 1, to: w - r, by: 1) { add(CGPoint(x: x, y: 0), CGVector(dx: 0, dy: -1)) }
        // Round the top-right corner: angles 3π/2 to 2π.
        for i in 0...arcSteps {
            let a = 1.5 * .pi + .pi / 2 * CGFloat(i) / CGFloat(arcSteps)
            add(CGPoint(x: w - r + r * cos(a), y: r + r * sin(a)), CGVector(dx: cos(a), dy: sin(a)))
        }
        // Down the right side.
        for y in stride(from: r + 1, through: r + drop, by: 1) { add(CGPoint(x: w, y: y), CGVector(dx: 1, dy: 0)) }
        return points
    }

    /// A repeatable "random" number in 0...1 for bulb `i`. `salt` picks an independent stream, so the
    /// side, angle, length and spacing of a bulb don't move in lockstep.
    static func noise(_ i: Int, _ salt: Int) -> CGFloat {
        var h = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ salt &* 668_265_263 &+ 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return CGFloat(h & 0xFFFF) / 65535
    }
}
