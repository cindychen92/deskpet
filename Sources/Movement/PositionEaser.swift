import Cocoa

final class PositionEaser {
    private(set) var current: NSPoint
    private var start: NSPoint
    private var target: NSPoint
    private var elapsed: CGFloat = 0
    private var duration: CGFloat = 0.35

    init(origin: NSPoint) {
        current = origin
        start = origin
        target = origin
        elapsed = duration
    }

    var isComplete: Bool {
        elapsed >= duration
    }

    func snap(to point: NSPoint) {
        current = point
        start = point
        target = point
        elapsed = duration
    }

    func move(to point: NSPoint, duration: CGFloat) {
        guard distance(from: target, to: point) > 0.5 else { return }
        start = current
        target = point
        elapsed = 0
        self.duration = max(0.12, duration)
    }

    func update(deltaTime: CGFloat) -> NSPoint {
        elapsed = min(duration, elapsed + max(0, min(deltaTime, 0.05)))
        let raw = duration <= 0 ? 1 : elapsed / duration
        let eased = easeInOut(raw)
        current = NSPoint(
            x: lerp(start.x, target.x, eased),
            y: lerp(start.y, target.y, eased)
        )
        return current
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ amount: CGFloat) -> CGFloat {
        start + (end - start) * max(0, min(1, amount))
    }

    private func easeInOut(_ t: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, t))
        return clamped * clamped * (3 - 2 * clamped)
    }

    private func distance(from a: NSPoint, to b: NSPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}
