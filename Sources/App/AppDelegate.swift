import Cocoa
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, PetViewDelegate {
    private var window: PetWindow!
    private var petView: PetView!
    private let resourceService = FirebasePetResourceService()
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
        resourceService.configureIfNeeded()
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        resourceService.authenticateAndLoadResources(into: petView)
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

        petView = PetView(
            frame: NSRect(origin: .zero, size: size),
            resourceLoader: FirebasePetResourceLoader()
        )
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
        let menu = PetMenuBuilder.makeMenu(target: self, walkEnabled: walkEnabled)
        NSMenu.popUpContextMenu(menu, with: event, for: petView)
    }

    @objc func setNormal() {
        walkEnabled = true
        requestAction(PetAction(state: .walking, speech: "我回来了。", jumpOnEnter: true))
    }

    @objc func setLie() {
        requestAction(PetAction(state: .lie, speech: "我趴好啦。"))
    }

    @objc func setSleep() {
        requestAction(PetAction(state: .sleep, speech: "先睡一小会儿。"))
    }

    @objc func setEat() {
        requestAction(PetAction(state: .eat, speech: "开饭啦！"))
    }

    @objc func setCuddle() {
        requestAction(PetAction(state: .cuddle, speech: "贴贴时间到。", shakeOnEnter: true))
    }

    @objc func jumpAction() {
        petView.say("起飞！")
        triggerJump()
    }

    @objc func shakeAction() {
        petView.say("听到了！")
        triggerShake()
    }

    @objc func toggleWalk() {
        walkEnabled.toggle()
        if walkEnabled {
            requestAction(PetAction(state: .walking, speech: "继续巡逻。"))
        } else {
            requestAction(PetAction(state: .idle, speech: "我先站会儿。"))
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    private func requestAction(_ action: PetAction) {
        stateMachine.request(action)
    }
}
