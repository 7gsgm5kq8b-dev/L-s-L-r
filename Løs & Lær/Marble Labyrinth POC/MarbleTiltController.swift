import Combine
import CoreMotion
import SwiftUI
import UIKit

final class MarbleTiltController: ObservableObject {
    private enum GameplayCalibration {
        static let lockedOrientation: UIInterfaceOrientation = .landscapeRight
        static let boardXSource = AxisSource.gravityY
        static let boardYSource = AxisSource.gravityX
        static let boardXMultiplier: CGFloat = -1
        static let boardYMultiplier: CGFloat = 1
    }

    private enum AxisSource {
        case gravityX
        case gravityY
    }

    struct Sample {
        var x: CGFloat = 0
        var y: CGFloat = 0
    }

    @Published private(set) var gravityVector: CGVector = .zero
    @Published private(set) var debugSample: Sample = .init()
    @Published private(set) var isUsingFallback = false

    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MarbleTiltController"
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private var filteredVector: CGVector = .zero
    private let smoothingFactor: CGFloat = 0.20
    private let clampLimit: CGFloat = 0.72
    private var activeStartToken = UUID()
    private var hasReceivedSensorSample = false
    private let startupFallbackDelay: TimeInterval = 0.85
    private let preferredReferenceFrames: [CMAttitudeReferenceFrame] = [
        .xArbitraryCorrectedZVertical,
        .xArbitraryZVertical,
        .xMagneticNorthZVertical
    ]

    func start() {
        stop()
        activeStartToken = UUID()
        hasReceivedSensorSample = false
        filteredVector = .zero
        publish(rawX: 0, rawY: 0)

        if startDeviceMotion(using: bestAvailableReferenceFrame()) {
            scheduleAccelerometerFallback(for: activeStartToken)
            return
        }

        if startAccelerometerUpdates() {
            return
        }

        isUsingFallback = true
        publish(rawX: 0, rawY: 0)
    }

    func stop() {
        activeStartToken = UUID()
        hasReceivedSensorSample = false
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
    }

    func refresh() {
        start()
    }

    func updateFallbackTilt(x: Double, y: Double) {
        isUsingFallback = true
        publish(rawX: CGFloat(x), rawY: CGFloat(y))
    }

    func resetFallbackTilt() {
        updateFallbackTilt(x: 0, y: 0)
    }

    private func mapGravityToBoardSpace(_ gravity: CMAcceleration) -> CGVector {
        let boardX = component(for: GameplayCalibration.boardXSource, gravity: gravity) * GameplayCalibration.boardXMultiplier
        let boardY = component(for: GameplayCalibration.boardYSource, gravity: gravity) * GameplayCalibration.boardYMultiplier
        return CGVector(dx: boardX, dy: boardY)
    }

    private func bestAvailableReferenceFrame() -> CMAttitudeReferenceFrame? {
        let availableFrames = CMMotionManager.availableAttitudeReferenceFrames()
        return preferredReferenceFrames.first(where: { availableFrames.contains($0) })
    }

    @discardableResult
    private func startDeviceMotion(using referenceFrame: CMAttitudeReferenceFrame?) -> Bool {
        guard motionManager.isDeviceMotionAvailable, let referenceFrame else {
            return false
        }

        isUsingFallback = false
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(using: referenceFrame, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.hasReceivedSensorSample = true
            let mapped = self.mapGravityToBoardSpace(motion.gravity)
            self.publish(rawX: mapped.dx, rawY: mapped.dy)
        }

        return motionManager.isDeviceMotionActive
    }

    @discardableResult
    private func startAccelerometerUpdates() -> Bool {
        guard motionManager.isAccelerometerAvailable else {
            isUsingFallback = true
            return false
        }

        isUsingFallback = false
        motionManager.accelerometerUpdateInterval = 1.0 / 60.0
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            self.hasReceivedSensorSample = true
            let mapped = self.mapGravityToBoardSpace(data.acceleration)
            self.publish(rawX: mapped.dx, rawY: mapped.dy)
        }

        return motionManager.isAccelerometerActive
    }

    private func scheduleAccelerometerFallback(for startToken: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + startupFallbackDelay) { [weak self] in
            guard let self else { return }
            guard self.activeStartToken == startToken else { return }
            guard !self.hasReceivedSensorSample else { return }

            self.motionManager.stopDeviceMotionUpdates()
            _ = self.startAccelerometerUpdates()
        }
    }

    private func component(for source: AxisSource, gravity: CMAcceleration) -> CGFloat {
        switch source {
        case .gravityX:
            return CGFloat(gravity.x)
        case .gravityY:
            return CGFloat(gravity.y)
        }
    }

    private func publish(rawX: CGFloat, rawY: CGFloat) {
        let clampedX = max(-clampLimit, min(clampLimit, rawX))
        let clampedY = max(-clampLimit, min(clampLimit, rawY))

        filteredVector.dx += (clampedX - filteredVector.dx) * smoothingFactor
        filteredVector.dy += (clampedY - filteredVector.dy) * smoothingFactor

        DispatchQueue.main.async {
            self.gravityVector = self.filteredVector
            self.debugSample = Sample(x: self.filteredVector.dx, y: self.filteredVector.dy)
        }
    }
}
