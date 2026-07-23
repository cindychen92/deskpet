import Cocoa

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
