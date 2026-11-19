import CoreGraphics
import Foundation

/// Where the cable, the bulbs and the tail go for one window, worked out from the window's size.
///
/// There are two styles (see WrapStyle):
///
/// Wrapped Around: the cable is wound round the top of the window the way the Festivizer winds it
/// round a gun, as a loose, uneven coil. Picture the top of the title bar as a pole lying on its
/// side. Each turn comes up the back of the pole, over the top (where it shows just above the
/// window's edge), down across the front, and under the bottom, out of sight. The spacing,
/// thickness and height of the coil wander as it goes, and the bulbs stick out at all angles.
///
/// Laid on Top: the cable lies along the window's outline like a scarf, up the left side, round
/// the top-left corner, along the top edge and round the top-right corner. Bulbs mostly point
/// outward; along the top edge some hang down over the title bar.
///
/// With a tail, the last of the cable leaves the window near its top-right corner and hangs free
/// (see SwingingTail).
///
/// All the unevenness comes from fixed sine waves and from hashes of each bulb's number, so a
/// window always looks the same. Everything here is window-local: origin at the window's top-left
/// corner, y pointing down.
struct WrapGeometry {
    /// A point on the cable's centre line.
    struct CablePoint {
        var p: CGPoint
        /// A unit vector to one side of the cable, which the two twisted strands weave either side of.
        var normal: CGVector
        /// Distance along the cable, so the twist carries on smoothly from one run to the next.
        var s: CGFloat
    }

    /// The cable is invisible at `from` and fully drawn by `to`, fading along the line between them.
    struct Fade {
        var from: CGPoint
        var to: CGPoint
    }

    struct Bulb {
        /// Where the bulb's socket clips onto the cable.
        var attach: CGPoint
        /// The direction the bulb points, in radians. y is down, so -π/2 is straight up.
        var angle: CGFloat
        var length: CGFloat
        /// Which of the theme's three colours it is: 0, 1 or 2.
        var group: Int
        /// On the back of the coil: only the part above the window's top edge shows.
        var behind = false
    }

    /// How the cable's two strands are twisted together.
    struct Twist {
        /// Width of each strand.
        var strandWidth: CGFloat
        /// How far each strand swings either side of the centre line.
        var amplitude: CGFloat
        /// Length of cable for one full twist.
        var period: CGFloat
    }

    /// The free end of the cable.
    struct Tail {
        /// Where it hangs from.
        var anchor: CGPoint
        /// The way it leaves the anchor (a unit vector). The wire's stiffness carries it on that
        /// way for a bit before gravity bends it down.
        var lead: CGVector
        var segments: Int
        var segmentLength: CGFloat
        /// Which links carry a bulb.
        var bulbNodes: [Int]
        /// Colour of the first bulb on the tail; the rest follow on.
        var firstGroup: Int
        var bulbLength: CGFloat
        /// What the tail's overlay covers: room to swing any way it likes.
        var rect: CGRect
    }

    let twist: Twist
    /// Cable passing behind the window, drawn first and darker, and only where it's above the
    /// window's top edge.
    let backRuns: [[CablePoint]]
    /// Cable in front, drawn on top.
    let frontRuns: [[CablePoint]]
    /// Where the front cable fades away as it goes round the back.
    let fades: [Fade]
    let bulbs: [Bulb]
    let tail: Tail?
    /// What the strip overlay covers: all the cable and every bulb, with a little room for shadows.
    let stripRect: CGRect

    /// Roughly the corner radius of a macOS window. The cable straddles the edge, so being a few
    /// points off for some windows doesn't show.
    static let cornerRadius: CGFloat = 12
    /// Nothing goes on the title bar left of this, so the window buttons stay clear.
    static let buttonsWidth: CGFloat = 84

    init(windowSize size: CGSize, style: WrapStyle, scale k: CGFloat, tail wantsTail: Bool) {
        let strand = 1.8 * k
        twist = Twist(strandWidth: strand, amplitude: 0.55 * strand, period: 7 * k)

        let parts = style == .wrapped
            ? Self.wrapped(size: size, k: k, tail: wantsTail)
            : Self.laidOnTop(size: size, k: k, tail: wantsTail, twist: twist)
        backRuns = parts.back
        frontRuns = parts.front
        fades = parts.fades
        bulbs = parts.bulbs
        tail = parts.tail

        // Cover the cable (both strands at full swing) and every bulb, plus room for shadows.
        var rect = CGRect.null
        for run in frontRuns { for c in run { rect = rect.union(CGRect(origin: c.p, size: .zero)) } }
        for run in backRuns { for c in run where c.p.y < 0 { rect = rect.union(CGRect(origin: c.p, size: .zero)) } }
        let reach = twist.amplitude + twist.strandWidth + 2
        rect = rect.insetBy(dx: -reach, dy: -reach)
        for bulb in bulbs {
            var box = BulbArt.bounds(of: bulb, pad: 2)
            if bulb.behind { box.size.height = max(0, min(box.maxY, 2) - box.minY) }
            if box.height > 0 { rect = rect.union(box) }
        }
        stripRect = rect.integral
    }

    private struct Parts {
        var back: [[CablePoint]] = []
        var front: [[CablePoint]] = []
        var fades: [Fade] = []
        var bulbs: [Bulb] = []
        var tail: Tail?
    }

    // MARK: Wrapped Around

    private static func wrapped(size: CGSize, k: CGFloat, tail wantsTail: Bool) -> Parts {
        var parts = Parts()
        let R = 7.5 * k               // the pole's radius, before it wanders
        let axis = 0.6 * R            // so the pole's top pokes a little above the window's edge
        let start = buttonsWidth
        let end = size.width - (wantsTail ? 0.3 : 0.6) * R
        let basePitch = 3 * R         // distance along the window per turn, before it wanders
        let stepsPerTurn = 72

        // Walk round and round the pole a little at a time. θ = 0 is the top of the pole, π the
        // bottom; sin θ > 0 is the front. The pitch, radius and height wander on slow sine waves.
        var points: [CGPoint] = []
        var front: [Bool] = []
        var phases: [CGFloat] = []
        var x = start
        var step = 0
        // Stop at the bottom of a turn, or at the top if a tail carries on from there, once
        // another turn wouldn't fit.
        let stopAt = wantsTail ? 0 : stepsPerTurn / 2
        while true {
            let theta = 2 * CGFloat.pi * CGFloat(step) / CGFloat(stepsPerTurn)
            let radius = R * (1 + 0.1 * sin(0.37 * theta + 1.3) + 0.06 * sin(0.91 * theta))
            let centre = axis + 0.12 * R * sin(0.29 * theta + 0.4)
            points.append(CGPoint(x: x, y: centre - radius * cos(theta)))
            front.append(step % stepsPerTurn <= stepsPerTurn / 2)
            phases.append(theta.truncatingRemainder(dividingBy: 2 * .pi))
            if step > 0, step % stepsPerTurn == stopAt, x + basePitch * 0.7 > end { break }
            let pitch = basePitch * (1 + 0.32 * sin(0.53 * theta) + 0.18 * sin(1.7 * theta + 1))
            x += pitch / CGFloat(stepsPerTurn)
            step += 1
        }

        // Split into front and back runs. Neighbouring runs share their end point so they join up.
        let cable = Self.cable(points)
        var run: [CablePoint] = []
        var runIsFront = front[0]
        for (i, point) in cable.enumerated() {
            run.append(point)
            let next = i + 1 < cable.count ? front[i + 1] : runIsFront
            if next != runIsFront || i == cable.count - 1 {
                if runIsFront { parts.front.append(run) } else { parts.back.append(run) }
                run = [point]
                runIsFront = next
            }
        }

        // Each front run ends at the bottom of the pole, going under and out of sight: fade it.
        // The very first one also fades in, since nothing comes before it.
        let fadeLength = 6 * k
        for (i, run) in parts.front.enumerated() {
            guard let first = run.first, let last = run.last else { continue }
            if let inner = run.last(where: { $0.s <= last.s - fadeLength }) {
                parts.fades.append(Fade(from: last.p, to: inner.p))
            }
            if i == 0, let inner = run.first(where: { $0.s >= first.s + fadeLength }) {
                parts.fades.append(Fade(from: first.p, to: inner.p))
            }
        }

        // Bulbs every half turn or so, give or take. Those on the front point up from the top of
        // the pole and down from the bottom, either way from the middle; those on the back are
        // only kept near the top, where they peek over the window's edge. All splay widely.
        let baseLength = (12 * k).rounded()
        var i = 10
        var attempt = 0
        while i < cable.count - 10 {
            let n = (side: noise(attempt, 1), angle: noise(attempt, 2), length: noise(attempt, 3), gap: noise(attempt, 4))
            let phase = phases[i]
            let behind = phase > .pi
            if !behind || phase > 2 * .pi - 0.85 {
                let c = cos(phase)
                let up = behind || c > 0.3 || (c > -0.3 && n.side < 0.5)
                parts.bulbs.append(Bulb(attach: cable[i].p,
                                        angle: (up ? -CGFloat.pi / 2 : .pi / 2) + (n.angle - 0.5) * 1.7,
                                        length: baseLength * (0.8 + 0.4 * n.length),
                                        group: parts.bulbs.count % 3, behind: behind))
            }
            i += Int(CGFloat(stepsPerTurn) * (0.3 + 0.45 * n.gap))
            attempt += 1
        }

        if wantsTail, let last = points.last {
            // The coil finished at the top of the pole; the rest of the cable carries on from there.
            parts.tail = tail(anchor: last, lead: CGVector(dx: cos(-0.1), dy: sin(-0.1)), k: k,
                              firstGroup: parts.bulbs.count % 3)
        }
        return parts
    }

    // MARK: Laid on Top

    private static func laidOnTop(size: CGSize, k: CGFloat, tail wantsTail: Bool, twist: Twist) -> Parts {
        var parts = Parts()
        let w = size.width
        let r = min(cornerRadius, w / 4, size.height / 4)
        let drop = 16 * k           // how far the cable runs down each side before it's gone
        let fadeLength = 12 * k
        let arcSteps = max(4, Int((r * .pi / 2).rounded(.up)))

        var points: [CGPoint] = []
        var outward: [CGVector] = []
        func add(_ p: CGPoint, _ n: CGVector) {
            points.append(p)
            outward.append(n)
        }
        // Up the left side.
        for y in stride(from: r + drop, to: r, by: -1) { add(CGPoint(x: 0, y: y), CGVector(dx: -1, dy: 0)) }
        // Round the top-left corner: angles π to 3π/2 (y down, so 3π/2 points up).
        for i in 0...arcSteps {
            let a = .pi + .pi / 2 * CGFloat(i) / CGFloat(arcSteps)
            add(CGPoint(x: r + r * cos(a), y: r + r * sin(a)), CGVector(dx: cos(a), dy: sin(a)))
        }
        // Along the top.
        for x in stride(from: r + 1, to: w - r, by: 1) { add(CGPoint(x: x, y: 0), CGVector(dx: 0, dy: -1)) }
        if !wantsTail {
            // Round the top-right corner (angles 3π/2 to 2π) and down the right side.
            for i in 0...arcSteps {
                let a = 1.5 * .pi + .pi / 2 * CGFloat(i) / CGFloat(arcSteps)
                add(CGPoint(x: w - r + r * cos(a), y: r + r * sin(a)), CGVector(dx: cos(a), dy: sin(a)))
            }
            for y in stride(from: r + 1, through: r + drop, by: 1) { add(CGPoint(x: w, y: y), CGVector(dx: 1, dy: 0)) }
        }
        let cable = Self.cable(points, normals: outward)
        parts.front = [cable]

        // Fade the start, and the end if there's no tail, as if the cable carried on round the back.
        if let first = cable.first, let inner = cable.first(where: { $0.s >= fadeLength }) {
            parts.fades.append(Fade(from: first.p, to: inner.p))
        }
        if !wantsTail, let last = cable.last, let inner = cable.last(where: { $0.s <= last.s - fadeLength }) {
            parts.fades.append(Fade(from: last.p, to: inner.p))
        }

        // Bulbs at uneven spacing. Along the top edge, past the buttons, they mostly alternate
        // between pointing up and hanging down, with the odd repeat so the rhythm isn't perfect.
        let baseLength = (12 * k).rounded()
        let last = (cable.last?.s ?? 0) - (wantsTail ? baseLength : fadeLength + 2)
        var s = fadeLength + 2
        var index = 0
        var pointsOut = true
        var cursor = 0
        while s < last {
            while cursor + 1 < cable.count && cable[cursor].s < s { cursor += 1 }
            let at = cable[cursor]
            let n = (side: noise(index, 1), angle: noise(index, 2), length: noise(index, 3), gap: noise(index, 4))
            if n.side > 0.22 { pointsOut.toggle() }
            let canHang = at.normal.dy < -0.999 && at.p.x > buttonsWidth
            let out = pointsOut || !canHang
            let straight = atan2(at.normal.dy, at.normal.dx) + (out ? 0 : .pi)
            // The socket clips onto the side of the cable the bulb points from.
            let lift = twist.amplitude * 0.6 * (out ? 1 : -1)
            parts.bulbs.append(Bulb(attach: CGPoint(x: at.p.x + at.normal.dx * lift, y: at.p.y + at.normal.dy * lift),
                                    angle: straight + (n.angle - 0.5) * 1.0,
                                    length: baseLength * (0.9 + 0.2 * n.length),
                                    group: index % 3))
            s += baseLength * (1.55 + 0.9 * n.gap)
            index += 1
        }

        if wantsTail, let end = points.last {
            // The cable runs off the top edge just before the corner, heading slightly upward,
            // then curls over and hangs beside the window.
            parts.tail = tail(anchor: end, lead: CGVector(dx: cos(-0.25), dy: sin(-0.25)), k: k,
                              firstGroup: parts.bulbs.count % 3)
        }
        return parts
    }

    // MARK: Shared

    private static func tail(anchor: CGPoint, lead: CGVector, k: CGFloat, firstGroup: Int) -> Tail {
        let segments = 7
        let segmentLength = (6.5 * k).rounded()
        let bulbLength = (11.5 * k).rounded()
        let reach = CGFloat(segments) * segmentLength + bulbLength + 4
        return Tail(anchor: anchor, lead: lead, segments: segments, segmentLength: segmentLength,
                    bulbNodes: [3, 5, 7], firstGroup: firstGroup, bulbLength: bulbLength,
                    rect: CGRect(x: anchor.x - reach, y: anchor.y - reach, width: 2 * reach, height: 2 * reach).integral)
    }

    /// Turns a line of points into cable points, measuring the distance along it. Without `normals`,
    /// each point's normal is the line's own sideways direction (on its upper side, for a cable
    /// heading right).
    static func cable(_ points: [CGPoint], normals: [CGVector]? = nil) -> [CablePoint] {
        var result: [CablePoint] = []
        result.reserveCapacity(points.count)
        var s: CGFloat = 0
        for i in points.indices {
            if i > 0 { s += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
            let normal: CGVector
            if let normals {
                normal = normals[i]
            } else {
                let a = points[max(0, i - 1)], b = points[min(points.count - 1, i + 1)]
                let length = max(hypot(b.x - a.x, b.y - a.y), 0.0001)
                normal = CGVector(dx: (b.y - a.y) / length, dy: -(b.x - a.x) / length)
            }
            result.append(CablePoint(p: points[i], normal: normal, s: s))
        }
        return result
    }

    /// A smooth curve through `points` (Catmull-Rom), sampled about once per point of length.
    static func smoothCurve(through points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var curve: [CGPoint] = []
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let steps = max(2, Int(hypot(p2.x - p1.x, p2.y - p1.y).rounded(.up)))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                func blend(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
                    0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
                }
                curve.append(CGPoint(x: blend(p0.x, p1.x, p2.x, p3.x), y: blend(p0.y, p1.y, p2.y, p3.y)))
            }
        }
        curve.append(points[points.count - 1])
        return curve
    }

    /// A repeatable "random" number in 0...1 for item `i`. `salt` picks an independent stream, so a
    /// bulb's side, angle, length and spacing don't move in lockstep.
    static func noise(_ i: Int, _ salt: Int) -> CGFloat {
        var h = UInt32(truncatingIfNeeded: i &* 374_761_393 &+ salt &* 668_265_263 &+ 1_442_695_041)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return CGFloat(h & 0xFFFF) / 65535
    }
}
