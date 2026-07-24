import Cocoa
import Carbon
import GoogleSignIn
import QuartzCore

final class AppDelegate: NSObject, NSApplicationDelegate, PetViewDelegate {
    private var window: PetWindow!
    private var petView: PetView!
    private let resourceLoader = FirebasePetResourceLoader()
    private let resourceService = FirebasePetResourceService()
    private lazy var settingsWindowController = PetSettingsWindowController(
        resourceService: resourceService,
        onUploaded: { [weak self] pet in
            self?.handleUploadedPet(pet)
        },
        onRenamed: { [weak self] pet in
            self?.handleRenamedPet(pet)
        },
        onVisibilityChanged: { [weak self] pet in
            self?.handleRenamedPet(pet)
        },
        onDeleted: { [weak self] pet in
            self?.handleDeletedPet(pet)
        }
    )
    private var availablePets: [PetMetadata] = [.defaultSimba]
    private var activePet: PetMetadata = .defaultSimba
    private var accountState: PetAccountState = .unavailable
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
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        NSApp.setActivationPolicy(.accessory)
        createWindow()
        loadPetMetadata()
        stateMachine.onEnter = { [weak self] action in
            self?.handleEntered(action)
        }
        scheduleNextPause()
        startTimers()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        event: NSAppleEventDescriptor?,
        replyEvent: NSAppleEventDescriptor?
    ) {
        guard
            let urlString = event?
                .paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?
                .stringValue,
            let url = URL(string: urlString)
        else {
            return
        }
        GIDSignIn.sharedInstance.handle(url)
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
            resourceLoader: resourceLoader
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
            requestAction(PetAction(state: .lie, speech: L10n.text("speech.lie.tap")))
        case .lie:
            requestAction(PetAction(state: .sleep, speech: L10n.text("speech.sleep.tap")))
        case .sleep:
            requestAction(PetAction(state: .eat, speech: L10n.text("speech.eat")))
        case .eat:
            requestAction(
                PetAction(
                    state: .cuddle,
                    speech: L10n.text("speech.cuddle"),
                    shakeOnEnter: true
                )
            )
        case .cuddle:
            walkEnabled = true
            requestAction(
                PetAction(
                    state: .walking,
                    speech: L10n.text("speech.walk.resume"),
                    jumpOnEnter: true
                )
            )
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
        let menu = PetMenuBuilder.makeMenu(
            target: self,
            walkEnabled: walkEnabled,
            pets: availablePets,
            activePetId: activePet.id,
            accountState: accountState
        )
        NSMenu.popUpContextMenu(menu, with: event, for: petView)
    }

    private func loadPetMetadata() {
        resourceService.authenticateAndLoadPets(
            onLoaded: { [weak self] selection in
                guard let self else { return }
                self.accountState = selection.accountState
                self.availablePets = selection.pets
                self.applyActivePet(selection.activePet, announcement: nil)
                self.syncSettingsState()
            },
            onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.petView.say(message)
                }
            }
        )
    }

    private func applyActivePet(_ pet: PetMetadata, announcement: String?) {
        activePet = pet
        petView.loadRemoteResources(for: pet)
        if let announcement {
            petView.say(announcement)
        }
    }

    @objc func setNormal() {
        walkEnabled = true
        requestAction(
            PetAction(
                state: .walking,
                speech: L10n.text("speech.normal"),
                jumpOnEnter: true
            )
        )
    }

    @objc func setLie() {
        requestAction(PetAction(state: .lie, speech: L10n.text("speech.lie.action")))
    }

    @objc func setSleep() {
        requestAction(PetAction(state: .sleep, speech: L10n.text("speech.sleep.action")))
    }

    @objc func setEat() {
        requestAction(PetAction(state: .eat, speech: L10n.text("speech.eat")))
    }

    @objc func setCuddle() {
        requestAction(
            PetAction(
                state: .cuddle,
                speech: L10n.text("speech.cuddle"),
                shakeOnEnter: true
            )
        )
    }

    @objc func jumpAction() {
        petView.say(L10n.text("speech.jump"))
        triggerJump()
    }

    @objc func shakeAction() {
        petView.say(L10n.text("speech.shake"))
        triggerShake()
    }

    @objc func toggleWalk() {
        walkEnabled.toggle()
        if walkEnabled {
            requestAction(PetAction(state: .walking, speech: L10n.text("speech.walk.resume")))
        } else {
            requestAction(PetAction(state: .idle, speech: L10n.text("speech.walk.pause")))
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    @objc func showPetSettings() {
        syncSettingsState()
        settingsWindowController.showWindow(nil)
    }

    @objc func signInWithGoogle() {
        resourceService.signInWithGoogle(presenting: window) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.reloadPetsAfterAuthenticationChange(
                        successAnnouncement: L10n.text("auth.sign_in.success")
                    )
                case .failure(let error):
                    self.petView.say(error.localizedDescription)
                }
            }
        }
    }

    @objc func signOut() {
        resourceService.signOut { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.reloadPetsAfterAuthenticationChange(
                        successAnnouncement: L10n.text("auth.sign_out.success")
                    )
                case .failure(let error):
                    self.petView.say(error.localizedDescription)
                }
            }
        }
    }

    @objc func selectPetFromMenu(_ sender: NSMenuItem) {
        guard
            let petId = sender.representedObject as? String,
            let pet = availablePets.first(where: { $0.id == petId })
        else {
            petView.say(L10n.text("error.pet.not_found"))
            return
        }

        guard pet.requiredImagesComplete else {
            petView.say(L10n.text("error.pet.incomplete"))
            return
        }

        resourceService.selectPet(pet) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let selectedPet):
                    self?.applyActivePet(
                        selectedPet,
                        announcement: L10n.format("speech.pet.switched", selectedPet.name)
                    )
                case .failure(let error):
                    NSLog("Unable to save active pet selection: \(error.localizedDescription)")
                    self?.petView.say(L10n.text("error.pet.selection_save"))
                }
            }
        }
    }

    private func handleUploadedPet(_ pet: PetMetadata) {
        upsertAvailablePet(pet)
        applyActivePet(pet, announcement: nil)
        syncSettingsState()

        resourceService.selectPet(pet) { [weak self] result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    NSLog("Unable to save uploaded pet selection: \(error.localizedDescription)")
                    self?.petView.say(L10n.text("error.pet.uploaded_selection_save"))
                }
            }
        }
    }

    private func handleRenamedPet(_ pet: PetMetadata) {
        upsertAvailablePet(pet)
        if activePet.id == pet.id {
            activePet = pet
        }
        syncSettingsState()
    }

    private func handleDeletedPet(_ pet: PetMetadata) {
        availablePets.removeAll { $0.id == pet.id }
        guard activePet.id == pet.id else {
            syncSettingsState()
            return
        }

        let fallback = availablePets.first(where: \.isDefault)
            ?? availablePets.first
            ?? .defaultSimba
        applyActivePet(fallback, announcement: nil)
        syncSettingsState()
        resourceService.selectPet(fallback) { result in
            if case .failure(let error) = result {
                NSLog("Unable to save fallback after deleting pet: \(error.localizedDescription)")
            }
        }
    }

    private func upsertAvailablePet(_ pet: PetMetadata) {
        availablePets.removeAll { $0.id == pet.id }
        availablePets.append(pet)
        availablePets.sort { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func syncSettingsState() {
        settingsWindowController.updateState(
            accountState: accountState,
            pets: availablePets,
            activePetId: activePet.id
        )
    }

    private func reloadPetsAfterAuthenticationChange(successAnnouncement: String) {
        let previousPet = activePet
        resourceService.authenticateAndLoadPets(
            onLoaded: { [weak self] selection in
                guard let self else { return }
                self.accountState = selection.accountState
                self.availablePets = selection.pets

                let retainedPet = selection.pets.first {
                    $0.id == previousPet.id && $0.requiredImagesComplete
                }
                let nextPet = retainedPet ?? selection.activePet
                let lostAccess = retainedPet == nil
                    && !previousPet.isPublic
                    && !previousPet.isDefault
                let announcement = lostAccess
                    ? L10n.format("auth.pet_fallback", nextPet.name)
                    : successAnnouncement
                self.applyActivePet(nextPet, announcement: announcement)
                self.syncSettingsState()

                if nextPet.id != selection.activePet.id {
                    self.resourceService.selectPet(nextPet) { result in
                        if case .failure(let error) = result {
                            NSLog(
                                "Unable to preserve active pet after authentication change: \(error.localizedDescription)"
                            )
                        }
                    }
                }
            },
            onError: { [weak self] message in
                DispatchQueue.main.async {
                    self?.petView.say(message)
                }
            }
        )
    }

    private func requestAction(_ action: PetAction) {
        stateMachine.request(action)
    }
}
