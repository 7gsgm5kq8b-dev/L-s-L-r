import SpriteKit
import SwiftUI

struct MarbleBoardConfiguration: Identifiable, Equatable {
    let id: String
    let boardSeed: UInt64
    let boardSize: CGSize
    let borderThickness: CGFloat
    let marbleRadius: CGFloat
    let holeRadius: CGFloat
    let startRect: CGRect
    let startPosition: CGPoint
    let goalRect: CGRect
    let wallRects: [CGRect]
    let holes: [CGPoint]

    static func generated(seed: UInt64) -> MarbleBoardConfiguration {
        for attempt in 0..<24 {
            if let board = makeCandidate(seed: seed, attempt: attempt) {
                return board
            }
        }

        let fallback = fallbackBoard(seed: seed)
        return fallback
    }

    func hasSameLayout(as other: MarbleBoardConfiguration) -> Bool {
        boardSize == other.boardSize &&
        borderThickness == other.borderThickness &&
        marbleRadius == other.marbleRadius &&
        holeRadius == other.holeRadius &&
        startRect == other.startRect &&
        startPosition == other.startPosition &&
        goalRect == other.goalRect &&
        wallRects == other.wallRects &&
        holes == other.holes
    }

    private static func makeCandidate(seed: UInt64, attempt: Int) -> MarbleBoardConfiguration? {
        var random = SeededGenerator(seed: mixedSeed(base: seed, salt: UInt64(attempt + 1)))

        let boardSize = CGSize(width: 1280, height: 860)
        let borderThickness: CGFloat = 42
        let marbleRadius: CGFloat = 28
        let holeRadius: CGFloat = 24
        let boardRect = CGRect(origin: .zero, size: boardSize)
        let innerRect = boardRect.insetBy(dx: borderThickness, dy: borderThickness)

        let laneCount = 4
        let barrierThickness: CGFloat = 52
        let laneHeight = (innerRect.height - CGFloat(laneCount - 1) * barrierThickness) / CGFloat(laneCount)
        guard laneHeight >= 128 else { return nil }

        let laneRects = (0..<laneCount).map { index in
            CGRect(
                x: innerRect.minX,
                y: innerRect.minY + CGFloat(index) * (laneHeight + barrierThickness),
                width: innerRect.width,
                height: laneHeight
            )
        }

        let startRect = CGRect(x: innerRect.minX + 34, y: laneRects[0].midY - 56, width: 142, height: 112)
        let startPosition = CGPoint(x: startRect.midX, y: startRect.midY)
        let goalRect = CGRect(x: innerRect.maxX - 176, y: laneRects[laneCount - 1].midY - 56, width: 142, height: 112)

        let gapWidth: CGFloat = 244
        var connectorCenters: [CGFloat] = []
        var wallRects: [CGRect] = []

        for index in 0..<(laneCount - 1) {
            let preferRight = index.isMultiple(of: 2)
            let baseCenter = preferRight ? innerRect.maxX - 250 : innerRect.minX + 250
            let jitter = random.nextCGFloat(in: -68...68)
            let gapCenter = max(innerRect.minX + 190, min(innerRect.maxX - 190, baseCenter + jitter))
            connectorCenters.append(gapCenter)

            let gapMinX = gapCenter - gapWidth / 2
            let gapMaxX = gapCenter + gapWidth / 2
            let barrierY = laneRects[index].maxY

            if gapMinX - innerRect.minX > 44 {
                wallRects.append(CGRect(x: innerRect.minX, y: barrierY, width: gapMinX - innerRect.minX, height: barrierThickness))
            }

            if innerRect.maxX - gapMaxX > 44 {
                wallRects.append(CGRect(x: gapMaxX, y: barrierY, width: innerRect.maxX - gapMaxX, height: barrierThickness))
            }
        }

        let safeRoute = guaranteedRouteRects(
            laneRects: laneRects,
            connectorCenters: connectorCenters,
            startRect: startRect,
            goalRect: goalRect,
            safeLaneHeight: min(124, laneHeight - 14),
            connectorWidth: gapWidth - 24
        )

        addStubWalls(
            random: &random,
            into: &wallRects,
            laneRects: laneRects,
            innerRect: innerRect,
            startRect: startRect,
            goalRect: goalRect,
            safeRoute: safeRoute
        )

        let holes = makeHoles(
            random: &random,
            holeRadius: holeRadius,
            marbleRadius: marbleRadius,
            laneRects: laneRects,
            connectorCenters: connectorCenters,
            innerRect: innerRect,
            startPosition: startPosition,
            goalRect: goalRect,
            wallRects: wallRects,
            safeRoute: safeRoute
        )

        let board = MarbleBoardConfiguration(
            id: "board_seed_\(seed)",
            boardSeed: seed,
            boardSize: boardSize,
            borderThickness: borderThickness,
            marbleRadius: marbleRadius,
            holeRadius: holeRadius,
            startRect: startRect,
            startPosition: startPosition,
            goalRect: goalRect,
            wallRects: wallRects,
            holes: holes
        )

        return isValid(
            board: board,
            safeRoute: safeRoute,
            innerRect: innerRect,
            laneRects: laneRects,
            connectorCenters: connectorCenters
        ) ? board : nil
    }

    private static func fallbackBoard(seed: UInt64) -> MarbleBoardConfiguration {
        var random = SeededGenerator(seed: mixedSeed(base: seed, salt: 0xFABBAC11))
        let boardSize = CGSize(width: 1280, height: 860)
        let borderThickness: CGFloat = 42
        let marbleRadius: CGFloat = 28
        let holeRadius: CGFloat = 24
        let boardRect = CGRect(origin: .zero, size: boardSize)
        let innerRect = boardRect.insetBy(dx: borderThickness, dy: borderThickness)
        let barrierThickness: CGFloat = 52
        let laneHeight = (innerRect.height - 3 * barrierThickness) / 4
        let laneRects = (0..<4).map { index in
            CGRect(
                x: innerRect.minX,
                y: innerRect.minY + CGFloat(index) * (laneHeight + barrierThickness),
                width: innerRect.width,
                height: laneHeight
            )
        }

        let startRect = CGRect(x: innerRect.minX + 34, y: laneRects[0].midY - 56, width: 142, height: 112)
        let goalRect = CGRect(x: innerRect.maxX - 176, y: laneRects[3].midY - 56, width: 142, height: 112)
        let baseGapCenters: [CGFloat] = [innerRect.maxX - 248, innerRect.minX + 252, innerRect.maxX - 248]
        let gapWidth: CGFloat = 244
        let gapCenters = baseGapCenters.map { center in
            let jitter = random.nextCGFloat(in: -44...44)
            return max(innerRect.minX + 190, min(innerRect.maxX - 190, center + jitter))
        }
        var wallRects: [CGRect] = []

        for index in 0..<3 {
            let gapCenter = gapCenters[index]
            let gapMinX = gapCenter - gapWidth / 2
            let gapMaxX = gapCenter + gapWidth / 2
            let barrierY = laneRects[index].maxY
            wallRects.append(CGRect(x: innerRect.minX, y: barrierY, width: gapMinX - innerRect.minX, height: barrierThickness))
            wallRects.append(CGRect(x: gapMaxX, y: barrierY, width: innerRect.maxX - gapMaxX, height: barrierThickness))
        }

        let hole1 = CGPoint(
            x: min(innerRect.maxX - 176, max(innerRect.minX + 176, innerRect.midX - 124 + random.nextCGFloat(in: -44...44))),
            y: min(laneRects[1].minY + 58, max(laneRects[1].minY + 42, laneRects[1].minY + 50 + random.nextCGFloat(in: -8...8)))
        )
        let hole2 = CGPoint(
            x: min(innerRect.maxX - 176, max(innerRect.minX + 176, innerRect.midX + 124 + random.nextCGFloat(in: -44...44))),
            y: max(laneRects[2].maxY - 58, min(laneRects[2].maxY - 42, laneRects[2].maxY - 50 + random.nextCGFloat(in: -8...8)))
        )

        return MarbleBoardConfiguration(
            id: "board_seed_\(seed)",
            boardSeed: seed,
            boardSize: boardSize,
            borderThickness: borderThickness,
            marbleRadius: marbleRadius,
            holeRadius: holeRadius,
            startRect: startRect,
            startPosition: CGPoint(x: startRect.midX, y: startRect.midY),
            goalRect: goalRect,
            wallRects: wallRects,
            holes: [hole1, hole2]
        )
    }

    private static func guaranteedRouteRects(
        laneRects: [CGRect],
        connectorCenters: [CGFloat],
        startRect: CGRect,
        goalRect: CGRect,
        safeLaneHeight: CGFloat,
        connectorWidth: CGFloat
    ) -> [CGRect] {
        var route: [CGRect] = []

        for laneIndex in laneRects.indices {
            let lane = laneRects[laneIndex]
            let startX = laneIndex == 0 ? startRect.maxX - 12 : connectorCenters[laneIndex - 1]
            let endX = laneIndex == laneRects.count - 1 ? goalRect.minX + 12 : connectorCenters[laneIndex]
            let minX = min(startX, endX)
            let maxX = max(startX, endX)
            route.append(
                CGRect(
                    x: minX - 26,
                    y: lane.midY - safeLaneHeight / 2,
                    width: max(1, maxX - minX) + 52,
                    height: safeLaneHeight
                )
            )

            if laneIndex < laneRects.count - 1 {
                let lowerLane = laneRects[laneIndex]
                let upperLane = laneRects[laneIndex + 1]
                route.append(
                    CGRect(
                        x: connectorCenters[laneIndex] - connectorWidth / 2,
                        y: lowerLane.midY - safeLaneHeight * 0.18,
                        width: connectorWidth,
                        height: (upperLane.midY - lowerLane.midY) + safeLaneHeight * 0.36
                    )
                )
            }
        }

        route.append(startRect.insetBy(dx: -24, dy: -18))
        route.append(goalRect.insetBy(dx: -24, dy: -18))
        return route
    }

    private static func addStubWalls(
        random: inout SeededGenerator,
        into wallRects: inout [CGRect],
        laneRects: [CGRect],
        innerRect: CGRect,
        startRect: CGRect,
        goalRect: CGRect,
        safeRoute: [CGRect]
    ) {
        for laneIndex in laneRects.indices {
            let lane = laneRects[laneIndex]
            let stubTargetCount = laneIndex == 0 || laneIndex == laneRects.count - 1 ? 1 : random.nextInt(in: 0...1)

            for _ in 0..<stubTargetCount {
                for _ in 0..<20 {
                    let stubWidth: CGFloat = 34
                    let stubHeight = random.nextCGFloat(in: lane.height * 0.26...lane.height * 0.42)
                    let x = random.nextCGFloat(in: innerRect.minX + 220...innerRect.maxX - 258)
                    let attachFromBottom = random.nextBool()
                    let candidate = CGRect(
                        x: x,
                        y: attachFromBottom ? lane.minY : lane.maxY - stubHeight,
                        width: stubWidth,
                        height: stubHeight
                    )

                    guard !candidate.intersects(startRect.insetBy(dx: -90, dy: -34)) else { continue }
                    guard !candidate.intersects(goalRect.insetBy(dx: -90, dy: -34)) else { continue }
                    guard safeRoute.allSatisfy({ !$0.intersects(candidate.insetBy(dx: -30, dy: -18)) }) else { continue }
                    guard wallRects.allSatisfy({ !$0.intersects(candidate.insetBy(dx: -20, dy: -20)) }) else { continue }

                    wallRects.append(candidate)
                    break
                }
            }
        }
    }

    private static func makeHoles(
        random: inout SeededGenerator,
        holeRadius: CGFloat,
        marbleRadius: CGFloat,
        laneRects: [CGRect],
        connectorCenters: [CGFloat],
        innerRect: CGRect,
        startPosition: CGPoint,
        goalRect: CGRect,
        wallRects: [CGRect],
        safeRoute: [CGRect]
    ) -> [CGPoint] {
        let goalPoint = CGPoint(x: goalRect.midX, y: goalRect.midY)
        let desiredCount = random.nextInt(in: 1...2)
        var holes: [CGPoint] = []

        for _ in 0..<desiredCount {
            for _ in 0..<48 {
                let lane = laneRects[random.nextInt(in: 1...(laneRects.count - 1))]
                let laneMinY = lane.minY + holeRadius + 14
                let laneMaxY = lane.maxY - holeRadius - 14
                guard laneMaxY > laneMinY else { continue }

                let edgeBandDepth = min(26, max(18, (laneMaxY - laneMinY) * 0.34))
                let placeUpperBand = random.nextBool()
                let yRange = placeUpperBand
                    ? laneMinY...(laneMinY + edgeBandDepth)
                    : (laneMaxY - edgeBandDepth)...laneMaxY
                let candidate = CGPoint(
                    x: random.nextCGFloat(in: innerRect.minX + 140...innerRect.maxX - 140),
                    y: random.nextCGFloat(in: yRange)
                )

                guard distance(candidate, startPosition) > 250 else { continue }
                guard distance(candidate, goalPoint) > 182 else { continue }
                guard holes.allSatisfy({ distance($0, candidate) > 220 }) else { continue }
                guard connectorCenters.allSatisfy({ abs($0 - candidate.x) > holeRadius + marbleRadius + 44 }) else { continue }
                guard holeLeavesForgivingPassage(
                    for: candidate,
                    in: laneRects,
                    holeRadius: holeRadius,
                    marbleRadius: marbleRadius,
                    minClearance: 14
                ) else { continue }
                guard safeRoute.allSatisfy({ !expanded($0, by: holeRadius + 44).contains(candidate) }) else { continue }
                guard wallRects.allSatisfy({ !expanded($0, by: holeRadius + 30).contains(candidate) }) else { continue }

                holes.append(candidate)
                break
            }
        }

        return holes
    }

    private static func isValid(
        board: MarbleBoardConfiguration,
        safeRoute: [CGRect],
        innerRect: CGRect,
        laneRects: [CGRect],
        connectorCenters: [CGFloat]
    ) -> Bool {
        guard innerRect.contains(board.startPosition) else { return false }
        guard innerRect.contains(CGPoint(x: board.goalRect.midX, y: board.goalRect.midY)) else { return false }
        guard board.wallRects.allSatisfy({ innerRect.contains($0) }) else { return false }
        guard safeRoute.allSatisfy({ innerRect.contains($0) }) else { return false }
        guard board.wallRects.allSatisfy({ !$0.intersects(board.startRect.insetBy(dx: -18, dy: -18)) }) else { return false }
        guard board.wallRects.allSatisfy({ !$0.intersects(board.goalRect.insetBy(dx: -18, dy: -18)) }) else { return false }
        guard board.wallRects.allSatisfy({ wall in safeRoute.allSatisfy { !wall.intersects($0.insetBy(dx: -14, dy: -14)) } }) else { return false }
        guard !board.holes.isEmpty else { return false }
        guard board.holes.allSatisfy({ innerRect.insetBy(dx: board.holeRadius + 10, dy: board.holeRadius + 10).contains($0) }) else { return false }
        guard board.holes.allSatisfy({ distance($0, board.startPosition) > 250 }) else { return false }
        guard board.holes.allSatisfy({ hole in safeRoute.allSatisfy { !expanded($0, by: board.holeRadius + 36).contains(hole) } }) else { return false }
        guard board.holes.allSatisfy({ hole in
            laneRects.dropFirst().contains(where: { $0.insetBy(dx: 0, dy: -1).contains(hole) })
        }) else { return false }
        guard board.holes.allSatisfy({ hole in
            connectorCenters.allSatisfy { abs($0 - hole.x) > board.holeRadius + board.marbleRadius + 34 }
        }) else { return false }
        guard board.holes.allSatisfy({
            holeLeavesForgivingPassage(
                for: $0,
                in: laneRects,
                holeRadius: board.holeRadius,
                marbleRadius: board.marbleRadius,
                minClearance: 14
            )
        }) else { return false }

        for index in board.holes.indices {
            for otherIndex in board.holes.indices where otherIndex > index {
                guard distance(board.holes[index], board.holes[otherIndex]) > 192 else { return false }
            }
        }

        return true
    }

    private static func expanded(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        rect.insetBy(dx: -amount, dy: -amount)
    }

    private static func holeLeavesForgivingPassage(
        for hole: CGPoint,
        in laneRects: [CGRect],
        holeRadius: CGFloat,
        marbleRadius: CGFloat,
        minClearance: CGFloat
    ) -> Bool {
        guard let lane = laneRects.first(where: { $0.insetBy(dx: 0, dy: -1).contains(hole) }) else { return false }
        let upperGap = (lane.maxY - marbleRadius) - (hole.y + holeRadius + marbleRadius)
        let lowerGap = (hole.y - holeRadius - marbleRadius) - (lane.minY + marbleRadius)
        return max(upperGap, lowerGap) >= minClearance
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private static func mixedSeed(base: UInt64, salt: UInt64) -> UInt64 {
        var value = base &+ 0x9E3779B97F4A7C15 &+ salt &* 0xBF58476D1CE4E5B9
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value &*= 0x94D049BB133111EB
        value ^= value >> 31
        return value
    }

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0xA5A5A5A5A5A5A5A5 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func nextBool() -> Bool {
            next() & 1 == 0
        }

        mutating func nextInt(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % span)
        }

        mutating func nextCGFloat(in range: ClosedRange<CGFloat>) -> CGFloat {
            let upper = Double(UInt64.max)
            let unit = CGFloat(Double(next()) / upper)
            return range.lowerBound + (range.upperBound - range.lowerBound) * unit
        }
    }
}

final class MarbleLabyrinthScene: SKScene, SKPhysicsContactDelegate {
    enum Event {
        case started
        case manualReset
        case failed
        case success
    }

    private enum GameplayState {
        case ready
        case playing
        case failed
        case success
    }

    private struct PhysicsCategory {
        static let marble: UInt32 = 1 << 0
        static let wall: UInt32 = 1 << 1
        static let goal: UInt32 = 1 << 2
        static let hole: UInt32 = 1 << 3
    }

    private enum Tuning {
        static let gravityStrength: CGFloat = 19.5
        static let maxSpeed: CGFloat = 610
        static let marbleDamping: CGFloat = 1.45
        static let marbleFriction: CGFloat = 0.60
        static let marbleRestitution: CGFloat = 0.10
        static let wallFriction: CGFloat = 0.82
    }

    private let board: MarbleBoardConfiguration
    private unowned let motionController: MarbleTiltController
    var eventHandler: ((Event) -> Void)?

    private var marbleNode: SKShapeNode?
    private var gameplayState: GameplayState = .ready
    private var isResolvingContact = false

    var boardSeed: UInt64 {
        board.boardSeed
    }

    init(board: MarbleBoardConfiguration, motionController: MarbleTiltController) {
        self.board = board
        self.motionController = motionController
        super.init(size: board.boardSize)
        scaleMode = .aspectFit
        backgroundColor = UIColor(red: 0.94, green: 0.90, blue: 0.82, alpha: 1.0)
        physicsWorld.contactDelegate = self
        physicsWorld.gravity = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        guard children.isEmpty else {
            return
        }
        buildBoard()
        createMarble()
        beginRound(notify: true)
    }

    override func update(_ currentTime: TimeInterval) {
        guard gameplayState == .playing else {
            physicsWorld.gravity = .zero
            return
        }

        let gravity = motionController.gravityVector
        physicsWorld.gravity = CGVector(dx: gravity.dx * Tuning.gravityStrength, dy: gravity.dy * Tuning.gravityStrength)
        capMarbleVelocity()
    }

    func resetMarble(manual: Bool) {
        guard let marbleNode else { return }
        isResolvingContact = false
        marbleNode.removeAllActions()
        marbleNode.alpha = 1
        marbleNode.setScale(1)
        marbleNode.isHidden = false
        marbleNode.position = board.startPosition
        marbleNode.zRotation = 0
        marbleNode.physicsBody?.isDynamic = true
        marbleNode.physicsBody?.velocity = .zero
        marbleNode.physicsBody?.angularVelocity = 0
        marbleNode.physicsBody?.collisionBitMask = PhysicsCategory.wall
        marbleNode.physicsBody?.contactTestBitMask = PhysicsCategory.goal | PhysicsCategory.hole
        gameplayState = .playing
        if manual {
            eventHandler?(.manualReset)
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let combined = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask

        if combined == (PhysicsCategory.marble | PhysicsCategory.goal) {
            handleGoalReached()
        } else if combined == (PhysicsCategory.marble | PhysicsCategory.hole) {
            handleHoleReached()
        }
    }

    private func beginRound(notify: Bool) {
        gameplayState = .playing
        marbleNode?.physicsBody?.isDynamic = true
        marbleNode?.physicsBody?.velocity = .zero
        marbleNode?.physicsBody?.angularVelocity = 0
        marbleNode?.position = board.startPosition
        if notify {
            eventHandler?(.started)
        }
    }

    private func buildBoard() {
        let boardRect = CGRect(origin: .zero, size: board.boardSize)
        let innerRect = boardRect.insetBy(dx: board.borderThickness, dy: board.borderThickness)

        let tray = SKShapeNode(rect: boardRect, cornerRadius: 46)
        tray.fillColor = UIColor(red: 0.77, green: 0.61, blue: 0.40, alpha: 1.0)
        tray.strokeColor = UIColor(red: 0.56, green: 0.40, blue: 0.23, alpha: 1.0)
        tray.lineWidth = 8
        tray.position = .zero
        tray.zPosition = 0
        addChild(tray)

        let playfield = SKShapeNode(rect: innerRect, cornerRadius: 34)
        playfield.fillColor = UIColor(red: 0.97, green: 0.93, blue: 0.84, alpha: 1.0)
        playfield.strokeColor = UIColor(red: 0.82, green: 0.74, blue: 0.58, alpha: 1.0)
        playfield.lineWidth = 4
        playfield.zPosition = 1
        addChild(playfield)

        let edgeNode = SKNode()
        edgeNode.physicsBody = SKPhysicsBody(edgeLoopFrom: innerRect)
        edgeNode.physicsBody?.friction = Tuning.wallFriction
        edgeNode.physicsBody?.categoryBitMask = PhysicsCategory.wall
        edgeNode.physicsBody?.contactTestBitMask = 0
        edgeNode.physicsBody?.collisionBitMask = PhysicsCategory.marble
        addChild(edgeNode)

        let startZone = SKShapeNode(rectOf: board.startRect.size, cornerRadius: 24)
        startZone.fillColor = UIColor(red: 0.72, green: 0.88, blue: 0.72, alpha: 0.95)
        startZone.strokeColor = UIColor(red: 0.42, green: 0.67, blue: 0.44, alpha: 1.0)
        startZone.lineWidth = 4
        startZone.position = CGPoint(x: board.startRect.midX, y: board.startRect.midY)
        startZone.zPosition = 1.5
        addChild(startZone)
        addLabel(text: "Start", at: CGPoint(x: board.startRect.midX, y: board.startRect.midY - 8), zPosition: 2)

        let goalNode = SKShapeNode(rectOf: board.goalRect.size, cornerRadius: 26)
        goalNode.fillColor = UIColor(red: 0.98, green: 0.83, blue: 0.46, alpha: 0.95)
        goalNode.strokeColor = UIColor(red: 0.87, green: 0.58, blue: 0.16, alpha: 1.0)
        goalNode.lineWidth = 4
        goalNode.zPosition = 1.5
        goalNode.physicsBody = SKPhysicsBody(rectangleOf: board.goalRect.size)
        goalNode.physicsBody?.isDynamic = false
        goalNode.physicsBody?.categoryBitMask = PhysicsCategory.goal
        goalNode.physicsBody?.collisionBitMask = 0
        goalNode.physicsBody?.contactTestBitMask = PhysicsCategory.marble
        goalNode.position = CGPoint(x: board.goalRect.midX, y: board.goalRect.midY)
        addChild(goalNode)
        addLabel(text: "Mål", at: CGPoint(x: board.goalRect.midX, y: board.goalRect.midY - 10), zPosition: 2)

        for wallRect in board.wallRects {
            let wall = SKShapeNode(rectOf: wallRect.size, cornerRadius: 18)
            wall.fillColor = UIColor(red: 0.82, green: 0.68, blue: 0.48, alpha: 1.0)
            wall.strokeColor = UIColor(red: 0.58, green: 0.43, blue: 0.26, alpha: 1.0)
            wall.lineWidth = 3
            wall.zPosition = 2
            wall.physicsBody = SKPhysicsBody(rectangleOf: wallRect.size)
            wall.physicsBody?.isDynamic = false
            wall.physicsBody?.friction = Tuning.wallFriction
            wall.physicsBody?.categoryBitMask = PhysicsCategory.wall
            wall.physicsBody?.collisionBitMask = PhysicsCategory.marble
            wall.physicsBody?.contactTestBitMask = 0
            wall.position = CGPoint(x: wallRect.midX, y: wallRect.midY)
            addChild(wall)
        }

        for holeCenter in board.holes {
            let rim = SKShapeNode(circleOfRadius: board.holeRadius)
            rim.fillColor = UIColor(red: 0.25, green: 0.16, blue: 0.10, alpha: 1.0)
            rim.strokeColor = UIColor(red: 0.48, green: 0.32, blue: 0.19, alpha: 1.0)
            rim.lineWidth = 4
            rim.position = holeCenter
            rim.zPosition = 1.8
            addChild(rim)

            let hole = SKShapeNode(circleOfRadius: board.holeRadius * 0.72)
            hole.fillColor = UIColor.black.withAlphaComponent(0.88)
            hole.strokeColor = UIColor.clear
            hole.position = holeCenter
            hole.zPosition = 1.9
            hole.physicsBody = SKPhysicsBody(circleOfRadius: board.holeRadius * 0.82)
            hole.physicsBody?.isDynamic = false
            hole.physicsBody?.categoryBitMask = PhysicsCategory.hole
            hole.physicsBody?.collisionBitMask = 0
            hole.physicsBody?.contactTestBitMask = PhysicsCategory.marble
            addChild(hole)
        }
    }

    private func createMarble() {
        let marble = SKShapeNode(circleOfRadius: board.marbleRadius)
        marble.fillColor = UIColor(red: 0.90, green: 0.94, blue: 0.99, alpha: 1.0)
        marble.strokeColor = UIColor(red: 0.65, green: 0.71, blue: 0.80, alpha: 1.0)
        marble.lineWidth = 3
        marble.glowWidth = 0.6
        marble.position = board.startPosition
        marble.zPosition = 4

        let highlight = SKShapeNode(circleOfRadius: board.marbleRadius * 0.28)
        highlight.fillColor = UIColor.white.withAlphaComponent(0.82)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -board.marbleRadius * 0.35, y: board.marbleRadius * 0.35)
        highlight.zPosition = 5
        marble.addChild(highlight)

        let physicsBody = SKPhysicsBody(circleOfRadius: board.marbleRadius)
        physicsBody.allowsRotation = true
        physicsBody.friction = Tuning.marbleFriction
        physicsBody.linearDamping = Tuning.marbleDamping
        physicsBody.angularDamping = 1.9
        physicsBody.restitution = Tuning.marbleRestitution
        physicsBody.mass = 0.06
        physicsBody.usesPreciseCollisionDetection = true
        physicsBody.categoryBitMask = PhysicsCategory.marble
        physicsBody.collisionBitMask = PhysicsCategory.wall
        physicsBody.contactTestBitMask = PhysicsCategory.goal | PhysicsCategory.hole
        marble.physicsBody = physicsBody

        marbleNode = marble
        addChild(marble)
    }

    private func handleGoalReached() {
        guard gameplayState == .playing else { return }
        gameplayState = .success
        freezeMarble()
        eventHandler?(.success)
    }

    private func handleHoleReached() {
        guard gameplayState == .playing, !isResolvingContact, let marbleNode else { return }
        isResolvingContact = true
        gameplayState = .failed
        physicsWorld.gravity = .zero
        marbleNode.physicsBody?.collisionBitMask = 0
        marbleNode.physicsBody?.contactTestBitMask = 0
        marbleNode.physicsBody?.velocity = .zero
        marbleNode.physicsBody?.angularVelocity = 0

        let shrink = SKAction.group([
            .scale(to: 0.30, duration: 0.22),
            .fadeOut(withDuration: 0.22)
        ])
        let finalize = SKAction.run { [weak self] in
            guard let self else { return }
            marbleNode.physicsBody?.isDynamic = false
            marbleNode.isHidden = true
            self.eventHandler?(.failed)
        }
        marbleNode.run(.sequence([shrink, finalize]))
    }

    private func freezeMarble() {
        marbleNode?.physicsBody?.velocity = .zero
        marbleNode?.physicsBody?.angularVelocity = 0
        marbleNode?.physicsBody?.isDynamic = false
        marbleNode?.physicsBody?.contactTestBitMask = 0
    }

    private func capMarbleVelocity() {
        guard let velocity = marbleNode?.physicsBody?.velocity else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > Tuning.maxSpeed else { return }

        let scale = Tuning.maxSpeed / speed
        marbleNode?.physicsBody?.velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
    }

    private func addLabel(text: String, at point: CGPoint, zPosition: CGFloat) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = 26
        label.fontColor = UIColor(red: 0.25, green: 0.20, blue: 0.12, alpha: 1.0)
        label.position = point
        label.zPosition = zPosition
        addChild(label)
    }
}
