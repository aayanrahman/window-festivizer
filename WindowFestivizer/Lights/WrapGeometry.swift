import CoreGraphics
import Foundation

/// Where the wire and the bulbs go for one window, worked out from the window's size alone.
///
/// Picture the window's top edge as a pole lying on its side, with the string of lights wound
/// round it like tinsel round a banister. Along the pole the wire follows a helix:
///
///     x(θ)     = start + pitch · θ / 2π     one `pitch` to the right per turn
///     y(θ)     = axis − R · cos θ           θ = 0 at the top of the pole, θ = π at the bottom
///     depth(θ) = sin θ                      positive: on the front of the pole, facing you
///
/// Only the front half of each turn (0 < θ < π) is drawn. The wire fades out as it rounds the
/// top and bottom of the pole, which reads as it slipping round the back and coming over again.
///
/// Everything here is window-local: origin at the window's top-left corner, y pointing down.
struct WrapGeometry {
    struct WirePoint {
        var p: CGPoint
        /// 0 at the top and bottom of the pole (about to go behind), 1 right in front.
        var depth: CGFloat
    }

    struct Bulb {
        /// Where the bulb's socket clips onto the wire.
        var attach: CGPoint
        /// The direction the bulb points, in radians. y is down, so π/2 is straight down.
        var angle: CGFloat
        /// Which of the theme's three colours it is: 0, 1 or 2.
        var group: Int
    }

    /// Radius of the pole.
    let radius: CGFloat
    let bulbLength: CGFloat
    let glowRadius: CGFloat
    let wireWidth: CGFloat

    /// The visible front half of each turn, left to right.
    let arcs: [[WirePoint]]
    let bulbs: [Bulb]
    /// What the strip overlay covers: the wrap plus room for the bulbs and their glow.
    let stripRect: CGRect

    /// Where the swinging tail hangs from: just past the window's right edge.
    let tailAnchor: CGPoint
    let tailSegments: Int
    let tailSegmentLength: CGFloat
    /// Which points along the tail carry a bulb, and in which colour.
    let tailBulbs: [(node: Int, group: Int)]
    /// What the tail overlay covers: room for the tail to swing to either side.
    let tailRect: CGRect

    /// Room left clear on the left for the red, yellow and green buttons.
    static let buttonsWidth: CGFloat = 78

    init(windowSize size: CGSize, radius R: CGFloat) {
        radius = R
        bulbLength = (R * 1.35).rounded()
        glowRadius = (bulbLength * 1.05).rounded()
        wireWidth = max(1.5, R * 0.2)

        // The pole lies along the top of the title bar, its top flush with the window's top edge.
        // So the wire comes over the window's edge, crosses the title bar, and tucks under.
        let axis = R
        let start = WrapGeometry.buttonsWidth
        let end = max(start + R * 4, size.width - R * 0.3)

        // About 3.4 radii per turn reads as a snug coil. Round to a whole number of turns that fits exactly.
        let turns = max(1, Int(((end - start) / (R * 3.4)).rounded()))
        let pitch = (end - start) / CGFloat(turns)

        func point(_ theta: CGFloat) -> CGPoint {
            CGPoint(x: start + pitch * theta / (2 * .pi), y: axis - R * cos(theta))
        }

        var arcs: [[WirePoint]] = []
        var bulbs: [Bulb] = []
        let steps = 24
        for k in 0..<turns {
            let base = 2 * CGFloat.pi * CGFloat(k)
            arcs.append((0...steps).map { i in
                let u = CGFloat.pi * CGFloat(i) / CGFloat(steps)
                return WirePoint(p: point(base + u), depth: sin(u))
            })

            // One bulb per turn, alternating between the upper and lower part of the pole's front.
            // Bulbs stick out from the pole: upper ones point up past the window's edge, lower ones
            // hang down over the title bar. Each is tipped by a repeatable random amount so they
            // splay in different directions, like the Festivizer's.
            let upper = k % 2 == 0
            let wobble = WrapGeometry.wobble(k)
            let theta = base + (upper ? 0.3 : 0.7) * .pi + 0.06 * wobble
            let outward: CGFloat = upper ? -.pi / 2 : .pi / 2
            bulbs.append(Bulb(attach: point(theta), angle: outward + 0.5 * wobble, group: k % 3))
        }
        self.arcs = arcs
        self.bulbs = bulbs

        let reach = bulbLength + glowRadius
        stripRect = CGRect(x: start - reach, y: axis - R - reach,
                           width: end - start + 2 * reach, height: 2 * R + 2 * reach).integral

        // The coil ends at the window's right edge and the tail drops from there, as if the wire
        // came round the back of the pole and fell off the end.
        tailAnchor = CGPoint(x: size.width + 1.5, y: axis)
        tailSegments = 6
        tailSegmentLength = (R * 1.15).rounded()
        tailBulbs = [2, 4, 6].enumerated().map { j, node in (node, (turns + j) % 3) }
        // The tail can swing anywhere within its own length of the anchor.
        let tailReach = CGFloat(tailSegments) * tailSegmentLength + reach
        tailRect = CGRect(x: tailAnchor.x - tailReach, y: tailAnchor.y - tailReach,
                          width: 2 * tailReach, height: 2 * tailReach).integral
    }

    /// A repeatable "random" number in -1...1 for bulb `k`, so the wobble is the same every time.
    static func wobble(_ k: Int) -> CGFloat {
        var h = UInt32(truncatingIfNeeded: k &* 374_761_393 &+ 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return CGFloat(h & 0xFFFF) / 32767.5 - 1
    }
}
