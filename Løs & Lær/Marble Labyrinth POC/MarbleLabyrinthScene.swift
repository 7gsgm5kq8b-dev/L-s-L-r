import SpriteKit
import SwiftUI
import UIKit

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
        for attempt in 0..<16 {
            if let board = makeCandidate(seed: seed, attempt: attempt) {
                return board
            }
        }

        return fallbackBoard(seed: seed)
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

    func hasSameMazeTopology(as other: MarbleBoardConfiguration) -> Bool {
        boardSize == other.boardSize &&
        borderThickness == other.borderThickness &&
        wallRects == other.wallRects
    }

    private struct MazeCell: Hashable {
        let column: Int
        let row: Int
    }

    private enum MazeDirection: CaseIterable {
        case north
        case east
        case south
        case west

        var delta: (column: Int, row: Int) {
            switch self {
            case .north:
                return (0, 1)
            case .east:
                return (1, 0)
            case .south:
                return (0, -1)
            case .west:
                return (-1, 0)
            }
        }

        var opposite: MazeDirection {
            switch self {
            case .north:
                return .south
            case .east:
                return .west
            case .south:
                return .north
            case .west:
                return .east
            }
        }
    }

    private struct MazeLayout {
        let innerRect: CGRect
        let columns: Int
        let rows: Int
        let corridorSize: CGSize
        let wallThickness: CGFloat
        let origin: CGPoint

        func rect(for cell: MazeCell) -> CGRect {
            CGRect(
                x: origin.x + CGFloat(cell.column) * (corridorSize.width + wallThickness),
                y: origin.y + CGFloat(cell.row) * (corridorSize.height + wallThickness),
                width: corridorSize.width,
                height: corridorSize.height
            )
        }

        var allCells: [MazeCell] {
            (0..<rows).flatMap { row in
                (0..<columns).map { column in
                    MazeCell(column: column, row: row)
                }
            }
        }
    }

    private static func makeCandidate(seed: UInt64, attempt: Int) -> MarbleBoardConfiguration? {
        var random = SeededGenerator(seed: mixedSeed(base: seed, salt: UInt64(attempt + 1)))

        let boardSize = CGSize(width: 1280, height: 860)
        let borderThickness: CGFloat = 42
        let marbleRadius: CGFloat = 28
        let holeRadius: CGFloat = 24
        let boardRect = CGRect(origin: .zero, size: boardSize)
        let innerRect = boardRect.insetBy(dx: borderThickness, dy: borderThickness)

        guard let layout = makeMazeLayout(innerRect: innerRect, marbleRadius: marbleRadius) else {
            return nil
        }

        let startCell = MazeCell(column: 0, row: 0)
        let adjacency = carveMaze(startCell: startCell, layout: layout, random: &random)
        let search = farthestSearch(from: startCell, adjacency: adjacency, layout: layout)
        let goalCell = search.goal
        let solutionPath = path(from: startCell, to: goalCell, parents: search.parents)

        let startCellRect = layout.rect(for: startCell)
        let goalCellRect = layout.rect(for: goalCell)
        let startRect = markerRect(
            in: startCellRect,
            preferredSize: CGSize(width: 96, height: 66),
            horizontalBias: -0.22
        )
        let goalRect = markerRect(
            in: goalCellRect,
            preferredSize: CGSize(width: 94, height: 94),
            horizontalBias: goalCell.column == layout.columns - 1 ? 0.12 : 0
        )
        let startPosition = CGPoint(x: startRect.midX, y: startRect.midY)

        let wallRects = makeWallRects(layout: layout, adjacency: adjacency)
        let holes = makeMazeHoles(
            random: &random,
            layout: layout,
            adjacency: adjacency,
            solutionPath: solutionPath,
            holeRadius: holeRadius,
            startPosition: startPosition,
            goalRect: goalRect
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
            layout: layout,
            solutionPath: solutionPath
        ) ? board : nil
    }

    private static func fallbackBoard(seed: UInt64) -> MarbleBoardConfiguration {
        for saltOffset in 0..<32 {
            let fallbackSeed = mixedSeed(base: seed, salt: 0xFABBAC11 &+ UInt64(saltOffset))
            if let board = makeCandidate(seed: fallbackSeed, attempt: 0) {
                return MarbleBoardConfiguration(
                    id: "board_seed_\(seed)",
                    boardSeed: seed,
                    boardSize: board.boardSize,
                    borderThickness: board.borderThickness,
                    marbleRadius: board.marbleRadius,
                    holeRadius: board.holeRadius,
                    startRect: board.startRect,
                    startPosition: board.startPosition,
                    goalRect: board.goalRect,
                    wallRects: board.wallRects,
                    holes: board.holes
                )
            }
        }

        fatalError("Unable to generate Marble Labyrinth board")
    }

    private static func makeMazeLayout(innerRect: CGRect, marbleRadius: CGFloat) -> MazeLayout? {
        let columns = 7
        let rows = 4
        let wallThickness: CGFloat = 32
        let horizontalPadding: CGFloat = 48
        let verticalPadding: CGFloat = 54
        let availableWidth = innerRect.width - horizontalPadding * 2
        let availableHeight = innerRect.height - verticalPadding * 2
        let corridorWidth = floor((availableWidth - CGFloat(columns - 1) * wallThickness) / CGFloat(columns))
        let corridorHeight = floor((availableHeight - CGFloat(rows - 1) * wallThickness) / CGFloat(rows))
        let minimumCorridor = marbleRadius * 4.1

        guard corridorWidth >= minimumCorridor, corridorHeight >= minimumCorridor else {
            return nil
        }

        let mazeWidth = CGFloat(columns) * corridorWidth + CGFloat(columns - 1) * wallThickness
        let mazeHeight = CGFloat(rows) * corridorHeight + CGFloat(rows - 1) * wallThickness
        let origin = CGPoint(
            x: innerRect.midX - mazeWidth / 2,
            y: innerRect.midY - mazeHeight / 2
        )

        return MazeLayout(
            innerRect: innerRect,
            columns: columns,
            rows: rows,
            corridorSize: CGSize(width: corridorWidth, height: corridorHeight),
            wallThickness: wallThickness,
            origin: origin
        )
    }

    private static func carveMaze(
        startCell: MazeCell,
        layout: MazeLayout,
        random: inout SeededGenerator
    ) -> [MazeCell: Set<MazeDirection>] {
        var adjacency = Dictionary(uniqueKeysWithValues: layout.allCells.map { ($0, Set<MazeDirection>()) })
        var visited: Set<MazeCell> = [startCell]
        var stack: [MazeCell] = [startCell]

        while let current = stack.last {
            let directions = shuffledDirections(random: &random)
            if let direction = directions.first(where: {
                guard let nextCell = neighbor(of: current, direction: $0, layout: layout) else { return false }
                return !visited.contains(nextCell)
            }), let nextCell = neighbor(of: current, direction: direction, layout: layout) {
                adjacency[current, default: []].insert(direction)
                adjacency[nextCell, default: []].insert(direction.opposite)
                visited.insert(nextCell)
                stack.append(nextCell)
            } else {
                _ = stack.popLast()
            }
        }

        return adjacency
    }

    private static func farthestSearch(
        from startCell: MazeCell,
        adjacency: [MazeCell: Set<MazeDirection>],
        layout: MazeLayout
    ) -> (goal: MazeCell, parents: [MazeCell: MazeCell]) {
        var parents: [MazeCell: MazeCell] = [:]
        var distances: [MazeCell: Int] = [startCell: 0]
        var queue: [MazeCell] = [startCell]
        var cursor = 0
        var goal = startCell
        var bestScore = 0

        while cursor < queue.count {
            let cell = queue[cursor]
            cursor += 1
            let distance = distances[cell, default: 0]
            let score = distance * 100 + cell.column * 7 + cell.row * 11
            if score >= bestScore {
                bestScore = score
                goal = cell
            }

            for direction in MazeDirection.allCases where adjacency[cell, default: []].contains(direction) {
                guard let nextCell = neighbor(of: cell, direction: direction, layout: layout) else { continue }
                guard distances[nextCell] == nil else { continue }
                distances[nextCell] = distance + 1
                parents[nextCell] = cell
                queue.append(nextCell)
            }
        }

        return (goal, parents)
    }

    private static func path(
        from startCell: MazeCell,
        to goalCell: MazeCell,
        parents: [MazeCell: MazeCell]
    ) -> [MazeCell] {
        var route: [MazeCell] = [goalCell]
        var current = goalCell

        while current != startCell, let parent = parents[current] {
            current = parent
            route.append(current)
        }

        return route.reversed()
    }

    private static func makeWallRects(
        layout: MazeLayout,
        adjacency: [MazeCell: Set<MazeDirection>]
    ) -> [CGRect] {
        var wallRects: [CGRect] = []

        for cell in layout.allCells {
            let cellRect = layout.rect(for: cell)
            let openDirections = adjacency[cell, default: []]

            if cell.column < layout.columns - 1, !openDirections.contains(.east) {
                wallRects.append(
                    CGRect(
                        x: cellRect.maxX - layout.wallThickness / 2,
                        y: cellRect.minY - layout.wallThickness / 2,
                        width: layout.wallThickness,
                        height: cellRect.height + layout.wallThickness
                    )
                )
            }

            if cell.row < layout.rows - 1, !openDirections.contains(.north) {
                wallRects.append(
                    CGRect(
                        x: cellRect.minX - layout.wallThickness / 2,
                        y: cellRect.maxY - layout.wallThickness / 2,
                        width: cellRect.width + layout.wallThickness,
                        height: layout.wallThickness
                    )
                )
            }
        }

        return mergeWallRects(wallRects)
    }

    private static func makeMazeHoles(
        random: inout SeededGenerator,
        layout: MazeLayout,
        adjacency: [MazeCell: Set<MazeDirection>],
        solutionPath: [MazeCell],
        holeRadius: CGFloat,
        startPosition: CGPoint,
        goalRect: CGRect
    ) -> [CGPoint] {
        let solutionCells = Set(solutionPath)
        let deadEnds = layout.allCells.filter { cell in
            guard !solutionCells.contains(cell) else { return false }
            return (adjacency[cell]?.count ?? 0) == 1
        }
        let fallbackCells = layout.allCells.filter { cell in
            guard !solutionCells.contains(cell) else { return false }
            return cell.column > 0 && (adjacency[cell]?.count ?? 0) <= 2
        }
        let secondaryCells = layout.allCells.filter { cell in
            guard !solutionCells.contains(cell) else { return false }
            return cell.column > 0
        }
        let minimumHoleCount = 5

        var primaryCells = deadEnds.isEmpty ? fallbackCells : deadEnds
        var reserveCells = fallbackCells.filter { !primaryCells.contains($0) }
        if reserveCells.count < 2 {
            reserveCells.append(contentsOf: secondaryCells.filter { !primaryCells.contains($0) && !reserveCells.contains($0) })
        }
        shuffleInPlace(&primaryCells, random: &random)
        shuffleInPlace(&reserveCells, random: &random)

        let desiredCount = min(primaryCells.count + reserveCells.count, primaryCells.count >= 6 ? 6 : minimumHoleCount)
        var selectedCells: [MazeCell] = []
        var remainingPrimary = primaryCells
        var remainingReserve = reserveCells

        while selectedCells.count < desiredCount {
            let source = !remainingPrimary.isEmpty ? remainingPrimary : remainingReserve
            guard !source.isEmpty else { break }
            guard let nextCell = bestHoleCell(
                from: source,
                selected: selectedCells,
                layout: layout,
                startPosition: startPosition,
                goalRect: goalRect
            ) else {
                break
            }

            selectedCells.append(nextCell)
            remainingPrimary.removeAll { $0 == nextCell }
            remainingReserve.removeAll { $0 == nextCell }
        }

        var holes: [CGPoint] = []

        for cell in selectedCells {
            let cellRect = layout.rect(for: cell)
            let jitterX = min(cellRect.width * 0.10, 12)
            let jitterY = min(cellRect.height * 0.10, 12)
            let candidate = CGPoint(
                x: cellRect.midX + random.nextCGFloat(in: -jitterX...jitterX),
                y: cellRect.midY + random.nextCGFloat(in: -jitterY...jitterY)
            )

            guard distance(candidate, startPosition) > 220 else { continue }
            guard !goalRect.insetBy(dx: -80, dy: -80).contains(candidate) else { continue }
            guard holes.allSatisfy({ distance($0, candidate) > 138 }) else { continue }
            guard cellRect.insetBy(dx: holeRadius + 18, dy: holeRadius + 18).contains(candidate) else { continue }

            holes.append(candidate)
            if holes.count >= desiredCount {
                break
            }
        }

        if holes.count < minimumHoleCount {
            let fallbackSource = reserveCells + secondaryCells.filter { !reserveCells.contains($0) && !selectedCells.contains($0) }
            for cell in fallbackSource where !selectedCells.contains(cell) {
                let cellRect = layout.rect(for: cell)
                let candidate = CGPoint(x: cellRect.midX, y: cellRect.midY)
                guard distance(candidate, startPosition) > 220 else { continue }
                guard !goalRect.insetBy(dx: -80, dy: -80).contains(candidate) else { continue }
                guard holes.allSatisfy({ distance($0, candidate) > 138 }) else { continue }
                guard cellRect.insetBy(dx: holeRadius + 18, dy: holeRadius + 18).contains(candidate) else { continue }
                holes.append(candidate)
                if holes.count >= minimumHoleCount { break }
            }
        }

        return holes
    }

    private static func isValid(
        board: MarbleBoardConfiguration,
        layout: MazeLayout,
        solutionPath: [MazeCell]
    ) -> Bool {
        let innerRect = layout.innerRect
        let solutionRects = solutionPath.map { layout.rect(for: $0) }

        guard innerRect.contains(board.startPosition) else { return false }
        guard innerRect.contains(CGPoint(x: board.goalRect.midX, y: board.goalRect.midY)) else { return false }
        guard !board.wallRects.isEmpty else { return false }
        guard board.wallRects.allSatisfy({ innerRect.contains($0) }) else { return false }
        guard board.wallRects.allSatisfy({ !$0.intersects(board.startRect.insetBy(dx: -16, dy: -16)) }) else { return false }
        guard board.wallRects.allSatisfy({ !$0.intersects(board.goalRect.insetBy(dx: -16, dy: -16)) }) else { return false }
        guard !board.holes.isEmpty else { return false }
        guard board.holes.count >= 5 else { return false }
        guard board.holes.allSatisfy({ innerRect.insetBy(dx: board.holeRadius + 10, dy: board.holeRadius + 10).contains($0) }) else { return false }
        guard board.holes.allSatisfy({ hole in solutionRects.allSatisfy { !expanded($0, by: board.holeRadius + board.marbleRadius * 0.85).contains(hole) } }) else { return false }
        guard board.holes.allSatisfy({ hole in board.wallRects.allSatisfy { !expanded($0, by: board.holeRadius + 4).contains(hole) } }) else { return false }
        guard board.holes.allSatisfy({ distance($0, board.startPosition) > 220 }) else { return false }
        guard distance(board.startPosition, CGPoint(x: board.goalRect.midX, y: board.goalRect.midY)) > innerRect.width * 0.42 else { return false }

        for index in board.holes.indices {
            for otherIndex in board.holes.indices where otherIndex > index {
                guard distance(board.holes[index], board.holes[otherIndex]) > 138 else { return false }
            }
        }

        return true
    }

    private static func expanded(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        rect.insetBy(dx: -amount, dy: -amount)
    }

    private static func markerRect(
        in cellRect: CGRect,
        preferredSize: CGSize,
        horizontalBias: CGFloat
    ) -> CGRect {
        let width = min(preferredSize.width, cellRect.width * 0.74)
        let height = min(preferredSize.height, cellRect.height * 0.70)
        let availableTravel = max(0, cellRect.width - width)
        let x = cellRect.minX + availableTravel * (0.5 + horizontalBias * 0.5)
        let y = cellRect.midY - height / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func bestHoleCell(
        from candidates: [MazeCell],
        selected: [MazeCell],
        layout: MazeLayout,
        startPosition: CGPoint,
        goalRect: CGRect
    ) -> MazeCell? {
        candidates.max { lhs, rhs in
            holeCellScore(
                for: lhs,
                selected: selected,
                layout: layout,
                startPosition: startPosition,
                goalRect: goalRect
            ) < holeCellScore(
                for: rhs,
                selected: selected,
                layout: layout,
                startPosition: startPosition,
                goalRect: goalRect
            )
        }
    }

    private static func holeCellScore(
        for cell: MazeCell,
        selected: [MazeCell],
        layout: MazeLayout,
        startPosition: CGPoint,
        goalRect: CGRect
    ) -> CGFloat {
        let cellRect = layout.rect(for: cell)
        let center = CGPoint(x: cellRect.midX, y: cellRect.midY)
        let rowDiversityBonus: CGFloat = selected.contains(where: { $0.row == cell.row }) ? 0 : 220
        let columnDiversityBonus: CGFloat = selected.contains(where: { abs($0.column - cell.column) <= 1 }) ? 0 : 160
        let minimumDistanceToOther = selected
            .map { distance(center, CGPoint(x: layout.rect(for: $0).midX, y: layout.rect(for: $0).midY)) }
            .min() ?? 240
        let startDistanceScore = min(distance(center, startPosition), 420) * 0.42
        let goalDistanceScore = min(distance(center, CGPoint(x: goalRect.midX, y: goalRect.midY)), 320) * 0.16
        let verticalSpread = CGFloat(cell.row) * 22
        return rowDiversityBonus + columnDiversityBonus + minimumDistanceToOther * 0.95 + startDistanceScore + goalDistanceScore + verticalSpread
    }

    private static func neighbor(
        of cell: MazeCell,
        direction: MazeDirection,
        layout: MazeLayout
    ) -> MazeCell? {
        let nextColumn = cell.column + direction.delta.column
        let nextRow = cell.row + direction.delta.row

        guard (0..<layout.columns).contains(nextColumn), (0..<layout.rows).contains(nextRow) else {
            return nil
        }

        return MazeCell(column: nextColumn, row: nextRow)
    }

    private static func shuffledDirections(random: inout SeededGenerator) -> [MazeDirection] {
        var directions = MazeDirection.allCases
        shuffleInPlace(&directions, random: &random)
        return directions
    }

    private static func shuffleInPlace<T>(_ values: inout [T], random: inout SeededGenerator) {
        guard values.count > 1 else { return }

        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let swapIndex = random.nextInt(in: 0...index)
            guard swapIndex != index else { continue }
            values.swapAt(index, swapIndex)
        }
    }

    private static func mergeWallRects(_ wallRects: [CGRect]) -> [CGRect] {
        let epsilon: CGFloat = 1.0
        let horizontal = wallRects
            .filter { $0.width >= $0.height }
            .sorted {
                if abs($0.minY - $1.minY) > epsilon {
                    return $0.minY < $1.minY
                }
                return $0.minX < $1.minX
            }
        let vertical = wallRects
            .filter { $0.height > $0.width }
            .sorted {
                if abs($0.minX - $1.minX) > epsilon {
                    return $0.minX < $1.minX
                }
                return $0.minY < $1.minY
            }

        return mergeHorizontalWallRects(horizontal, epsilon: epsilon) + mergeVerticalWallRects(vertical, epsilon: epsilon)
    }

    private static func mergeHorizontalWallRects(_ wallRects: [CGRect], epsilon: CGFloat) -> [CGRect] {
        var merged: [CGRect] = []

        for rect in wallRects {
            guard var last = merged.last else {
                merged.append(rect.integral)
                continue
            }

            if abs(last.minY - rect.minY) <= epsilon,
                abs(last.height - rect.height) <= epsilon,
                rect.minX <= last.maxX + epsilon {
                last = CGRect(
                    x: last.minX,
                    y: min(last.minY, rect.minY),
                    width: max(last.maxX, rect.maxX) - last.minX,
                    height: max(last.height, rect.height)
                ).integral
                merged[merged.count - 1] = last
            } else {
                merged.append(rect.integral)
            }
        }

        return merged
    }

    private static func mergeVerticalWallRects(_ wallRects: [CGRect], epsilon: CGFloat) -> [CGRect] {
        var merged: [CGRect] = []

        for rect in wallRects {
            guard var last = merged.last else {
                merged.append(rect.integral)
                continue
            }

            if abs(last.minX - rect.minX) <= epsilon,
                abs(last.width - rect.width) <= epsilon,
                rect.minY <= last.maxY + epsilon {
                last = CGRect(
                    x: min(last.minX, rect.minX),
                    y: last.minY,
                    width: max(last.width, rect.width),
                    height: max(last.maxY, rect.maxY) - last.minY
                ).integral
                merged[merged.count - 1] = last
            } else {
                merged.append(rect.integral)
            }
        }

        return merged
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
        case marbleStartedMoving
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

    private enum Theme {
        static let sceneBackground = UIColor(red: 0.89, green: 0.96, blue: 0.98, alpha: 1.0)
        static let trayFill = UIColor(red: 0.98, green: 0.95, blue: 0.87, alpha: 0.16)
        static let trayStroke = UIColor(red: 0.72, green: 0.63, blue: 0.47, alpha: 0.22)
        static let waterFill = UIColor(red: 0.22, green: 0.65, blue: 0.95, alpha: 0.95)
        static let waterCenter = UIColor(red: 0.43, green: 0.82, blue: 0.99, alpha: 1.0)
        static let waterMid = UIColor(red: 0.27, green: 0.70, blue: 0.96, alpha: 1.0)
        static let waterEdge = UIColor(red: 0.17, green: 0.58, blue: 0.88, alpha: 1.0)
        static let waterEdgeDeep = UIColor(red: 0.11, green: 0.49, blue: 0.78, alpha: 1.0)
        static let waterStroke = UIColor(red: 0.12, green: 0.53, blue: 0.80, alpha: 0.76)
        static let bankSoft = UIColor(red: 0.55, green: 0.45, blue: 0.30, alpha: 0.10)
        static let waterHighlight = UIColor.white.withAlphaComponent(0.10)
        static let shoreShadow = UIColor(red: 0.06, green: 0.24, blue: 0.38, alpha: 0.16)
        static let shoreFoam = UIColor.white.withAlphaComponent(0.24)
        static let beamTop = UIColor(red: 0.83, green: 0.64, blue: 0.36, alpha: 1.0)
        static let beamSide = UIColor(red: 0.64, green: 0.45, blue: 0.21, alpha: 0.98)
        static let beamStroke = UIColor(red: 0.46, green: 0.31, blue: 0.14, alpha: 0.76)
        static let beamShadow = UIColor(red: 0.06, green: 0.19, blue: 0.28, alpha: 0.16)
        static let beamHighlight = UIColor.white.withAlphaComponent(0.18)
        static let beamGrain = UIColor(red: 0.42, green: 0.28, blue: 0.12, alpha: 0.28)
        static let beamEdgeShade = UIColor(red: 0.31, green: 0.20, blue: 0.08, alpha: 0.20)
        static let beamInsetStroke = UIColor.white.withAlphaComponent(0.12)
        static let beamGloss = UIColor(red: 0.98, green: 0.89, blue: 0.67, alpha: 0.12)
        static let markerShadow = UIColor(red: 0.05, green: 0.17, blue: 0.25, alpha: 0.10)
        static let markerInnerStroke = UIColor.white.withAlphaComponent(0.24)
        static let markerRipple = UIColor.white.withAlphaComponent(0.18)
        static let markerFillShadow = UIColor(red: 0.08, green: 0.21, blue: 0.31, alpha: 0.12)
        static let startFill = UIColor(red: 0.69, green: 0.95, blue: 0.88, alpha: 0.88)
        static let startStroke = UIColor(red: 0.28, green: 0.69, blue: 0.58, alpha: 0.92)
        static let goalFill = UIColor(red: 1.0, green: 0.87, blue: 0.47, alpha: 0.96)
        static let goalStroke = UIColor(red: 0.86, green: 0.61, blue: 0.18, alpha: 0.94)
        static let goalGlow = UIColor(red: 1.0, green: 0.90, blue: 0.56, alpha: 0.22)
        static let goalCupFill = UIColor(red: 0.99, green: 0.95, blue: 0.79, alpha: 0.96)
        static let goalCupInner = UIColor(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.96)
        static let goalFlag = UIColor(red: 0.97, green: 0.45, blue: 0.36, alpha: 0.96)
        static let goalSpark = UIColor.white.withAlphaComponent(0.92)
        static let goalHalo = UIColor(red: 1.0, green: 0.92, blue: 0.62, alpha: 0.34)
        static let goalRingFill = UIColor(red: 1.0, green: 0.94, blue: 0.74, alpha: 0.96)
        static let goalRingInner = UIColor(red: 0.99, green: 0.84, blue: 0.35, alpha: 0.96)
        static let goalWellFill = UIColor(red: 0.13, green: 0.48, blue: 0.76, alpha: 0.96)
        static let goalWellDeep = UIColor(red: 0.07, green: 0.30, blue: 0.52, alpha: 0.96)
        static let goalStarFill = UIColor(red: 1.0, green: 0.95, blue: 0.73, alpha: 1.0)
        static let goalStarStroke = UIColor(red: 0.86, green: 0.61, blue: 0.18, alpha: 0.88)
        static let holeShadow = UIColor(red: 0.05, green: 0.19, blue: 0.31, alpha: 0.12)
        static let holeSurfaceRing = UIColor(red: 0.61, green: 0.87, blue: 0.97, alpha: 0.22)
        static let holeOuterFill = UIColor(red: 0.08, green: 0.47, blue: 0.72, alpha: 0.96)
        static let holeMidFill = UIColor(red: 0.06, green: 0.34, blue: 0.55, alpha: 0.98)
        static let holeCoreFill = UIColor(red: 0.05, green: 0.21, blue: 0.37, alpha: 0.94)
        static let holeRimStroke = UIColor(red: 0.63, green: 0.87, blue: 0.98, alpha: 0.58)
        static let holeFoam = UIColor(red: 0.84, green: 0.96, blue: 1.0, alpha: 0.46)
        static let holeGlow = UIColor(red: 0.30, green: 0.66, blue: 0.91, alpha: 0.26)
        static let marbleFill = UIColor(red: 0.97, green: 0.98, blue: 1.0, alpha: 1.0)
        static let marbleStroke = UIColor(red: 0.46, green: 0.64, blue: 0.82, alpha: 0.96)
        static let marbleInnerRim = UIColor.white.withAlphaComponent(0.52)
        static let marbleLowerShade = UIColor(red: 0.64, green: 0.77, blue: 0.90, alpha: 0.24)
        static let marbleGloss = UIColor.white.withAlphaComponent(0.26)
        static let marbleEdgeShadow = UIColor(red: 0.41, green: 0.56, blue: 0.72, alpha: 0.18)
        static let marbleBlueReflect = UIColor(red: 0.78, green: 0.89, blue: 0.98, alpha: 0.36)
        static let labelColor = UIColor(red: 0.10, green: 0.24, blue: 0.38, alpha: 1.0)
    }

    private enum BoardLocationStyle {
        case startPad
        case goalPad
    }

    private struct BeamVisualStyle {
        let cornerRadius: CGFloat
        let shadowYOffset: CGFloat
        let highlightInset: CGFloat
        let highlightYOffset: CGFloat
        let highlightAlpha: CGFloat
        let primaryGrainYOffset: CGFloat
        let secondaryGrainYOffset: CGFloat
        let seamBias: CGFloat
    }

    private let board: MarbleBoardConfiguration
    private unowned let motionController: MarbleTiltController
    var eventHandler: ((Event) -> Void)?

    private var marbleNode: SKShapeNode?
    private var goalNode: SKShapeNode?
    private var gameplayState: GameplayState = .ready
    private var isResolvingContact = false
    private var hasReportedMarbleMovement = false

    var boardSeed: UInt64 {
        board.boardSeed
    }

    init(board: MarbleBoardConfiguration, motionController: MarbleTiltController) {
        self.board = board
        self.motionController = motionController
        super.init(size: board.boardSize)
        scaleMode = .aspectFit
        backgroundColor = Theme.sceneBackground
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
        reportMarbleMovementIfNeeded()
    }

    func resetMarble(manual: Bool) {
        guard let marbleNode else { return }
        isResolvingContact = false
        hasReportedMarbleMovement = false
        resetGoalPresentation()
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
        hasReportedMarbleMovement = false
        resetGoalPresentation()
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
        tray.fillColor = Theme.trayFill
        tray.strokeColor = Theme.trayStroke
        tray.lineWidth = 2.5
        tray.position = .zero
        tray.zPosition = 0
        addChild(tray)

        let waterCrop = SKCropNode()
        waterCrop.zPosition = 0.95

        let playfieldMask = SKShapeNode(rect: innerRect, cornerRadius: 34)
        playfieldMask.fillColor = .white
        playfieldMask.strokeColor = .clear
        waterCrop.maskNode = playfieldMask

        let waterGradient = SKSpriteNode(texture: waterGradientTexture(size: innerRect.size))
        waterGradient.size = innerRect.size
        waterGradient.position = CGPoint(x: innerRect.midX, y: innerRect.midY)
        waterCrop.addChild(waterGradient)
        addChild(waterCrop)

        let playfield = SKShapeNode(rect: innerRect, cornerRadius: 34)
        playfield.fillColor = .clear
        playfield.strokeColor = Theme.waterStroke
        playfield.lineWidth = 2.4
        playfield.zPosition = 1
        addChild(playfield)

        let waterBank = SKShapeNode(rect: innerRect, cornerRadius: 34)
        waterBank.fillColor = .clear
        waterBank.strokeColor = Theme.bankSoft
        waterBank.lineWidth = 22
        waterBank.zPosition = 1.05
        addChild(waterBank)

        let shorelineShadow = SKShapeNode(rect: innerRect.insetBy(dx: 5, dy: 5), cornerRadius: 30)
        shorelineShadow.fillColor = .clear
        shorelineShadow.strokeColor = Theme.shoreShadow
        shorelineShadow.lineWidth = 14
        shorelineShadow.zPosition = 1.08
        addChild(shorelineShadow)

        let waterHighlight = SKShapeNode(rect: innerRect.insetBy(dx: 8, dy: 8), cornerRadius: 28)
        waterHighlight.fillColor = .clear
        waterHighlight.strokeColor = Theme.waterHighlight
        waterHighlight.lineWidth = 4.5
        waterHighlight.zPosition = 1.1
        addChild(waterHighlight)

        let shorelineFoam = SKShapeNode(rect: innerRect.insetBy(dx: 14, dy: 14), cornerRadius: 22)
        shorelineFoam.fillColor = .clear
        shorelineFoam.strokeColor = Theme.shoreFoam
        shorelineFoam.lineWidth = 2.2
        shorelineFoam.zPosition = 1.14
        addChild(shorelineFoam)

        let edgeNode = SKNode()
        edgeNode.physicsBody = SKPhysicsBody(edgeLoopFrom: innerRect)
        edgeNode.physicsBody?.friction = Tuning.wallFriction
        edgeNode.physicsBody?.categoryBitMask = PhysicsCategory.wall
        edgeNode.physicsBody?.contactTestBitMask = 0
        edgeNode.physicsBody?.collisionBitMask = PhysicsCategory.marble
        addChild(edgeNode)

        _ = addBoardMarker(
            rect: board.startRect,
            text: "Start",
            fill: Theme.startFill,
            stroke: Theme.startStroke,
            style: .startPad
        )

        let goalNode = addBoardMarker(
            rect: board.goalRect,
            text: "Mål",
            fill: Theme.goalFill,
            stroke: Theme.goalStroke,
            style: .goalPad
        )
        self.goalNode = goalNode
        goalNode.physicsBody = SKPhysicsBody(rectangleOf: board.goalRect.size)
        goalNode.physicsBody?.isDynamic = false
        goalNode.physicsBody?.categoryBitMask = PhysicsCategory.goal
        goalNode.physicsBody?.collisionBitMask = 0
        goalNode.physicsBody?.contactTestBitMask = PhysicsCategory.marble

        for wallRect in board.wallRects {
            addFloatingBarrier(wallRect)
        }
        addWallCornerCaps(for: board.wallRects)

        for holeCenter in board.holes {
            addWhirlpool(at: holeCenter)
        }
    }

    private func createMarble() {
        let marble = SKShapeNode(circleOfRadius: board.marbleRadius)
        marble.fillColor = Theme.marbleFill
        marble.strokeColor = Theme.marbleStroke
        marble.lineWidth = 3
        marble.glowWidth = 1.1
        marble.position = board.startPosition
        marble.zPosition = 4

        let shadow = SKShapeNode(circleOfRadius: board.marbleRadius * 0.94)
        shadow.fillColor = UIColor.black.withAlphaComponent(0.14)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: board.marbleRadius * 0.12, y: -board.marbleRadius * 0.14)
        shadow.zPosition = -1
        marble.addChild(shadow)

        let lowerShade = SKShapeNode(circleOfRadius: board.marbleRadius * 0.84)
        lowerShade.fillColor = Theme.marbleLowerShade
        lowerShade.strokeColor = .clear
        lowerShade.position = CGPoint(x: board.marbleRadius * 0.14, y: -board.marbleRadius * 0.18)
        lowerShade.zPosition = 0.05
        marble.addChild(lowerShade)

        let innerRim = SKShapeNode(circleOfRadius: board.marbleRadius * 0.88)
        innerRim.fillColor = .clear
        innerRim.strokeColor = Theme.marbleInnerRim
        innerRim.lineWidth = 1.4
        innerRim.zPosition = 0.1
        marble.addChild(innerRim)

        let edgeShadow = SKShapeNode(circleOfRadius: board.marbleRadius * 0.92)
        edgeShadow.fillColor = .clear
        edgeShadow.strokeColor = Theme.marbleEdgeShadow
        edgeShadow.lineWidth = 1.2
        edgeShadow.zPosition = 0.08
        marble.addChild(edgeShadow)

        let glossBand = SKShapeNode(ellipseOf: CGSize(width: board.marbleRadius * 1.26, height: board.marbleRadius * 0.48))
        glossBand.fillColor = Theme.marbleGloss
        glossBand.strokeColor = .clear
        glossBand.position = CGPoint(x: -board.marbleRadius * 0.10, y: board.marbleRadius * 0.16)
        glossBand.zPosition = 0.15
        marble.addChild(glossBand)

        let waterReflection = SKShapeNode(ellipseOf: CGSize(width: board.marbleRadius * 0.92, height: board.marbleRadius * 0.26))
        waterReflection.fillColor = Theme.marbleBlueReflect
        waterReflection.strokeColor = .clear
        waterReflection.position = CGPoint(x: board.marbleRadius * 0.10, y: -board.marbleRadius * 0.04)
        waterReflection.zPosition = 0.14
        marble.addChild(waterReflection)

        let highlight = SKShapeNode(circleOfRadius: board.marbleRadius * 0.28)
        highlight.fillColor = UIColor.white.withAlphaComponent(0.82)
        highlight.strokeColor = .clear
        highlight.position = CGPoint(x: -board.marbleRadius * 0.35, y: board.marbleRadius * 0.35)
        highlight.zPosition = 5
        marble.addChild(highlight)

        let sparkle = SKShapeNode(circleOfRadius: board.marbleRadius * 0.11)
        sparkle.fillColor = UIColor.white.withAlphaComponent(0.96)
        sparkle.strokeColor = .clear
        sparkle.position = CGPoint(x: -board.marbleRadius * 0.12, y: board.marbleRadius * 0.10)
        sparkle.zPosition = 5.1
        marble.addChild(sparkle)

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

        guard let goalNode else {
            eventHandler?(.success)
            return
        }

        goalNode.removeAction(forKey: "goalCelebrate")

        let pulseUp = SKAction.scale(to: 1.08, duration: 0.24)
        pulseUp.timingMode = .easeOut

        let pulseDown = SKAction.scale(to: 1.0, duration: 0.22)
        pulseDown.timingMode = .easeInEaseOut

        let celebration = SKAction.sequence([
            pulseUp,
            pulseDown,
            .wait(forDuration: 0.08),
            .run { [weak self] in
                self?.eventHandler?(.success)
            }
        ])

        goalNode.run(celebration, withKey: "goalCelebrate")
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

    private func resetGoalPresentation() {
        goalNode?.removeAction(forKey: "goalCelebrate")
        goalNode?.setScale(1)
        goalNode?.alpha = 1
    }

    private func capMarbleVelocity() {
        guard let velocity = marbleNode?.physicsBody?.velocity else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > Tuning.maxSpeed else { return }

        let scale = Tuning.maxSpeed / speed
        marbleNode?.physicsBody?.velocity = CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
    }

    private func reportMarbleMovementIfNeeded() {
        guard !hasReportedMarbleMovement, let velocity = marbleNode?.physicsBody?.velocity else { return }

        let speed = hypot(velocity.dx, velocity.dy)
        guard speed > 18 else { return }

        hasReportedMarbleMovement = true
        eventHandler?(.marbleStartedMoving)
    }

    private func addBoardMarker(
        rect: CGRect,
        text: String,
        fill: UIColor,
        stroke: UIColor,
        style: BoardLocationStyle
    ) -> SKShapeNode {
        let markerCornerRadius = min(rect.width, rect.height) * 0.24

        let marker = SKShapeNode(rectOf: rect.size, cornerRadius: markerCornerRadius)
        marker.fillColor = .clear
        marker.strokeColor = .clear
        marker.position = CGPoint(x: rect.midX, y: rect.midY)
        marker.zPosition = 1.5

        switch style {
        case .startPad:
            let rippleShadow = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.70, height: rect.height * 0.24))
            rippleShadow.fillColor = Theme.markerShadow
            rippleShadow.strokeColor = .clear
            rippleShadow.position = CGPoint(x: 0, y: -rect.height * 0.08)
            rippleShadow.zPosition = -0.4
            marker.addChild(rippleShadow)

            let ripple = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.74, height: rect.height * 0.28))
            ripple.fillColor = .clear
            ripple.strokeColor = Theme.markerRipple
            ripple.lineWidth = 1.2
            ripple.position = CGPoint(x: 0, y: -rect.height * 0.04)
            ripple.zPosition = -0.3
            marker.addChild(ripple)

            let padSize = CGSize(width: rect.width * 0.60, height: rect.height * 0.34)
            let padCorner = padSize.height * 0.30
            let padShadow = SKShapeNode(rectOf: padSize, cornerRadius: padCorner)
            padShadow.fillColor = Theme.markerFillShadow
            padShadow.strokeColor = .clear
            padShadow.position = CGPoint(x: 0, y: -3)
            padShadow.zPosition = -0.1
            marker.addChild(padShadow)

            let pad = SKShapeNode(rectOf: padSize, cornerRadius: padCorner)
            pad.fillColor = fill
            pad.strokeColor = stroke
            pad.lineWidth = 1.8
            marker.addChild(pad)

            let padInset = SKShapeNode(
                rectOf: CGSize(width: padSize.width - 10, height: padSize.height - 10),
                cornerRadius: max(8, padCorner - 4)
            )
            padInset.fillColor = .clear
            padInset.strokeColor = Theme.markerInnerStroke
            padInset.lineWidth = 1.0
            padInset.alpha = 0.74
            pad.addChild(padInset)

            let padHighlight = SKShapeNode(
                rectOf: CGSize(width: padSize.width - 18, height: max(5, padSize.height * 0.16)),
                cornerRadius: max(3, padSize.height * 0.08)
            )
            padHighlight.fillColor = UIColor.white.withAlphaComponent(0.18)
            padHighlight.strokeColor = .clear
            padHighlight.position = CGPoint(x: 0, y: padSize.height * 0.16)
            padHighlight.zPosition = 0.1
            pad.addChild(padHighlight)

            let launchStripe = SKShapeNode(
                rectOf: CGSize(width: padSize.width * 0.30, height: max(4, padSize.height * 0.14)),
                cornerRadius: max(3, padSize.height * 0.07)
            )
            launchStripe.fillColor = stroke.withAlphaComponent(0.24)
            launchStripe.strokeColor = .clear
            launchStripe.position = CGPoint(x: 0, y: padSize.height * 0.02)
            launchStripe.zPosition = 0.12
            pad.addChild(launchStripe)

            let label = boardLabel(text: text, fontSize: 18)
            label.position = CGPoint(x: 0, y: -2)
            label.zPosition = 0.2
            pad.addChild(label)

        case .goalPad:
            let haloRadius = min(rect.width, rect.height) * 0.52
            let glow = SKShapeNode(circleOfRadius: haloRadius)
            glow.fillColor = Theme.goalHalo
            glow.strokeColor = .clear
            glow.position = CGPoint(x: 0, y: -rect.height * 0.01)
            glow.zPosition = -0.28
            marker.addChild(glow)

            let ripple = SKShapeNode(ellipseOf: CGSize(width: rect.width * 0.82, height: rect.height * 0.30))
            ripple.fillColor = .clear
            ripple.strokeColor = Theme.goalGlow.withAlphaComponent(0.95)
            ripple.lineWidth = 1.5
            ripple.position = CGPoint(x: 0, y: -rect.height * 0.12)
            ripple.zPosition = -0.2
            marker.addChild(ripple)

            let cupRadius = min(rect.width, rect.height) * 0.38
            let cupShadow = SKShapeNode(circleOfRadius: cupRadius * 1.10)
            cupShadow.fillColor = Theme.markerFillShadow
            cupShadow.strokeColor = .clear
            cupShadow.position = CGPoint(x: 0, y: -4)
            cupShadow.zPosition = -0.1
            marker.addChild(cupShadow)

            let cup = SKShapeNode(circleOfRadius: cupRadius)
            cup.fillColor = Theme.goalRingFill
            cup.strokeColor = stroke
            cup.lineWidth = 4.2
            marker.addChild(cup)

            let cupInnerBand = SKShapeNode(circleOfRadius: cupRadius * 0.82)
            cupInnerBand.fillColor = Theme.goalRingInner
            cupInnerBand.strokeColor = UIColor.white.withAlphaComponent(0.34)
            cupInnerBand.lineWidth = 1.0
            cupInnerBand.zPosition = 0.12
            cup.addChild(cupInnerBand)

            let cupRim = SKShapeNode(circleOfRadius: cupRadius * 0.64)
            cupRim.fillColor = .clear
            cupRim.strokeColor = UIColor.white.withAlphaComponent(0.58)
            cupRim.lineWidth = 1.4
            cupRim.zPosition = 0.16
            cup.addChild(cupRim)

            let goalWell = SKShapeNode(circleOfRadius: cupRadius * 0.48)
            goalWell.fillColor = Theme.goalWellFill
            goalWell.strokeColor = Theme.goalWellDeep
            goalWell.lineWidth = 1.6
            goalWell.zPosition = 0.17
            cup.addChild(goalWell)

            let goalCore = SKShapeNode(circleOfRadius: cupRadius * 0.28)
            goalCore.fillColor = Theme.goalWellDeep
            goalCore.strokeColor = .clear
            goalCore.zPosition = 0.18
            goalWell.addChild(goalCore)

            let finishRing = SKShapeNode(circleOfRadius: cupRadius * 1.16)
            finishRing.fillColor = .clear
            finishRing.strokeColor = UIColor.white.withAlphaComponent(0.38)
            finishRing.lineWidth = 1.6
            finishRing.zPosition = -0.05
            marker.addChild(finishRing)

            let pole = decorativeLine(
                from: CGPoint(x: cupRadius * 0.52, y: cupRadius * 0.06),
                to: CGPoint(x: cupRadius * 0.52, y: cupRadius * 1.04),
                strokeColor: stroke.withAlphaComponent(0.88),
                lineWidth: 2.6
            )
            pole.zPosition = 0.18
            marker.addChild(pole)

            let flag = SKShapeNode(path: pennantPath(size: CGSize(width: cupRadius * 0.72, height: cupRadius * 0.40)))
            flag.fillColor = Theme.goalFlag
            flag.strokeColor = UIColor.white.withAlphaComponent(0.28)
            flag.lineWidth = 0.8
            flag.position = CGPoint(x: cupRadius * 0.52, y: cupRadius * 0.82)
            flag.zPosition = 0.2
            marker.addChild(flag)

            let star = SKShapeNode(path: starPath(radius: cupRadius * 0.22, points: 5, innerRatio: 0.50))
            star.fillColor = Theme.goalStarFill
            star.strokeColor = Theme.goalStarStroke
            star.lineWidth = 1.2
            star.position = CGPoint(x: -cupRadius * 0.58, y: cupRadius * 0.52)
            star.zPosition = 0.23
            marker.addChild(star)

            let sparkle = SKShapeNode(circleOfRadius: cupRadius * 0.10)
            sparkle.fillColor = Theme.goalSpark
            sparkle.strokeColor = .clear
            sparkle.position = CGPoint(x: -cupRadius * 0.06, y: cupRadius * 0.82)
            sparkle.zPosition = 0.24
            marker.addChild(sparkle)
        }

        addChild(marker)
        return marker
    }

    private func addFloatingBarrier(_ wallRect: CGRect) {
        let style = beamVisualStyle(for: wallRect)
        let isHorizontal = wallRect.width >= wallRect.height
        let majorLength = isHorizontal ? wallRect.width : wallRect.height
        let minorThickness = isHorizontal ? wallRect.height : wallRect.width
        let shadowSize = isHorizontal
            ? CGSize(width: max(18, wallRect.width - 4), height: max(18, wallRect.height * 0.84))
            : CGSize(width: max(18, wallRect.width * 0.84), height: max(18, wallRect.height - 4))
        let shadow = SKShapeNode(rectOf: shadowSize, cornerRadius: style.cornerRadius)
        shadow.fillColor = Theme.beamShadow
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: wallRect.midX, y: wallRect.midY + style.shadowYOffset)
        shadow.zPosition = 1.78
        addChild(shadow)

        let beam = SKShapeNode(rectOf: wallRect.size, cornerRadius: style.cornerRadius)
        beam.fillColor = Theme.beamTop
        beam.strokeColor = Theme.beamStroke
        beam.lineWidth = 3.0
        beam.zPosition = 2
        beam.physicsBody = SKPhysicsBody(rectangleOf: wallRect.size)
        beam.physicsBody?.isDynamic = false
        beam.physicsBody?.friction = Tuning.wallFriction
        beam.physicsBody?.categoryBitMask = PhysicsCategory.wall
        beam.physicsBody?.collisionBitMask = PhysicsCategory.marble
        beam.physicsBody?.contactTestBitMask = 0
        beam.position = CGPoint(x: wallRect.midX, y: wallRect.midY)

        let underside = SKShapeNode(
            rectOf: isHorizontal
                ? CGSize(width: max(18, wallRect.width - 2), height: max(16, wallRect.height * 0.88))
                : CGSize(width: max(16, wallRect.width * 0.88), height: max(18, wallRect.height - 2)),
            cornerRadius: max(10, style.cornerRadius - 2)
        )
        underside.fillColor = Theme.beamSide
        underside.strokeColor = .clear
        underside.position = isHorizontal ? CGPoint(x: 0, y: -3.0) : CGPoint(x: 2.3, y: -1.6)
        underside.zPosition = -0.1
        beam.addChild(underside)

        let insetStroke = SKShapeNode(
            rectOf: CGSize(width: max(16, wallRect.width - 10), height: max(16, wallRect.height - 10)),
            cornerRadius: max(8, style.cornerRadius - 4)
        )
        insetStroke.fillColor = .clear
        insetStroke.strokeColor = Theme.beamInsetStroke
        insetStroke.lineWidth = 1.1
        insetStroke.zPosition = 0.08
        beam.addChild(insetStroke)

        let topHighlight = SKShapeNode(
            rectOf: isHorizontal
                ? CGSize(width: max(20, majorLength - style.highlightInset), height: max(5, minorThickness * 0.16))
                : CGSize(width: max(5, minorThickness * 0.16), height: max(20, majorLength - style.highlightInset)),
            cornerRadius: max(4, minorThickness * 0.09)
        )
        topHighlight.fillColor = Theme.beamHighlight.withAlphaComponent(style.highlightAlpha)
        topHighlight.strokeColor = .clear
        topHighlight.position = isHorizontal
            ? CGPoint(x: 0, y: style.highlightYOffset)
            : CGPoint(x: -style.highlightYOffset, y: 0)
        topHighlight.zPosition = 0.1
        beam.addChild(topHighlight)

        let glossPatch = SKShapeNode(
            ellipseOf: isHorizontal
                ? CGSize(width: max(28, majorLength * 0.34), height: max(8, minorThickness * 0.30))
                : CGSize(width: max(8, minorThickness * 0.30), height: max(28, majorLength * 0.34))
        )
        glossPatch.fillColor = Theme.beamGloss
        glossPatch.strokeColor = .clear
        glossPatch.position = isHorizontal
            ? CGPoint(x: -majorLength * 0.12, y: minorThickness * 0.08)
            : CGPoint(x: -minorThickness * 0.02, y: majorLength * 0.12)
        glossPatch.zPosition = 0.11
        beam.addChild(glossPatch)

        let centerGrain = decorativeLine(
            from: isHorizontal
                ? CGPoint(x: -majorLength * 0.34, y: style.primaryGrainYOffset)
                : CGPoint(x: style.primaryGrainYOffset, y: -majorLength * 0.34),
            to: isHorizontal
                ? CGPoint(x: majorLength * 0.34, y: style.primaryGrainYOffset)
                : CGPoint(x: style.primaryGrainYOffset, y: majorLength * 0.34),
            strokeColor: Theme.beamGrain,
            lineWidth: 1.4
        )
        centerGrain.zPosition = 0.15
        beam.addChild(centerGrain)

        if majorLength > 180 {
            let secondaryGrain = decorativeLine(
                from: isHorizontal
                    ? CGPoint(x: -majorLength * 0.22, y: style.secondaryGrainYOffset)
                    : CGPoint(x: style.secondaryGrainYOffset, y: -majorLength * 0.22),
                to: isHorizontal
                    ? CGPoint(x: majorLength * 0.18, y: style.secondaryGrainYOffset)
                    : CGPoint(x: style.secondaryGrainYOffset, y: majorLength * 0.18),
                strokeColor: Theme.beamGrain.withAlphaComponent(0.72),
                lineWidth: 1.1
            )
            secondaryGrain.zPosition = 0.15
            beam.addChild(secondaryGrain)
        }

        for seamPosition in seamPositions(for: majorLength, bias: style.seamBias) {
            let seam = decorativeLine(
                from: isHorizontal
                    ? CGPoint(x: seamPosition, y: -minorThickness * 0.26)
                    : CGPoint(x: -minorThickness * 0.26, y: seamPosition),
                to: isHorizontal
                    ? CGPoint(x: seamPosition, y: minorThickness * 0.22)
                    : CGPoint(x: minorThickness * 0.22, y: seamPosition),
                strokeColor: Theme.beamGrain,
                lineWidth: 1.5
            )
            seam.zPosition = 0.15
            beam.addChild(seam)
        }

        let lowerEdgeShade = decorativeLine(
            from: isHorizontal
                ? CGPoint(x: -majorLength * 0.42, y: -minorThickness * 0.26)
                : CGPoint(x: minorThickness * 0.26, y: -majorLength * 0.42),
            to: isHorizontal
                ? CGPoint(x: majorLength * 0.42, y: -minorThickness * 0.26)
                : CGPoint(x: minorThickness * 0.26, y: majorLength * 0.42),
            strokeColor: Theme.beamEdgeShade.withAlphaComponent(0.94),
            lineWidth: 1.3
        )
        lowerEdgeShade.zPosition = 0.14
        beam.addChild(lowerEdgeShade)

        let upperEdgeHighlight = decorativeLine(
            from: isHorizontal
                ? CGPoint(x: -majorLength * 0.40, y: minorThickness * 0.22)
                : CGPoint(x: -minorThickness * 0.22, y: -majorLength * 0.40),
            to: isHorizontal
                ? CGPoint(x: majorLength * 0.40, y: minorThickness * 0.22)
                : CGPoint(x: -minorThickness * 0.22, y: majorLength * 0.40),
            strokeColor: Theme.beamHighlight.withAlphaComponent(0.16),
            lineWidth: 1.0
        )
        upperEdgeHighlight.zPosition = 0.14
        beam.addChild(upperEdgeHighlight)

        addChild(beam)
    }

    private func addWallCornerCaps(for wallRects: [CGRect]) {
        var seenCenters: Set<String> = []

        for horizontalWall in wallRects where horizontalWall.width >= horizontalWall.height {
            for verticalWall in wallRects where verticalWall.height > verticalWall.width {
                let overlap = horizontalWall.intersection(verticalWall)
                guard !overlap.isNull, overlap.width > 4, overlap.height > 4 else { continue }

                let center = CGPoint(x: overlap.midX, y: overlap.midY)
                let key = "\(Int(center.x.rounded())):\(Int(center.y.rounded()))"
                guard seenCenters.insert(key).inserted else { continue }

                let radius = max(12, min(overlap.width, overlap.height) * 0.62)
                let shadow = SKShapeNode(circleOfRadius: radius * 0.96)
                shadow.fillColor = Theme.beamShadow.withAlphaComponent(0.9)
                shadow.strokeColor = .clear
                shadow.position = CGPoint(x: center.x + 1.4, y: center.y - 2.0)
                shadow.zPosition = 1.79
                addChild(shadow)

                let cap = SKShapeNode(circleOfRadius: radius)
                cap.fillColor = Theme.beamTop
                cap.strokeColor = Theme.beamStroke
                cap.lineWidth = 2.2
                cap.position = center
                cap.zPosition = 2.04
                addChild(cap)

                let inset = SKShapeNode(circleOfRadius: radius * 0.74)
                inset.fillColor = .clear
                inset.strokeColor = Theme.beamInsetStroke
                inset.lineWidth = 0.9
                inset.zPosition = 0.11
                cap.addChild(inset)

                let highlight = SKShapeNode(ellipseOf: CGSize(width: radius * 1.28, height: radius * 0.44))
                highlight.fillColor = Theme.beamHighlight.withAlphaComponent(0.14)
                highlight.strokeColor = .clear
                highlight.position = CGPoint(x: -radius * 0.10, y: radius * 0.22)
                highlight.zPosition = 0.12
                cap.addChild(highlight)
            }
        }
    }

    private func addWhirlpool(at center: CGPoint) {
        let shadow = SKShapeNode(circleOfRadius: board.holeRadius * 1.18)
        shadow.fillColor = Theme.holeShadow
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: center.x, y: center.y - 2)
        shadow.zPosition = 1.74
        addChild(shadow)

        let surfaceRing = SKShapeNode(circleOfRadius: board.holeRadius * 1.28)
        surfaceRing.fillColor = .clear
        surfaceRing.strokeColor = Theme.holeSurfaceRing
        surfaceRing.lineWidth = 1.5
        surfaceRing.position = center
        surfaceRing.zPosition = 1.76
        addChild(surfaceRing)

        let glow = SKShapeNode(circleOfRadius: board.holeRadius * 1.14)
        glow.fillColor = Theme.holeGlow
        glow.strokeColor = .clear
        glow.position = center
        glow.zPosition = 1.78
        addChild(glow)

        let outerPool = SKShapeNode(circleOfRadius: board.holeRadius * 1.10)
        outerPool.fillColor = Theme.holeOuterFill.withAlphaComponent(0.82)
        outerPool.strokeColor = Theme.holeRimStroke.withAlphaComponent(0.82)
        outerPool.lineWidth = 2.2
        outerPool.position = center
        outerPool.zPosition = 1.82
        addChild(outerPool)

        let foamRing = SKShapeNode(circleOfRadius: board.holeRadius * 0.94)
        foamRing.fillColor = .clear
        foamRing.strokeColor = Theme.holeFoam.withAlphaComponent(0.42)
        foamRing.lineWidth = 1.2
        foamRing.position = center
        foamRing.zPosition = 1.84
        addChild(foamRing)

        let hole = SKShapeNode(circleOfRadius: board.holeRadius * 0.86)
        hole.fillColor = Theme.holeMidFill
        hole.strokeColor = .clear
        hole.position = center
        hole.zPosition = 1.88
        hole.physicsBody = SKPhysicsBody(circleOfRadius: board.holeRadius * 0.82)
        hole.physicsBody?.isDynamic = false
        hole.physicsBody?.categoryBitMask = PhysicsCategory.hole
        hole.physicsBody?.collisionBitMask = 0
        hole.physicsBody?.contactTestBitMask = PhysicsCategory.marble
        addChild(hole)

        let core = SKShapeNode(circleOfRadius: board.holeRadius * 0.52)
        core.fillColor = Theme.holeCoreFill
        core.strokeColor = .clear
        core.zPosition = 0.1
        hole.addChild(core)

        let largeSwirl = SKShapeNode(path: whirlpoolArcPath(radius: board.holeRadius * 0.66, startAngle: -0.2, endAngle: 4.4))
        largeSwirl.strokeColor = Theme.holeFoam
        largeSwirl.lineWidth = 2.1
        largeSwirl.lineCap = .round
        largeSwirl.fillColor = .clear
        largeSwirl.zPosition = 0.2
        hole.addChild(largeSwirl)

        let smallSwirl = SKShapeNode(path: whirlpoolArcPath(radius: board.holeRadius * 0.40, startAngle: 0.8, endAngle: 5.4))
        smallSwirl.strokeColor = Theme.holeFoam.withAlphaComponent(0.72)
        smallSwirl.lineWidth = 1.6
        smallSwirl.lineCap = .round
        smallSwirl.fillColor = .clear
        smallSwirl.zPosition = 0.25
        hole.addChild(smallSwirl)

        let foamDot = SKShapeNode(circleOfRadius: board.holeRadius * 0.10)
        foamDot.fillColor = Theme.holeFoam.withAlphaComponent(0.72)
        foamDot.strokeColor = .clear
        foamDot.position = CGPoint(x: -board.holeRadius * 0.20, y: board.holeRadius * 0.18)
        foamDot.zPosition = 0.3
        hole.addChild(foamDot)
    }

    private func boardLabel(text: String, fontSize: CGFloat) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = fontSize
        label.fontColor = Theme.labelColor.withAlphaComponent(0.84)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        return label
    }

    private func decorativeLine(from start: CGPoint, to end: CGPoint, strokeColor: UIColor, lineWidth: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)

        let line = SKShapeNode(path: path)
        line.strokeColor = strokeColor
        line.lineWidth = lineWidth
        line.lineCap = .round
        line.fillColor = .clear
        return line
    }

    private func pennantPath(size: CGSize) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: size.width, y: size.height * 0.28))
        path.addLine(to: CGPoint(x: 0, y: size.height * 0.56))
        path.closeSubpath()
        return path
    }

    private func starPath(radius: CGFloat, points: Int, innerRatio: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let innerRadius = radius * innerRatio
        let step = CGFloat.pi / CGFloat(points)
        let startAngle = -CGFloat.pi / 2

        for index in 0..<(points * 2) {
            let currentRadius = index.isMultiple(of: 2) ? radius : innerRadius
            let angle = startAngle + step * CGFloat(index)
            let point = CGPoint(
                x: cos(angle) * currentRadius,
                y: sin(angle) * currentRadius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.closeSubpath()
        return path
    }

    private func beamVisualStyle(for wallRect: CGRect) -> BeamVisualStyle {
        let seed = abs(Int(wallRect.midX.rounded()) * 31 + Int(wallRect.midY.rounded()) * 17)
        let unit = CGFloat(seed % 97) / 96
        let majorLength = max(wallRect.width, wallRect.height)
        let minorThickness = min(wallRect.width, wallRect.height)

        return BeamVisualStyle(
            cornerRadius: max(10, minorThickness * (0.34 + unit * 0.06)),
            shadowYOffset: -(4.2 + unit * 1.6),
            highlightInset: max(18, majorLength * (0.10 + unit * 0.04)),
            highlightYOffset: minorThickness * (0.10 + unit * 0.05),
            highlightAlpha: 0.12 + unit * 0.08,
            primaryGrainYOffset: (-minorThickness * 0.08) + (unit * minorThickness * 0.10),
            secondaryGrainYOffset: minorThickness * (-0.01 + unit * 0.08),
            seamBias: (unit - 0.5) * majorLength * 0.05
        )
    }

    private func seamPositions(for width: CGFloat, bias: CGFloat) -> [CGFloat] {
        let positions: [CGFloat]

        if width > 520 {
            positions = [-width * 0.23, 0, width * 0.23]
        } else if width > 220 {
            positions = [-width * 0.18, width * 0.18]
        } else {
            positions = [0]
        }

        let maxShift = width * 0.08
        let clampedBias = max(-maxShift, min(maxShift, bias))
        return positions.map { $0 + clampedBias }
    }

    private func whirlpoolArcPath(radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> CGPath {
        UIBezierPath(
            arcCenter: .zero,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        ).cgPath
    }

    private func waterGradientTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            if let radialGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    Theme.waterCenter.cgColor,
                    Theme.waterMid.cgColor,
                    Theme.waterEdge.cgColor,
                    Theme.waterEdgeDeep.cgColor
                ] as CFArray,
                locations: [0.0, 0.42, 0.80, 1.0]
            ) {
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.56)
                let radius = max(size.width, size.height) * 0.70
                cg.drawRadialGradient(
                    radialGradient,
                    startCenter: center,
                    startRadius: 0,
                    endCenter: center,
                    endRadius: radius,
                    options: [.drawsAfterEndLocation]
                )
            }

            if let sheenGradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [
                    UIColor.white.withAlphaComponent(0.10).cgColor,
                    UIColor.white.withAlphaComponent(0.03).cgColor,
                    UIColor.clear.cgColor
                ] as CFArray,
                locations: [0.0, 0.42, 1.0]
            ) {
                cg.drawLinearGradient(
                    sheenGradient,
                    start: CGPoint(x: size.width * 0.18, y: size.height * 0.88),
                    end: CGPoint(x: size.width * 0.84, y: size.height * 0.14),
                    options: []
                )
            }
        }

        return SKTexture(image: image)
    }
}
