import Cocoa

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
