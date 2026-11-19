import CoreGraphics

/// The short string of lights hanging off a window's right corner, as a chain of points.
///
/// It uses Verlet integration, the classic trick for ropes in games: each point remembers where it
/// was on the last step, and the difference *is* its velocity. Each step, every point carries on
/// moving, gravity pulls it down, and then the links are pulled back to their proper length. When
/// the window is dragged, the top point goes with it and the rest of the chain lags and swings.
///
/// Points are in global screen coordinates (y down), so the chain stays put in the world while
/// the window moves under it.
struct SwingingTail {
    private(set) var points: [CGPoint]
    private var previous: [CGPoint]
    let segmentLength: CGFloat
    /// Steps in a row with (almost) no movement. After a while the tail rests and stops ticking.
    private var stillSteps = 0

    /// Points per second², tuned by eye. Higher makes the swing snappier.
    static let gravity: CGFloat = 2200
    /// Fraction of its speed a point keeps each step. Lower settles faster.
    static let damping: CGFloat = 0.975

    var isResting: Bool { stillSteps > 30 }

    /// A tail hanging straight down from `anchor`.
    init(anchor: CGPoint, segments: Int, segmentLength: CGFloat) {
        self.segmentLength = segmentLength
        points = (0...segments).map { CGPoint(x: anchor.x, y: anchor.y + CGFloat($0) * segmentLength) }
        previous = points
    }

    /// Move on by `dt` seconds, with the top of the tail at `anchor`.
    mutating func step(anchor: CGPoint, dt: CGFloat) {
        let anchorMoved = anchor != points[0]
        points[0] = anchor
        previous[0] = anchor

        var fastest: CGFloat = 0
        let fall = SwingingTail.gravity * dt * dt
        for i in 1..<points.count {
            let vx = (points[i].x - previous[i].x) * SwingingTail.damping
            let vy = (points[i].y - previous[i].y) * SwingingTail.damping
            previous[i] = points[i]
            points[i].x += vx
            points[i].y += vy + fall
            fastest = max(fastest, hypot(vx, vy))
        }

        // Pull every link back to its proper length. A few passes are enough to look like a rope.
        for _ in 0..<6 {
            for i in 1..<points.count {
                let dx = points[i].x - points[i - 1].x
                let dy = points[i].y - points[i - 1].y
                let distance = hypot(dx, dy)
                guard distance > 0.0001 else { continue }
                let stretch = (distance - segmentLength) / distance
                if i == 1 {
                    // The first link hangs from the anchor, which can't move.
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
