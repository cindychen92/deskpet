import Cocoa
import QuartzCore

final class PetView: NSView, PetResourcePresenting {
    weak var delegate: PetViewDelegate?
    var state: PetState = .walking
    var previousState: PetState?
    var stateTransition: CGFloat = 1
    var stateCycleProgress: CGFloat = 0
    var currentFrameName: String = "pet-walk-3"
    var animationClock: CGFloat = 0
    var now: CFTimeInterval = CACurrentMediaTime()
    var jumpProgress: CGFloat = 0
    var shakeProgress: CGFloat = 0
    var walkDirection: CGFloat = 1
    var isWalking = true

    private var petImages: [String: NSImage] = [:]
    private let resourceLoader: PetResourceLoading
    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartScreenPoint: NSPoint = .zero
    private var didDrag = false
    private var speech: String?
    private var speechUntil: CFTimeInterval = 0

    init(frame frameRect: NSRect, resourceLoader: PetResourceLoading) {
        self.resourceLoader = resourceLoader
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    func loadRemoteResources(for pet: PetMetadata) {
        resourceLoader.setActivePet(pet)
        petImages.removeAll()
        resourceLoader.loadImages(named: PetResourceManifest.requiredImageNames) { [weak self] name, image in
            self?.petImages[name] = image
            self?.needsDisplay = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard
                let self,
                self.resourceLoader.activePet.id == pet.id,
                self.petImages.isEmpty
            else {
                return
            }
            self.say("宠物图片加载失败，已显示备用图。")
        }
    }

    func say(_ text: String) {
        speech = text
        speechUntil = CACurrentMediaTime() + 2.8
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let frameSet = currentPetFrames(for: state)
        let primaryFrame = petImages[currentFrameName] ?? frameSet.primary
        let image = state == .walking ? primaryFrame : frameSet.primary
        let petRect = spriteRect(for: image)
        drawEffects(around: petRect, behindPet: true)
        if let previousState, previousState != state, stateTransition < 0.999 {
            let previousFrames = currentPetFrames(for: previousState)
            drawPet(
                in: petRect,
                primary: previousFrames.primary,
                secondary: image,
                blend: stateTransition
            )
        } else {
            drawPet(in: petRect, primary: image, secondary: frameSet.secondary, blend: frameSet.blend)
        }
        drawStateOverlay(in: petRect)
        drawEffects(around: petRect, behindPet: false)
        drawSpeechBubble()
    }

    private func currentPetFrames(for state: PetState) -> (primary: NSImage?, secondary: NSImage?, blend: CGFloat) {
        switch state {
        case .idle:
            return (petImages["pet-idle"], nil, 0)
        case .walking:
            return (petImages["pet-walk-3"] ?? petImages["pet-idle"], nil, 0)
        case .lie:
            return (petImages["pet-lie"] ?? petImages["pet-idle"], nil, 0)
        case .sleep:
            return (petImages["pet-sleep"] ?? petImages["pet-lie"] ?? petImages["pet-idle"], nil, 0)
        case .eat:
            return (petImages["pet-eat"] ?? petImages["pet-idle"], nil, 0)
        case .cuddle:
            return (petImages["pet-cuddle"] ?? petImages["pet-idle"], nil, 0)
        }
    }

    private func spriteRect(for image: NSImage?) -> NSRect {
        let topSpace: CGFloat = 72
        let bottomSpace: CGFloat = 16
        let sideSpace: CGFloat = 14
        let available = NSRect(
            x: sideSpace,
            y: bottomSpace,
            width: bounds.width - sideSpace * 2,
            height: bounds.height - topSpace - bottomSpace
        )

        guard let image, image.size.width > 0, image.size.height > 0 else {
            let side = min(available.width, available.height)
            return NSRect(
                x: available.midX - side / 2,
                y: available.minY,
                width: side,
                height: side
            )
        }

        let aspect = image.size.width / image.size.height
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }

        return NSRect(
            x: available.midX - width / 2,
            y: available.minY,
            width: width,
            height: height
        )
    }

    private func drawPet(in rect: NSRect, primary: NSImage?, secondary: NSImage?, blend: CGFloat) {
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.saveGState()

        let stepAngle = stateCycleProgress * .pi * 2
        let bob = state == .walking && isWalking ? abs(sin(stepAngle)) * 2.2 : 0
        let scaleX: CGFloat = walkDirection >= 0 ? 1 : -1
        let shakeAngle = sin(shakeProgress * .pi * 7) * (1 - shakeProgress) * 0.18
        let walkSway = state == .walking && isWalking ? sin(stepAngle) * 0.012 : 0
        let cuddleSway = state == .cuddle ? sin(animationClock * 9.0) * 0.05 : 0
        let squash = jumpProgress > 0 ? 1.0 - sin(jumpProgress * .pi) * 0.06 : 1.0

        ctx.translateBy(x: rect.midX, y: rect.midY + bob)
        ctx.scaleBy(x: scaleX, y: squash)
        ctx.rotate(by: shakeAngle + cuddleSway + walkSway)
        ctx.translateBy(x: -rect.midX, y: -rect.midY)

        if let primary {
            let clampedBlend = max(0, min(1, blend))
            let primaryOpacity = secondary == nil ? 1.0 : 1.0 - clampedBlend
            primary.draw(
                in: rect,
                from: .zero,
                operation: .sourceOver,
                fraction: primaryOpacity
            )
            if let secondary, clampedBlend > 0.001 {
                secondary.draw(
                    in: rect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: clampedBlend
                )
            }
        } else {
            drawFallbackDog(in: rect)
        }

        ctx.restoreGState()
    }

    private func drawStateOverlay(in rect: NSRect) {
        switch state {
        case .walking, .idle:
            break
        case .lie:
            break
        case .sleep:
            drawSleepMoon(near: rect)
        case .eat:
            break
        case .cuddle:
            drawHearts(near: rect)
        }
    }

    private func drawEffects(around rect: NSRect, behindPet: Bool) {
        guard state == .cuddle, !behindPet else { return }
    }

    private func drawSpeechBubble() {
        guard let speech, now < speechUntil else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.19, green: 0.12, blue: 0.09, alpha: 1),
            .paragraphStyle: paragraph
        ]

        let textSize = (speech as NSString).boundingRect(
            with: NSSize(width: bounds.width - 34, height: 60),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size

        let bubble = NSRect(
            x: (bounds.width - min(bounds.width - 24, textSize.width + 34)) / 2,
            y: bounds.height - 52,
            width: min(bounds.width - 24, textSize.width + 34),
            height: max(38, textSize.height + 18)
        )

        NSColor.white.withAlphaComponent(0.94).setFill()
        let path = NSBezierPath(roundedRect: bubble, xRadius: 13, yRadius: 13)
        path.fill()
        NSColor(calibratedWhite: 0.0, alpha: 0.14).setStroke()
        path.lineWidth = 1
        path.stroke()

        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubble.midX - 9, y: bubble.minY + 2))
        tail.line(to: NSPoint(x: bubble.midX + 8, y: bubble.minY + 2))
        tail.line(to: NSPoint(x: bubble.midX - 2, y: bubble.minY - 11))
        tail.close()
        NSColor.white.withAlphaComponent(0.94).setFill()
        tail.fill()

        let textRect = bubble.insetBy(dx: 14, dy: 9)
        (speech as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin], attributes: attrs)
    }

    private func drawSleepMoon(near rect: NSRect) {
        let moonRect = NSRect(x: rect.maxX - 42, y: rect.maxY - 10, width: 26, height: 26)
        NSColor(calibratedRed: 1.0, green: 0.83, blue: 0.35, alpha: 0.9).setFill()
        NSBezierPath(ovalIn: moonRect).fill()
        drawText("Zzz", at: NSPoint(x: moonRect.maxX - 2, y: moonRect.maxY - 2), size: 18, color: NSColor.systemBlue)
    }

    private func drawHearts(near rect: NSRect) {
        for i in 0..<3 {
            let phase = Double(animationClock) * 1.6 + Double(i)
            let x = rect.minX + CGFloat(24 + i * 55) + CGFloat(sin(phase) * 6)
            let y = rect.maxY - CGFloat(12 + i * 10) + CGFloat(sin(phase * 1.7) * 5)
            drawHeart(center: NSPoint(x: x, y: y), scale: 0.75 + CGFloat(i) * 0.1)
        }
    }

    private func drawHeart(center: NSPoint, scale: CGFloat) {
        let path = NSBezierPath()
        let s = 12 * scale
        path.move(to: NSPoint(x: center.x, y: center.y - s * 0.55))
        path.curve(
            to: NSPoint(x: center.x - s, y: center.y + s * 0.2),
            controlPoint1: NSPoint(x: center.x - s * 0.85, y: center.y - s * 0.05),
            controlPoint2: NSPoint(x: center.x - s * 1.15, y: center.y + s * 0.45)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y + s * 0.55),
            controlPoint1: NSPoint(x: center.x - s * 0.9, y: center.y + s * 0.95),
            controlPoint2: NSPoint(x: center.x - s * 0.25, y: center.y + s * 0.95)
        )
        path.curve(
            to: NSPoint(x: center.x + s, y: center.y + s * 0.2),
            controlPoint1: NSPoint(x: center.x + s * 0.25, y: center.y + s * 0.95),
            controlPoint2: NSPoint(x: center.x + s * 0.9, y: center.y + s * 0.95)
        )
        path.curve(
            to: NSPoint(x: center.x, y: center.y - s * 0.55),
            controlPoint1: NSPoint(x: center.x + s * 1.15, y: center.y + s * 0.45),
            controlPoint2: NSPoint(x: center.x + s * 0.85, y: center.y - s * 0.05)
        )
        path.close()
        NSColor.systemPink.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    private func drawFallbackDog(in rect: NSRect) {
        let body = NSRect(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.06, width: rect.width * 0.50, height: rect.height * 0.56)
        let head = NSRect(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.48, width: rect.width * 0.56, height: rect.height * 0.36)
        NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.86, alpha: 1).setFill()
        NSBezierPath(ovalIn: body).fill()
        NSBezierPath(ovalIn: head).fill()
        NSColor(calibratedRed: 0.69, green: 0.40, blue: 0.20, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: head.minX - 20, y: head.minY - 8, width: 48, height: 92)).fill()
        NSBezierPath(ovalIn: NSRect(x: head.maxX - 28, y: head.minY - 8, width: 48, height: 92)).fill()
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: head.midX - 10, y: head.midY - 6, width: 20, height: 14)).fill()
    }

    private func drawText(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .bold),
            .foregroundColor: color
        ]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragStartWindowOrigin = window.frame.origin
        dragStartScreenPoint = NSEvent.mouseLocation
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let delta = NSPoint(x: point.x - dragStartScreenPoint.x, y: point.y - dragStartScreenPoint.y)
        if abs(delta.x) + abs(delta.y) > 4 {
            didDrag = true
        }
        delegate?.petWasDragged(to: NSPoint(x: dragStartWindowOrigin.x + delta.x, y: dragStartWindowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag {
            delegate?.petWasTapped()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        delegate?.showPetMenu(for: event)
    }
}
