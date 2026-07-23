import Cocoa

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
