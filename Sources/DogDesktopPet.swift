import Cocoa
import QuartzCore

enum AnimationTiming {
    static let walkFramesPerSecond: CGFloat = 15
    static let walkFrameNames = [
        "pet-walk-3", "pet-walk-3", "pet-walk-3",
        "pet-walk-2", "pet-walk-2",
        "pet-walk-3", "pet-walk-3", "pet-walk-3",
        "pet-walk-4", "pet-walk-4"
    ]
    static var walkCycleDuration: CGFloat {
        CGFloat(walkFrameNames.count) / walkFramesPerSecond
    }
}

enum PetState: String {
    case idle
    case walking
    case lie
    case sleep
    case eat
    case cuddle

    var cycleDuration: CGFloat {
        switch self {
        case .idle: return 1.2
        case .walking: return AnimationTiming.walkCycleDuration
        case .lie: return 1.0
        case .sleep: return 2.4
        case .eat: return 1.15
        case .cuddle: return 0.9
        }
    }

    var minimumCyclesBeforeSwitch: Int {
        switch self {
        case .idle, .lie: return 1
        case .walking, .sleep, .eat, .cuddle: return 1
        }
    }
}

struct PetAction {
    let state: PetState
    let speech: String?
    let jumpOnEnter: Bool
    let shakeOnEnter: Bool

    init(
        state: PetState,
        speech: String? = nil,
        jumpOnEnter: Bool = false,
        shakeOnEnter: Bool = false
    ) {
        self.state = state
        self.speech = speech
        self.jumpOnEnter = jumpOnEnter
        self.shakeOnEnter = shakeOnEnter
    }
}

struct PetStateSnapshot {
    let current: PetState
    let previous: PetState?
    let transitionProgress: CGFloat
    let cycleProgress: CGFloat
    let elapsed: CGFloat
}

final class PetStateMachine {
    private(set) var currentAction: PetAction
    private var previousState: PetState?
    private var queue: [PetAction] = []
    private var elapsed: CGFloat = 0
    private var cycleElapsed: CGFloat = 0
    private var completedCycles: Int = 0
    private var transitionElapsed: CGFloat
    private let transitionDuration: CGFloat = 0.26

    var onEnter: ((PetAction) -> Void)?

    init(initial: PetAction) {
        currentAction = initial
        transitionElapsed = transitionDuration
    }

    var currentState: PetState {
        currentAction.state
    }

    var queuedOrCurrentState: PetState {
        queue.last?.state ?? currentAction.state
    }

    func request(_ action: PetAction) {
        guard action.state != currentAction.state || !queue.isEmpty else { return }
        guard queue.last?.state != action.state else { return }
        queue.append(action)
    }

    func update(deltaTime: CGFloat) {
        let dt = max(0, min(deltaTime, 0.05))
        elapsed += dt
        cycleElapsed += dt
        transitionElapsed = min(transitionElapsed + dt, transitionDuration)

        let duration = max(0.1, currentAction.state.cycleDuration)
        guard cycleElapsed >= duration else { return }

        let cycles = Int(cycleElapsed / duration)
        completedCycles += max(1, cycles)
        cycleElapsed = cycleElapsed.truncatingRemainder(dividingBy: duration)

        guard
            completedCycles >= currentAction.state.minimumCyclesBeforeSwitch,
            !queue.isEmpty
        else {
            return
        }

        transition(to: queue.removeFirst())
    }

    func snapshot() -> PetStateSnapshot {
        let rawTransition = transitionDuration <= 0 ? 1 : min(1, transitionElapsed / transitionDuration)
        let easedTransition = rawTransition * rawTransition * (3 - 2 * rawTransition)
        let duration = max(0.1, currentAction.state.cycleDuration)
        return PetStateSnapshot(
            current: currentAction.state,
            previous: previousState,
            transitionProgress: easedTransition,
            cycleProgress: cycleElapsed / duration,
            elapsed: elapsed
        )
    }

    private func transition(to action: PetAction) {
        previousState = currentAction.state
        currentAction = action
        elapsed = 0
        cycleElapsed = 0
        completedCycles = 0
        transitionElapsed = 0
        onEnter?(action)
    }
}

final class AnimationController {
    private let framesPerSecond: CGFloat
    private let frameDuration: CGFloat
    private let sequences: [PetState: [String]]
    private var state: PetState = .walking
    private var frameIndex = 0
    private var frameElapsed: CGFloat = 0

    init(framesPerSecond: CGFloat = AnimationTiming.walkFramesPerSecond) {
        self.framesPerSecond = framesPerSecond
        self.frameDuration = 1.0 / framesPerSecond
        self.sequences = [
            .idle: ["pet-idle"],
            .walking: AnimationTiming.walkFrameNames,
            .lie: ["pet-lie"],
            .sleep: ["pet-sleep"],
            .eat: ["pet-eat"],
            .cuddle: ["pet-cuddle"]
        ]
    }

    var currentFrameName: String {
        let frames = currentFrames
        guard !frames.isEmpty else { return "pet-idle" }
        return frames[min(frameIndex, frames.count - 1)]
    }

    var cycleProgress: CGFloat {
        let frames = currentFrames
        guard frames.count > 1 else { return 0 }
        let frameProgress = min(1, frameElapsed / frameDuration)
        return (CGFloat(frameIndex) + frameProgress) / CGFloat(frames.count)
    }

    func firstFrameName(for state: PetState) -> String {
        sequences[state]?.first ?? "pet-idle"
    }

    func update(state newState: PetState, deltaTime: CGFloat) {
        if newState != state {
            state = newState
            frameIndex = 0
            frameElapsed = 0
        }

        let frames = currentFrames
        guard frames.count > 1 else {
            frameIndex = 0
            frameElapsed = 0
            return
        }

        frameElapsed += max(0, min(deltaTime, 0.05))
        while frameElapsed >= frameDuration {
            frameElapsed -= frameDuration
            frameIndex = (frameIndex + 1) % frames.count
        }
    }

    private var currentFrames: [String] {
        sequences[state] ?? ["pet-idle"]
    }
}

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

protocol PetViewDelegate: AnyObject {
    func petWasTapped()
    func petWasDragged(to origin: NSPoint)
    func showPetMenu(for event: NSEvent)
}

final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@main
struct DogDesktopPetMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, PetViewDelegate {
    private var window: PetWindow!
    private var petView: PetView!
    private var updateTimer: Timer?
    private var lastUpdateTime: CFTimeInterval = CACurrentMediaTime()
    private let stateMachine = PetStateMachine(initial: PetAction(state: .walking))
    private let animationController = AnimationController()
    private var positionEaser: PositionEaser?
    private var direction: CGFloat = 1
    private var speed: CGFloat = 10
    private let walkSegmentDistance: CGFloat = 16
    private var walkEnabled = true
    private var baseBottom: CGFloat = 18
    private var jumpElapsed: CGFloat?
    private var shakeElapsed: CGFloat?
    private var pauseRemaining: CGFloat = 0
    private var nextPauseRemaining: CGFloat = 0
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        stateMachine.onEnter = { [weak self] action in
            self?.handleEntered(action)
        }
        scheduleNextPause()
        startTimers()
    }

    private func createWindow() {
        let size = NSSize(width: 290, height: 370)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        baseBottom = screen.minY + 18
        let startX = screen.maxX - size.width - 80
        let startY = baseBottom
        let rect = NSRect(origin: NSPoint(x: startX, y: startY), size: size)

        window = PetWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.delegate = self
        window.contentView = petView
        window.makeKeyAndOrderFront(nil)
        positionEaser = PositionEaser(origin: rect.origin)
    }

    private func startTimers() {
        lastUpdateTime = CACurrentMediaTime()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.updateFrame()
        }
    }

    private func updateFrame() {
        let now = CACurrentMediaTime()
        let deltaTime = CGFloat(max(0, min(now - lastUpdateTime, 0.05)))
        lastUpdateTime = now

        stateMachine.update(deltaTime: deltaTime)
        animationController.update(state: stateMachine.currentState, deltaTime: deltaTime)
        updateEffects(deltaTime: deltaTime)
        updateMovement(deltaTime: deltaTime)
        syncView(now: now, deltaTime: deltaTime)
    }

    private func updateMovement(deltaTime: CGFloat) {
        guard
            let screen = window.screen ?? NSScreen.main,
            let positionEaser
        else {
            return
        }

        let visible = screen.visibleFrame
        let walkingState = stateMachine.currentState == .walking

        if walkingState {
            if pauseRemaining > 0 {
                pauseRemaining = max(0, pauseRemaining - deltaTime)
            } else {
                nextPauseRemaining = max(0, nextPauseRemaining - deltaTime)
                if nextPauseRemaining <= 0 {
                    pauseRemaining = CGFloat.random(in: 1.1...2.8)
                    scheduleNextPause()
                }
            }
        } else {
            pauseRemaining = 0
        }

        let activeWalk = walkingState && pauseRemaining <= 0
        if activeWalk && positionEaser.isComplete {
            let minX = visible.minX + 8
            let maxX = visible.maxX - window.frame.width - 8
            var nextX = positionEaser.current.x + walkSegmentDistance * direction
            if nextX <= minX {
                nextX = minX
                direction = 1
                triggerShake()
                pauseRemaining = 0.9
            } else if nextX >= maxX {
                nextX = maxX
                direction = -1
                triggerShake()
                pauseRemaining = 0.9
            }

            let nextOrigin = NSPoint(x: nextX, y: baseBottom)
            let travel = max(1, abs(nextOrigin.x - positionEaser.current.x))
            positionEaser.move(to: nextOrigin, duration: travel / speed)
        } else if !activeWalk && positionEaser.isComplete {
            positionEaser.move(to: NSPoint(x: positionEaser.current.x, y: baseBottom), duration: 0.18)
        }

        let easedOrigin = positionEaser.update(deltaTime: deltaTime)
        let jumpY = sin(currentJumpProgress() * .pi) * 82

        var frame = window.frame
        frame.origin = NSPoint(x: easedOrigin.x, y: easedOrigin.y + jumpY)
        window.setFrame(frame, display: true)
    }

    private func scheduleNextPause() {
        nextPauseRemaining = CGFloat.random(in: 5.0...11.0)
    }

    private func updateEffects(deltaTime: CGFloat) {
        if let elapsed = jumpElapsed {
            let next = elapsed + deltaTime
            jumpElapsed = next >= 0.72 ? nil : next
        }
        if let elapsed = shakeElapsed {
            let next = elapsed + deltaTime
            shakeElapsed = next >= 0.55 ? nil : next
        }
    }

    private func currentJumpProgress() -> CGFloat {
        guard let jumpElapsed else { return 0 }
        return max(0, min(1, jumpElapsed / 0.72))
    }

    private func currentShakeProgress() -> CGFloat {
        guard let shakeElapsed else { return 0 }
        return max(0, min(1, shakeElapsed / 0.55))
    }

    private func triggerJump() {
        jumpElapsed = 0
    }

    private func triggerShake() {
        shakeElapsed = 0
    }

    private func handleEntered(_ action: PetAction) {
        if let speech = action.speech {
            petView.say(speech)
        }
        if action.jumpOnEnter {
            triggerJump()
        }
        if action.shakeOnEnter {
            triggerShake()
        }
        if action.state == .walking {
            pauseRemaining = 0
            scheduleNextPause()
        }
    }

    private func syncView(now: CFTimeInterval, deltaTime: CGFloat) {
        let snapshot = stateMachine.snapshot()
        petView.now = now
        petView.animationClock += deltaTime
        petView.state = snapshot.current
        petView.previousState = snapshot.previous
        petView.stateTransition = snapshot.transitionProgress
        petView.currentFrameName = animationController.currentFrameName
        petView.stateCycleProgress = animationController.cycleProgress
        petView.jumpProgress = currentJumpProgress()
        petView.shakeProgress = currentShakeProgress()
        petView.walkDirection = direction
        petView.isWalking = snapshot.current == .walking
            && pauseRemaining <= 0
        petView.needsDisplay = true
    }

    func petWasTapped() {
        switch stateMachine.queuedOrCurrentState {
        case .walking, .idle:
            requestAction(PetAction(state: .lie, speech: "我趴好啦。"))
        case .lie:
            requestAction(PetAction(state: .sleep, speech: "困困。"))
        case .sleep:
            requestAction(PetAction(state: .eat, speech: "开饭啦！"))
        case .eat:
            requestAction(PetAction(state: .cuddle, speech: "贴贴时间到。", shakeOnEnter: true))
        case .cuddle:
            walkEnabled = true
            requestAction(PetAction(state: .walking, speech: "继续巡逻。", jumpOnEnter: true))
        }
    }

    func petWasDragged(to origin: NSPoint) {
        positionEaser?.snap(to: origin)
        baseBottom = origin.y
        var frame = window.frame
        frame.origin = origin
        window.setFrame(frame, display: true)
    }

    func showPetMenu(for event: NSEvent) {
        let menu = NSMenu()
        addMenuItem("普通", action: #selector(setNormal), to: menu)
        addMenuItem("趴下", action: #selector(setLie), to: menu)
        addMenuItem("睡觉", action: #selector(setSleep), to: menu)
        addMenuItem("吃饭", action: #selector(setEat), to: menu)
        addMenuItem("撒娇", action: #selector(setCuddle), to: menu)
        menu.addItem(.separator())
        addMenuItem("摇头", action: #selector(shakeAction), to: menu)
        addMenuItem("跳一跳", action: #selector(jumpAction), to: menu)
        let walkTitle = walkEnabled ? "暂停边缘走动" : "继续边缘走动"
        addMenuItem(walkTitle, action: #selector(toggleWalk), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出桌宠", action: #selector(quit), to: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: petView)
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func setNormal() {
        walkEnabled = true
        requestAction(PetAction(state: .walking, speech: "我回来了。", jumpOnEnter: true))
    }

    @objc private func setLie() {
        requestAction(PetAction(state: .lie, speech: "我趴好啦。"))
    }

    @objc private func setSleep() {
        requestAction(PetAction(state: .sleep, speech: "先睡一小会儿。"))
    }

    @objc private func setEat() {
        requestAction(PetAction(state: .eat, speech: "开饭啦！"))
    }

    @objc private func setCuddle() {
        requestAction(PetAction(state: .cuddle, speech: "贴贴时间到。", shakeOnEnter: true))
    }

    @objc private func jumpAction() {
        petView.say("起飞！")
        triggerJump()
    }

    @objc private func shakeAction() {
        petView.say("听到了！")
        triggerShake()
    }

    @objc private func toggleWalk() {
        walkEnabled.toggle()
        if walkEnabled {
            requestAction(PetAction(state: .walking, speech: "继续巡逻。"))
        } else {
            requestAction(PetAction(state: .idle, speech: "我先站会儿。"))
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func requestAction(_ action: PetAction) {
        stateMachine.request(action)
    }
}

final class PetView: NSView {
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
    private var dragStartWindowOrigin: NSPoint = .zero
    private var dragStartScreenPoint: NSPoint = .zero
    private var didDrag = false
    private var speech: String?
    private var speechUntil: CFTimeInterval = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for name in [
            "pet-idle",
            "pet-walk-1",
            "pet-walk-2",
            "pet-walk-3",
            "pet-walk-4",
            "pet-lie",
            "pet-sleep",
            "pet-eat",
            "pet-cuddle"
        ] {
            petImages[name] = NSImage(named: name)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

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
