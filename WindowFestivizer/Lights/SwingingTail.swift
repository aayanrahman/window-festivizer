import CoreGraphics

/// The free end of the cable, hanging off a window's top-right corner, as a chain of points.
///
/// It uses Verlet integration, the classic trick for ropes in games: each point remembers where it
/// was on the last step, and the difference *is* its velocity. Each step, every point carries on
/// moving, gravity pulls it down, a little stiffness keeps the wire from folding sharply, and then
/// the links are pulled back to their proper length.
///
/// The first link is held at the window, pointing along `lead`, so the wire leaves the corner
/// heading outward and curls down from there instead of dropping straight beside the window. When
/// the window is dragged, the held end goes with it and the rest lags and swings.
///
/// Points are in global screen coordinates (y down), so the chain stays put in the world while the
/// window moves under it.
struct SwingingTail {
    private(set) var points: [CGPoint]
    private var previous: [CGPoint]
    let segmentLength: CGFloat
    let lead: CGVector
    /// Steps in a row with (almost) no movement. After a while the tail rests and stops ticking.
    private var stillSteps = 0

    /// Points per second², tuned by eye. Higher makes the swing snappier.
    static let gravity: CGFloat = 1800
    /// Fraction of its speed a point keeps each step. Lower settles faster.
    static let damping: CGFloat = 0.97
    /// How much the wire wants to keep going the way it was going: 0 is a limp string, 1 a rod.
    static let stiffness: CGFloat = 0.16

    var isResting: Bool { stillSteps > 30 }

    /// A tail already hanging at rest from `anchor`, so a new window's tail doesn't swing into place.
    init(anchor: CGPoint, lead: CGVector, segments: Int, segmentLength: CGFloat) {
        self.segmentLength = segmentLength
        self.lead = lead
        points = (0...segments).map {
            CGPoint(x: anchor.x + lead.dx * CGFloat($0) * segmentLength, y: anchor.y + lead.dy * CGFloat($0) * segmentLength)
        }
        previous = points
        for _ in 0..<480 { step(anchor: anchor, dt: 1.0 / 60) }
    }

    /// Move on by `dt` seconds, with the held end at `anchor`.
    mutating func step(anchor: CGPoint, dt: CGFloat) {
        let anchorMoved = anchor != points[0]
        // Hold the first link: at the anchor, pointing along the lead.
        let second = CGPoint(x: anchor.x + lead.dx * segmentLength, y: anchor.y + lead.dy * segmentLength)
        points[0] = anchor
        previous[0] = anchor
        points[1] = second
        previous[1] = second

        var fastest: CGFloat = 0
        let fall = SwingingTail.gravity * dt * dt
        for i in 2..<points.count {
            let vx = (points[i].x - previous[i].x) * SwingingTail.damping
            let vy = (points[i].y - previous[i].y) * SwingingTail.damping
            previous[i] = points[i]
            points[i].x += vx
            points[i].y += vy + fall
            fastest = max(fastest, hypot(vx, vy))
        }

        // Stiffness: nudge each point towards where it would be if the wire carried straight on.
        for i in 2..<points.count {
            let ahead = CGPoint(x: 2 * points[i - 1].x - points[i - 2].x, y: 2 * points[i - 1].y - points[i - 2].y)
            points[i].x += (ahead.x - points[i].x) * SwingingTail.stiffness
            points[i].y += (ahead.y - points[i].y) * SwingingTail.stiffness
        }

        // Pull every link back to its proper length. A few passes are enough to look like wire.
        for _ in 0..<6 {
            for i in 2..<points.count {
                let dx = points[i].x - points[i - 1].x
                let dy = points[i].y - points[i - 1].y
                let distance = hypot(dx, dy)
                guard distance > 0.0001 else { continue }
                let stretch = (distance - segmentLength) / distance
                if i == 2 {
                    // Hangs from the held link, which can't move.
                    points[i].x -= dx * stretch
                    points[i].y -= dy * stretch
                } else {
                    points[i - 1].x += dx * stretch * 0.5
                    points[i - 1].y += dy * stretch * 0.5
                    points[i].x -= dx * stretch * 0.5
                    points[i].y -= dy * stretch * 0.5
                }
            }
        }

        stillSteps = (anchorMoved || fastest > 0.05) ? 0 : stillSteps + 1
    }
}
