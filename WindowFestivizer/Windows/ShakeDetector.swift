import CoreGraphics
import Foundation

/// Notices a window being shaken while it's dragged.
///
/// Fed the window's position every time it moves, it works out how fast it's going. A movement
/// faster than `flingSpeed` is a fling; a fling that turns round by more than about 110 degrees
/// from the last one is a shake. So shaking a window back and forth counts every swing, while an
/// ordinary drag (even a fast one, or one that curves) counts nothing.
struct ShakeDetector {
    /// Points per second. Slower than this is just moving the window.
    static let flingSpeed: CGFloat = 700
    /// How sharply a fling has to turn round to count: the cosine of the angle between it and the
    /// last one. -0.35 is about 110 degrees.
    static let turnThreshold: CGFloat = -0.35
    /// A gap longer than this between moves means a new drag.
    static let pause: CFTimeInterval = 0.12

    private var lastMove: (time: CFTimeInterval, origin: CGPoint)?
    private var lastFling: CGVector?

    /// The window has moved to `origin` at `time`. Returns true if that was a shake.
    mutating func moved(to origin: CGPoint, at time: CFTimeInterval) -> Bool {
        defer { lastMove = (time, origin) }
        guard let last = lastMove, time - last.time < Self.pause else {
            lastFling = nil
            return false
        }
        let dt = max(time - last.time, 1.0 / 120)
        let velocity = CGVector(dx: (origin.x - last.origin.x) / dt, dy: (origin.y - last.origin.y) / dt)
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > Self.flingSpeed else { return false }
        defer { lastFling = velocity }
        guard let previous = lastFling else { return false }
        let turn = (velocity.dx * previous.dx + velocity.dy * previous.dy) / (speed * hypot(previous.dx, previous.dy))
        return turn < Self.turnThreshold
    }
}
