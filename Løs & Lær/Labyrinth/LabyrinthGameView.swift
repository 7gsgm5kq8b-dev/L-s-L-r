import SwiftUI
import AVFoundation
import UIKit

// Global speech synthesizer
let synthesizer = AVSpeechSynthesizer()

// MARK: - River Models
struct RiverSegment {
    let start: CGPoint
    let control: CGPoint
    let end: CGPoint
}

struct River {
    var segments: [RiverSegment]
}

struct Labyrinth {
    var mainRiver: River
    var sideRivers: [River]
    var goalPositions: [CGRect]
}

// MARK: - Helpers til målplacering
func goalRect(from endPoint: CGPoint) -> CGRect {
    // Sørg for at rect er centreret omkring endPoint
    let w: CGFloat = 40
    let h: CGFloat = 40
    return CGRect(x: endPoint.x - w / 2, y: endPoint.y - h / 2, width: w, height: h)
}


// MARK: - Seedable RNG (SplitMix64)
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Randomiseret Labyrinth (V9.2 – kompakt maze for alder 4-7)
func generateRandomLabyrinth(seed: UInt64? = nil, internalDifficulty: Difficulty = .easy) -> Labyrinth {
    var rng = seed.map { SeededGenerator(seed: $0) } ?? SeededGenerator(seed: UInt64(Date().timeIntervalSince1970))

    let leftBound: CGFloat = 222
    let rightBound: CGFloat = 770
    let bottomY: CGFloat = 1265
    let topYMin: CGFloat = 410

    let mazeMinX: CGFloat = leftBound + 48
    let mazeMaxX: CGFloat = rightBound - 48
    let mazeMinY: CGFloat = topYMin + 55
    let mazeMaxY: CGFloat = bottomY - 75

    let cols = internalDifficulty == .hard ? 6 : 5
    let rows = internalDifficulty == .hard ? 7 : 6

    let regionWidth = mazeMaxX - mazeMinX
    let regionHeight = mazeMaxY - mazeMinY
    let cellStepX = regionWidth / CGFloat(cols - 1)
    let cellStepY = regionHeight / CGFloat(rows - 1)

    let minSegmentLength = max(58.0, min(cellStepX, cellStepY) * 0.68)
    let maxSegmentLength = max(cellStepX, cellStepY) * 1.20

    let maxStraightRun = internalDifficulty == .hard ? 3 : 2
    let turnBias: CGFloat = 0.62
    let extraDeadEndCount = internalDifficulty == .hard ? 2 : 1

    struct EdgeKey: Hashable {
        let a: Int
        let b: Int

        init(_ x: Int, _ y: Int) {
            if x < y { a = x; b = y } else { a = y; b = x }
        }
    }

    enum Dir: Int {
        case up, down, left, right
    }

    struct NeighborInfo {
        let node: Int
        let dir: Dir
    }

    struct LeafInfo {
        let node: Int
        let point: CGPoint
        let decisionDepth: Int
        let distanceFromStart: Int
    }

    func rand(_ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &rng)
    }

    func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    func distance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y)
    }

    func uniquePoints(_ input: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        var result: [CGPoint] = []
        for point in input {
            if result.allSatisfy({ distance($0, point) >= minDistance }) {
                result.append(point)
            }
        }
        return result
    }

    func gridIndex(row: Int, col: Int) -> Int {
        row * cols + col
    }

    func gridRowCol(for index: Int) -> (row: Int, col: Int) {
        (index / cols, index % cols)
    }

    // MARK: 1) Node field across bounded maze region
    var points: [CGPoint] = Array(repeating: .zero, count: rows * cols)
    let jitterX = cellStepX * 0.10
    let jitterY = cellStepY * 0.10

    for row in 0..<rows {
        for col in 0..<cols {
            let idx = gridIndex(row: row, col: col)
            let baseX = mazeMinX + CGFloat(col) * cellStepX
            let baseY = mazeMinY + CGFloat(row) * cellStepY

            let jx = (col == 0 || col == cols - 1) ? 0 : rand(-jitterX...jitterX)
            let jy = (row == 0 || row == rows - 1) ? 0 : rand(-jitterY...jitterY)

            points[idx] = CGPoint(
                x: clamp(baseX + jx, to: mazeMinX...mazeMaxX),
                y: clamp(baseY + jy, to: mazeMinY...mazeMaxY)
            )
        }
    }

    let startCol = cols / 2
    let startNode = gridIndex(row: rows - 1, col: startCol)
    points[startNode] = CGPoint(x: mazeMinX + CGFloat(startCol) * cellStepX, y: mazeMaxY)

    func gridNeighbors(of node: Int) -> [NeighborInfo] {
        let rc = gridRowCol(for: node)
        var neighbors: [NeighborInfo] = []

        if rc.row > 0 { neighbors.append(NeighborInfo(node: gridIndex(row: rc.row - 1, col: rc.col), dir: .up)) }
        if rc.row < rows - 1 { neighbors.append(NeighborInfo(node: gridIndex(row: rc.row + 1, col: rc.col), dir: .down)) }
        if rc.col > 0 { neighbors.append(NeighborInfo(node: gridIndex(row: rc.row, col: rc.col - 1), dir: .left)) }
        if rc.col < cols - 1 { neighbors.append(NeighborInfo(node: gridIndex(row: rc.row, col: rc.col + 1), dir: .right)) }

        neighbors.shuffle(using: &rng)
        return neighbors
    }

    // MARK: 2) Recursive backtracker with straight-run limiter
    var visited: Set<Int> = [startNode]
    var stack: [Int] = [startNode]
    var parent: [Int: Int] = [:]
    var dirFromParent: [Int: Dir] = [:]
    var straightRun: [Int: Int] = [startNode: 0]
    var edges: [EdgeKey] = []

    while let current = stack.last {
        var options = gridNeighbors(of: current).filter { !visited.contains($0.node) }

        if options.isEmpty {
            stack.removeLast()
            continue
        }

        let prevDir = dirFromParent[current]
        let prevRun = straightRun[current] ?? 0

        if let prevDir {
            if prevRun >= maxStraightRun {
                let turned = options.filter { $0.dir != prevDir }
                if !turned.isEmpty {
                    options = turned
                }
            } else if rand(0...1) < turnBias {
                let turned = options.filter { $0.dir != prevDir }
                if !turned.isEmpty {
                    options = turned
                }
            }
        }

        guard let chosen = options.randomElement(using: &rng) else {
            stack.removeLast()
            continue
        }

        visited.insert(chosen.node)
        parent[chosen.node] = current
        dirFromParent[chosen.node] = chosen.dir
        straightRun[chosen.node] = (prevDir == chosen.dir) ? (prevRun + 1) : 1

        edges.append(EdgeKey(current, chosen.node))
        stack.append(chosen.node)
    }

    func adjacency(from edgeList: [EdgeKey], nodeCount: Int) -> [Int: Set<Int>] {
        var adj: [Int: Set<Int>] = [:]
        for node in 0..<nodeCount { adj[node] = [] }
        for edge in edgeList {
            adj[edge.a, default: []].insert(edge.b)
            adj[edge.b, default: []].insert(edge.a)
        }
        return adj
    }

    var adj = adjacency(from: edges, nodeCount: points.count)

    func leafNodes(in graph: [Int: Set<Int>]) -> [Int] {
        graph.keys.filter { node in
            node != startNode && (graph[node]?.count ?? 0) == 1
        }
    }

    // MARK: 3) Add short internal dead-end stubs
    var usedDeadEndAnchors: Set<Int> = []
    var deadEndAdded = 0
    var deadEndAttempts = 0

    while deadEndAdded < extraDeadEndCount && deadEndAttempts < 24 {
        let anchors = adj.keys.filter { node in
            let degree = adj[node]?.count ?? 0
            return degree >= 2 && degree <= 3 && node != startNode && !usedDeadEndAnchors.contains(node)
        }

        guard let anchor = anchors.randomElement(using: &rng) else { break }
        usedDeadEndAnchors.insert(anchor)
        deadEndAttempts += 1

        let anchorPoint = points[anchor]
        let outward: CGFloat = anchorPoint.x >= points[startNode].x ? 1 : -1
        let branchLen = min(cellStepX, cellStepY) * rand(0.55...0.82)

        let candidateDirs: [CGPoint] = [
            CGPoint(x: outward, y: -0.45),
            CGPoint(x: outward, y: 0),
            CGPoint(x: -outward, y: -0.45),
            CGPoint(x: 0, y: -1)
        ]

        var added = false
        for dir in candidateDirs.shuffled(using: &rng) {
            let np = CGPoint(
                x: clamp(anchorPoint.x + dir.x * branchLen, to: mazeMinX...mazeMaxX),
                y: clamp(anchorPoint.y + dir.y * branchLen, to: mazeMinY...mazeMaxY)
            )

            if distance(anchorPoint, np) < minSegmentLength * 0.72 { continue }
            if points.contains(where: { distance($0, np) < minSegmentLength * 0.50 }) { continue }

            let newNode = points.count
            points.append(np)
            edges.append(EdgeKey(anchor, newNode))
            adj[anchor, default: []].insert(newNode)
            adj[newNode, default: []].insert(anchor)

            deadEndAdded += 1
            added = true
            break
        }

        if !added { continue }
    }

    // If still too few leaves, add emergency stubs
    var emergency = 0
    while leafNodes(in: adj).count < 3 && emergency < 8 {
        let anchors = adj.keys.filter { (adj[$0]?.count ?? 0) >= 2 && $0 != startNode }
        guard let anchor = anchors.randomElement(using: &rng) else { break }

        let ap = points[anchor]
        let dir: CGFloat = ap.x >= points[startNode].x ? 1 : -1
        let np = CGPoint(
            x: clamp(ap.x + dir * minSegmentLength * 0.75, to: mazeMinX...mazeMaxX),
            y: clamp(ap.y - minSegmentLength * 0.62, to: mazeMinY...mazeMaxY)
        )

        if points.contains(where: { distance($0, np) < minSegmentLength * 0.45 }) {
            emergency += 1
            continue
        }

        let newNode = points.count
        points.append(np)
        edges.append(EdgeKey(anchor, newNode))
        adj[anchor, default: []].insert(newNode)
        adj[newNode, default: []].insert(anchor)
        emergency += 1
    }

    // Rebuild parent/depth on final graph
    func bfsParents(from start: Int, graph: [Int: Set<Int>]) -> (dist: [Int: Int], parent: [Int: Int]) {
        var dist: [Int: Int] = [start: 0]
        var parent: [Int: Int] = [:]
        var queue: [Int] = [start]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            let base = dist[current] ?? 0
            for next in graph[current] ?? [] where dist[next] == nil {
                dist[next] = base + 1
                parent[next] = current
                queue.append(next)
            }
        }

        return (dist, parent)
    }

    let bfs = bfsParents(from: startNode, graph: adj)
    let distFromStart = bfs.dist
    let finalParent = bfs.parent

    func decisionDepth(of node: Int) -> Int {
        var depth = 0
        var current = node

        while let p = finalParent[current] {
            if p != startNode, (adj[p]?.count ?? 0) >= 3 {
                depth += 1
            }
            current = p
        }

        return depth
    }

    let leaves = leafNodes(in: adj).map { node in
        LeafInfo(
            node: node,
            point: points[node],
            decisionDepth: decisionDepth(of: node),
            distanceFromStart: distFromStart[node] ?? 0
        )
    }

    // MARK: 4) Build mainRiver path from start to farthest endpoint
    let farthestNode = (distFromStart.max { $0.value < $1.value }?.key) ?? startNode

    var mainPathNodes: [Int] = [farthestNode]
    var walk = farthestNode
    while let p = finalParent[walk] {
        mainPathNodes.append(p)
        walk = p
    }
    mainPathNodes.reverse()

    let mainPathEdgeSet = Set(zip(mainPathNodes, mainPathNodes.dropFirst()).map { EdgeKey($0.0, $0.1) })

    func controlPoint(from a: CGPoint, to b: CGPoint, intensity: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let len = max(1, hypot(dx, dy))
        let nx = -dy / len
        let ny = dx / len
        let offset = rand(-intensity...intensity)

        return CGPoint(
            x: clamp(mid.x + nx * offset, to: mazeMinX...mazeMaxX),
            y: clamp(mid.y + ny * offset + rand(-5...5), to: mazeMinY...mazeMaxY)
        )
    }

    func appendSegmentPieces(from a: CGPoint, to b: CGPoint, jitter: CGFloat, into segments: inout [RiverSegment]) {
        let total = distance(a, b)
        let splitsByMax = max(1, Int(ceil(total / maxSegmentLength)))
        let maxSplitsByMin = max(1, Int(floor(total / minSegmentLength)))
        let splitCount = max(1, min(splitsByMax, maxSplitsByMin))

        var prev = a
        for i in 1...splitCount {
            let t = CGFloat(i) / CGFloat(splitCount)
            var next = CGPoint(
                x: a.x + (b.x - a.x) * t,
                y: a.y + (b.y - a.y) * t
            )

            if i < splitCount {
                let dx = b.x - a.x
                let dy = b.y - a.y
                let len = max(1, hypot(dx, dy))
                let nx = -dy / len
                let ny = dx / len
                let wobble = rand(-8...8)
                next.x = clamp(next.x + nx * wobble, to: mazeMinX...mazeMaxX)
                next.y = clamp(next.y + ny * wobble + rand(-4...4), to: mazeMinY...mazeMaxY)
            }

            segments.append(RiverSegment(start: prev, control: controlPoint(from: prev, to: next, intensity: jitter), end: next))
            prev = next
        }
    }

    func segmentsFromNodePath(_ nodePath: [Int], jitter: CGFloat) -> [RiverSegment] {
        guard nodePath.count >= 2 else { return [] }
        var segments: [RiverSegment] = []
        for (fromNode, toNode) in zip(nodePath, nodePath.dropFirst()) {
            appendSegmentPieces(from: points[fromNode], to: points[toNode], jitter: jitter, into: &segments)
        }
        return segments
    }

    let mainSegments = segmentsFromNodePath(mainPathNodes, jitter: 10)

    // MARK: 5) Convert remaining maze edges to side rivers
    let mainPathNodeSet = Set(mainPathNodes)
    var consumedNonMainEdges: Set<EdgeKey> = []
    var sideRivers: [River] = []

    let chainStartCandidates = adj.keys.sorted().filter { node in
        mainPathNodeSet.contains(node) || (adj[node]?.count ?? 0) != 2
    }

    for chainStart in chainStartCandidates {
        for neighbor in adj[chainStart] ?? [] {
            let firstEdge = EdgeKey(chainStart, neighbor)
            if mainPathEdgeSet.contains(firstEdge) || consumedNonMainEdges.contains(firstEdge) {
                continue
            }

            var chain: [Int] = [chainStart, neighbor]
            consumedNonMainEdges.insert(firstEdge)

            var prev = chainStart
            var current = neighbor

            while !mainPathNodeSet.contains(current), (adj[current]?.count ?? 0) == 2 {
                guard let next = (adj[current] ?? []).first(where: { $0 != prev }) else { break }
                let nextEdge = EdgeKey(current, next)
                if mainPathEdgeSet.contains(nextEdge) || consumedNonMainEdges.contains(nextEdge) {
                    break
                }

                chain.append(next)
                consumedNonMainEdges.insert(nextEdge)
                prev = current
                current = next
            }

            let riverSegments = segmentsFromNodePath(chain, jitter: 9)
            if !riverSegments.isEmpty {
                sideRivers.append(River(segments: riverSegments))
            }
        }
    }

    // MARK: 6) Endpoint selection (terminal endpoints, spaced, depth-aware)
    func pickLeaves(_ candidates: [LeafInfo], count: Int, already: [CGPoint]) -> [CGPoint] {
        var picked: [CGPoint] = []
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.decisionDepth == rhs.decisionDepth {
                return lhs.distanceFromStart > rhs.distanceFromStart
            }
            return lhs.decisionDepth > rhs.decisionDepth
        }

        for leaf in sorted {
            if picked.count >= count { break }
            let p = leaf.point
            if (already + picked).allSatisfy({ distance($0, p) >= 68 }) {
                picked.append(p)
            }
        }

        return picked
    }

    let deepLeaves = leaves.filter { $0.decisionDepth >= 2 }

    var selectedGoalPoints: [CGPoint] = []
    selectedGoalPoints += pickLeaves(deepLeaves, count: min(2, deepLeaves.count), already: selectedGoalPoints)

    if selectedGoalPoints.count < 3 {
        selectedGoalPoints += pickLeaves(leaves, count: 3 - selectedGoalPoints.count, already: selectedGoalPoints)
    }

    if selectedGoalPoints.count < 3 {
        let fallbackLeafPoints = uniquePoints(leaves.map { $0.point }, minDistance: 52)
        for p in fallbackLeafPoints where selectedGoalPoints.count < 3 {
            if selectedGoalPoints.allSatisfy({ distance($0, p) >= 45 }) {
                selectedGoalPoints.append(p)
            }
        }
    }

    while selectedGoalPoints.count < 3 {
        selectedGoalPoints.append(points[farthestNode])
    }

    selectedGoalPoints = Array(selectedGoalPoints.prefix(3))
    let goalPositions = selectedGoalPoints.map { goalRect(from: $0) }

    return Labyrinth(
        mainRiver: River(segments: mainSegments),
        sideRivers: sideRivers,
        goalPositions: goalPositions
    )
}
// MARK: - GameMode
enum GameMode {
    case letters
    case math
    case words
}

enum Difficulty {
    case easy
    case hard
}


// MARK: - ContentView
struct LabyrinthGameView: View {
    let difficulty: Difficulty          // kommer udefra
    let randomizeInternalModes: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void
    let startImmediately: Bool

    @State private var internalDifficulty: Difficulty

    @EnvironmentObject var session: GameSessionManager

    
    init(
        difficulty: Difficulty,
        randomizeInternalModes: Bool,
        startImmediately: Bool = false,
        initialMode: GameMode? = nil,
        onExit: @escaping () -> Void,
        onBackToHub: @escaping () -> Void
    ) {
        self.difficulty = difficulty
        self.randomizeInternalModes = randomizeInternalModes
        self.onExit = onExit
        self.onBackToHub = onBackToHub
        self.startImmediately = startImmediately

        _internalDifficulty = State(initialValue: difficulty)
        _gameStarted       = State(initialValue: startImmediately)

        if let mode = initialMode {
            _gameMode = State(initialValue: mode)   // ← VIGTIG LINJE
        }

        preloadVoice()
    }

    private func nextInternalMode() {
        switch gameMode {
        case .letters:
            gameMode = .math
        case .math:
            gameMode = .words
        case .words:
            gameMode = .letters
        }
    }
    
    private func introText(for mode: GameMode) -> String {
        switch mode {
        case .letters:
            return "Hjælp båden med at finde det rigtige bogstav!\nFølg floden langs stierne og vælg rigtigt."
        case .math:
            return "Hjælp båden med at finde det rigtige resultat!\nFølg floden langs stierne og vælg rigtigt."
        case .words:
            return "Hjælp båden med at finde det rigtige ord!\nFølg floden langs stierne og vælg rigtigt."
        }
    }
    
    private func introAIFile(for mode: GameMode) -> String {
        switch mode {
        case .letters: return "labyrinth_intro_letters"
        case .math:    return "labyrinth_intro_math"
        case .words:   return "labyrinth_intro_words"
        }
    }
    
    private func speakIntro() {
        AudioVoiceManager.shared.debugLogging = false
        let file = introAIFile(for: gameMode)
        AudioVoiceManager.shared.speakWithFallback(aiFile: file) {
            // fallback TTS hvis fil mangler
            speak(" \(introText(for: gameMode))")
        }
    }
    
    // MARK: - Canvas reference size
    private let canvasWidth: CGFloat = 900
    private let canvasHeight: CGFloat = 1300

    // MARK: - Game transform
    private let gameOffsetX: CGFloat = -110
    private let gameOffsetY: CGFloat = -110
    private let gameScaleMultiplier: CGFloat = 1.25

    // MARK: - State
    @State private var position = CGPoint(x: 450, y: 1248)
    @State private var showErrorFlash = false
    @State private var showSuccessMessage = false
    @State private var gameStarted = false
    @State private var helpMode = false
    @State private var bounce = false
    @State private var debugMode = false
    @State private var useUppercase = true
    @State private var lastDragPoint: CGPoint? = nil
    @State private var score: Int = 0
    @State private var gameMode: GameMode = .letters

    // Word-mode state
    @State private var currentWord: String = ""
    @State private var remainingLetters: [Character] = []
    @State private var solvedLettersCount: Int = 0

    // Math-mode state (til hjælp/visning)
    @State private var currentMathQuestion: String? = nil
    @State private var useMinus: Bool = false   // ⭐ NY LINJE til at styre +/-
    
    // Gem sidste bådposition (canvas coords) for at undgå at placere mål ovenpå båden
    @State private var lastBoatPosition: CGPoint? = nil

    //Pling lyd
    @State private var audioPlayer: AVAudioPlayer?
    
    @State private var introPlayed: Bool = false
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }



    // MARK: - Labyrinth & Goals
    let availableLetters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
   
    let easyWords: [String] = [
        "må", "ko", "bi", "nu", "gå", "på", "ny", "et", "to", "sy",
        "se", "få", "vi", "du", "bo"
    ]

    let hardWords: [String] = [
        "kat", "hund", "får", "bog", "glas", "sol", "hus", "bil", "grib",
        "bold", "sæl", "gren", "løve", "abe", "fisk"
    ]

    @State private var randomizedGoals: [(label: String, rect: CGRect)] = []
    @State private var targetLetter: String? = nil
    @State private var labyrinth: Labyrinth = generateRandomLabyrinth()


    // MARK: - Helper: sæt bådens startposition ud fra labyrintens main river start
    private func setBoatToMainStart() {
        if let firstSegment = labyrinth.mainRiver.segments.first {
            position = firstSegment.start
        } else {
            position = CGPoint(x: canvasWidth / 2, y: canvasHeight - 50)
        }
    }

    // MARK: - Helper: clamp et centerpunkt indenfor bounds (så målet ikke flytter sig væk fra floden)
    private func clampGoalCenter(_ center: CGPoint, radius: CGFloat = 20) -> CGPoint {
        let minX: CGFloat = 222 + radius
        let maxX: CGFloat = 770 - radius
        let minY: CGFloat = 410 + radius
        let maxY: CGFloat = 1265 - radius
        let cx = min(max(minX, center.x), maxX)
        let cy = min(max(minY, center.y), maxY)
        return CGPoint(x: cx, y: cy)
    }

    // MARK: - Helper: lav en mål-rect ud fra et centerpunkt (holder mål centreret på flodens endepunkt)
    private func goalRectCentered(at center: CGPoint, size: CGSize = CGSize(width: 40, height: 40)) -> CGRect {
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        return CGRect(origin: origin, size: size)
    }


    private struct GoalNodeKey: Hashable {
        let x: Int
        let y: Int
    }

    private func goalNodeKey(_ point: CGPoint) -> GoalNodeKey {
        GoalNodeKey(
            x: Int((point.x * 10).rounded()),
            y: Int((point.y * 10).rounded())
        )
    }

    private func goalDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func uniqueGoalPoints(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        var unique: [CGPoint] = []
        for point in points {
            if unique.allSatisfy({ goalDistance($0, point) >= minDistance }) {
                unique.append(point)
            }
        }
        return unique
    }

    // MARK: - Helper: vælg op til `count` endepunkter med afstand + separation
    private func pickDistinctGoalEnds(from candidates: [CGPoint], count: Int = 3, minDistance: CGFloat = 60) -> [CGPoint] {
        guard count > 0 else { return [] }

        let startPoint = labyrinth.mainRiver.segments.first?.start ?? CGPoint(x: 450, y: 1248)
        var pool = uniqueGoalPoints(candidates, minDistance: minDistance * 0.55)
        var selected: [CGPoint] = []

        func score(_ point: CGPoint, selected: [CGPoint]) -> CGFloat {
            let distFromStart = goalDistance(point, startPoint)
            let separation = selected.isEmpty ? 200 : (selected.map { goalDistance(point, $0) }.min() ?? 0)
            return distFromStart + (separation * 1.3)
        }

        while selected.count < count && !pool.isEmpty {
            let bestIndex = pool.indices.max { lhs, rhs in
                score(pool[lhs], selected: selected) < score(pool[rhs], selected: selected)
            } ?? pool.startIndex

            let candidate = pool.remove(at: bestIndex)
            if selected.allSatisfy({ goalDistance($0, candidate) >= minDistance }) {
                selected.append(candidate)
            }
        }

        return selected
    }

    // MARK: - Helper: terminale endpoints (degree == 1), ekskl. start
    private func terminalGoalEndpoints() -> [CGPoint] {
        var degrees: [GoalNodeKey: Int] = [:]
        var representativePoints: [GoalNodeKey: CGPoint] = [:]

        func addEdge(_ a: CGPoint, _ b: CGPoint) {
            let ka = goalNodeKey(a)
            let kb = goalNodeKey(b)
            degrees[ka, default: 0] += 1
            degrees[kb, default: 0] += 1
            representativePoints[ka] = a
            representativePoints[kb] = b
        }

        for segment in labyrinth.mainRiver.segments {
            addEdge(segment.start, segment.end)
        }

        for river in labyrinth.sideRivers {
            for segment in river.segments {
                addEdge(segment.start, segment.end)
            }
        }

        let startKey = labyrinth.mainRiver.segments.first.map { goalNodeKey($0.start) }

        var leaves: [CGPoint] = []
        for (key, degree) in degrees where degree == 1 {
            if key == startKey { continue }
            if let p = representativePoints[key] {
                leaves.append(p)
            }
        }

        let deduped = uniqueGoalPoints(leaves, minDistance: 52)
        let startPoint = labyrinth.mainRiver.segments.first?.start ?? CGPoint(x: 450, y: 1248)
        return deduped.sorted { goalDistance($0, startPoint) > goalDistance($1, startPoint) }
    }

    // MARK: - Helper: foretrukne mål-ends (leaf-prioritet)
    private func preferredGoalEndpoints(count: Int = 3) -> [CGPoint] {
        var preferred = pickDistinctGoalEnds(from: terminalGoalEndpoints(), count: count, minDistance: 68)

        if preferred.count < count {
            let riverEnds: [CGPoint] = [labyrinth.mainRiver.segments.last?.end].compactMap { $0 }
                + labyrinth.sideRivers.compactMap { $0.segments.last?.end }
            let fallbackEnds = pickDistinctGoalEnds(from: riverEnds, count: count, minDistance: 60)

            for candidate in fallbackEnds where preferred.count < count {
                if preferred.allSatisfy({ goalDistance($0, candidate) >= 36 }) {
                    preferred.append(candidate)
                }
            }
        }

        return Array(preferred.prefix(count))
    }

    // MARK: - Helper: find nærmeste punkt på en quad bezier til et punkt (samples)
    private func nearestPointOnQuadCurve(start: CGPoint, control: CGPoint, end: CGPoint, to point: CGPoint, samples: Int = 128) -> (point: CGPoint, distance: CGFloat) {
        var bestPoint = start
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
            let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
            let candidate = CGPoint(x: x, y: y)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let d = sqrt(dx*dx + dy*dy)
            if d < bestDist {
                bestDist = d
                bestPoint = candidate
            }
        }
        return (bestPoint, bestDist)
    }

    // Find nærmeste punkt på en allerede skaleret quad (bruges til screen-space snapping)
    private func nearestPointOnQuadCurveScaled(start: CGPoint, control: CGPoint, end: CGPoint, to point: CGPoint, samples: Int = 128) -> (point: CGPoint, distance: CGFloat) {
        var bestPoint = start
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in 0...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let x = pow(1 - t, 2) * start.x + 2 * (1 - t) * t * control.x + pow(t, 2) * end.x
            let y = pow(1 - t, 2) * start.y + 2 * (1 - t) * t * control.y + pow(t, 2) * end.y
            let candidate = CGPoint(x: x, y: y)
            let dx = candidate.x - point.x
            let dy = candidate.y - point.y
            let d = sqrt(dx*dx + dy*dy)
            if d < bestDist {
                bestDist = d
                bestPoint = candidate
            }
        }
        return (bestPoint, bestDist)
    }

    // Snap et screen-space punkt til nærmeste punkt på alle floder i screen-space
    private func snapPointToRiverScreen(_ pScreen: CGPoint, scaleX: CGFloat, scaleY: CGFloat, threshold: CGFloat = 48) -> CGPoint {
        var bestPoint: CGPoint? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude

        for segment in labyrinth.mainRiver.segments {
            let s = CGPoint(x: segment.start.x * scaleX, y: segment.start.y * scaleY)
            let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
            let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
            let res = nearestPointOnQuadCurveScaled(start: s, control: c, end: e, to: pScreen, samples: 48)
            if res.distance < bestDist {
                bestDist = res.distance
                bestPoint = res.point
            }
        }

        for river in labyrinth.sideRivers {
            for segment in river.segments {
                let s = CGPoint(x: segment.start.x * scaleX, y: segment.start.y * scaleY)
                let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
                let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
                let res = nearestPointOnQuadCurveScaled(start: s, control: c, end: e, to: pScreen, samples: 32)
                if res.distance < bestDist {
                    bestDist = res.distance
                    bestPoint = res.point
                }
            }
        }

        if let bp = bestPoint, bestDist <= threshold {
            return bp
        }
        return pScreen
    }

    // Tegn mål direkte i screen coords (brug når vi allerede har snapped screen center)
func goalMarkerScreen(centerScreen: CGPoint, label: String, objectScale: CGFloat) -> some View {
    let markerBoost: CGFloat = isPhone ? 1.25 : 1.0
    let labelBoost: CGFloat = isPhone ? 1.35 : 1.0
    let minLabelSize: CGFloat = isPhone ? 15 : 0
    let baseMarkerSize: CGFloat = isPhone ? 44 : 40
    let size = CGSize(width: baseMarkerSize * objectScale * markerBoost,
                      height: baseMarkerSize * objectScale * markerBoost)
    let labelSize = max(16 * objectScale * labelBoost, minLabelSize)

    return ZStack {
        Circle()
            .fill(Color.green.opacity(0.9))
            .frame(width: size.width, height: size.height)
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
            .shadow(radius: 4)
            .position(x: centerScreen.x, y: centerScreen.y)

        Text(label)
            .font(.system(size: labelSize, weight: .black))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .foregroundColor(.white)
            .shadow(radius: 2)
            .position(x: centerScreen.x, y: centerScreen.y)
    }
}

    // MARK: - Helper: snap et punkt til nærmeste punkt på alle floder hvis indenfor threshold
    private func snapPointToRiver(_ p: CGPoint, threshold: CGFloat = 48) -> CGPoint {
        var bestPoint: CGPoint? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude

        for segment in labyrinth.mainRiver.segments {
            let res = nearestPointOnQuadCurve(start: segment.start, control: segment.control, end: segment.end, to: p, samples: 48)
            if res.distance < bestDist {
                bestDist = res.distance
                bestPoint = res.point
            }
        }

        for river in labyrinth.sideRivers {
            for segment in river.segments {
                let res = nearestPointOnQuadCurve(start: segment.start, control: segment.control, end: segment.end, to: p, samples: 32)
                if res.distance < bestDist {
                    bestDist = res.distance
                    bestPoint = res.point
                }
            }
        }

        if let bp = bestPoint, bestDist <= threshold {
            return bp
        }
        return p
    }

    // MARK: - Helper: sikre præcis 3 synlige målrektangler (leaf først, fallback sidst)
    private func ensureThreeGoalRects(from possibleEnds: [CGPoint]) -> [CGRect] {
        var ends = preferredGoalEndpoints(count: 3)

        if ends.count < 3 {
            let goalCenters = labyrinth.goalPositions.map { CGPoint(x: $0.midX, y: $0.midY) }
            let fallbackPool = pickDistinctGoalEnds(from: possibleEnds + goalCenters, count: 3, minDistance: 56)

            for candidate in fallbackPool where ends.count < 3 {
                if ends.allSatisfy({ goalDistance($0, candidate) >= 34 }) {
                    ends.append(candidate)
                }
            }
        }

        // Absolut sidste fallback: ikke-leaf midtpunkter på river-segmenter
        if ends.count < 3 {
            let allSegments = labyrinth.mainRiver.segments + labyrinth.sideRivers.flatMap(\.segments)
            let segmentMidpoints = allSegments.map {
                CGPoint(x: ($0.start.x + $0.end.x) / 2, y: ($0.start.y + $0.end.y) / 2)
            }
            let midpointFallback = pickDistinctGoalEnds(from: segmentMidpoints, count: 3, minDistance: 50)

            for candidate in midpointFallback where ends.count < 3 {
                if ends.allSatisfy({ goalDistance($0, candidate) >= 30 }) {
                    ends.append(candidate)
                }
            }
        }

        let radius: CGFloat = 0
        let snapThreshold: CGFloat = 48
        var rects: [CGRect] = []

        for endPoint in ends {
            let snapped = snapPointToRiver(endPoint, threshold: snapThreshold)
            let clampedCenter = clampGoalCenter(snapped, radius: radius)
            rects.append(goalRectCentered(at: clampedCenter, size: CGSize(width: isPhone ? 52 : 40, height: isPhone ? 52 : 40)))
        }

        if rects.count < 3, let mainEnd = labyrinth.mainRiver.segments.last?.end {
            let fallbackCenter = clampGoalCenter(snapPointToRiver(mainEnd, threshold: snapThreshold), radius: radius)
            let fallbackRect = goalRectCentered(at: fallbackCenter, size: CGSize(width: isPhone ? 52 : 40, height: isPhone ? 52 : 40))
            while rects.count < 3 {
                rects.append(fallbackRect)
            }
        }

        return Array(rects.prefix(3))
    }
    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let transform = gameTransform(for: geo.size)
            ZStack {
                Color.black.ignoresSafeArea()
                Image("jungleBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                gameLayer(
                    in: geo.size,
                    scaleMultiplier: transform.scaleMultiplier,
                    footprintScale: transform.footprintScale
                )
                    .offset(x: transform.offsetX, y: transform.offsetY)

                uiOverlay(in: geo.size, safeTop: geo.safeAreaInsets.top)
            }
        }
        
        .onAppear {
            if randomizedGoals.isEmpty {
                if startImmediately {
                    // AllGames → start direkte
                    restartGame()
                    gameStarted = true
                } else {
                    // Fra forsiden → vis startskærm, men start IKKE spillet
                    gameStarted = false
                    speakIntro()
                }
            }
        }


    }

private func gameTransform(for size: CGSize) -> (offsetX: CGFloat, offsetY: CGFloat, scaleMultiplier: CGFloat, footprintScale: CGFloat) {
    // Preserve current iPad tuning exactly.
    guard isPhone else {
        return (gameOffsetX, gameOffsetY, gameScaleMultiplier, 1.0)
    }

    let isLandscape = size.width > size.height
    let footprintScale: CGFloat = isLandscape ? 0.92 : 0.93
    let centerX = (size.width * (1 - footprintScale)) / 2
    let centerY = (size.height * (1 - footprintScale)) / 2

    if isLandscape {
        return (-38 + centerX, -58 + centerY, 1.10, footprintScale)
    } else {
        return (-72 + centerX, -86 + centerY, 1.15, footprintScale)
    }
}

    // MARK: - UI Overlay
    private func uiOverlay(in size: CGSize, safeTop: CGFloat) -> some View {
        let topInset = max(8, safeTop + 6)

        return ZStack(alignment: .topLeading) {
            if !gameStarted {
                startScreen
            }

            if gameStarted {
                HStack {
                    topButtonBar(in: size)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, topInset)
            }

            if gameStarted {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        scoreCounter
                        if gameMode == .words && !currentWord.isEmpty {
                            wordProgressView
                        }
                    }
                }
                .padding(.top, topInset)
                .padding(.trailing, 14)
            }

            if gameStarted, helpMode {
                switch gameMode {
                case .math:
                    if let question = currentMathQuestion {
                        helpMathOverlay(question: question)
                    }
                case .letters, .words:
                    if let target = targetLetter {
                        helpLetterOverlay(target: target)
                    }
                }
            }

            if showErrorFlash {
                Color.red.opacity(0.4).ignoresSafeArea()
            }

            if showSuccessMessage {
                successOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Top Button Bar
    private func topButtonBar(in size: CGSize) -> some View {
        Group {
            if isPhone {
                ScrollView(.horizontal, showsIndicators: false) {
                    controlButtonsRow(spacing: 10)
                        .padding(.horizontal, 2)
                }
                .frame(maxWidth: min(size.width * 0.92, 520), alignment: .leading)
            } else {
                controlButtonsRow(spacing: 20)
            }
        }
    }

    private func controlButtonsRow(spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Button(action: { onBackToHub() }) {
                Text("← Tilbage")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                    .shadow(radius: 3)
            }

            // Speaker-knap – afhænger af mode
            Button(action: {
                switch gameMode {
                case .letters:
                    if let target = targetLetter {
                        let spokenLetter = useUppercase ? String(target) : String(target).lowercased()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            speakLetterQuestion(letter: spokenLetter)
                        }
                    }
                case .math:
                    if let q = currentMathQuestion {
                        let cleaned = q.replacingOccurrences(of: " ", with: "")

                        // Find operator
                        let opChar: Character? =
                            cleaned.contains("+") ? "+" :
                            cleaned.contains("-") ? "-" : nil

                        if let op = opChar,
                           let range = cleaned.range(of: String(op)) {

                            let left = String(cleaned[..<range.lowerBound])
                            let right = String(cleaned[range.upperBound...])

                            if let a = Int(left), let b = Int(right) {

                                // Brug segmenteret AI-stemme
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                                    speakMath(a: a, b: b)
                                }

                            } else {
                                // Fallback: parsing fejlede
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                                    let text = useMinus
                                        ? "Hvad er \(q) minus?"
                                        : "Hvad er \(q) plus?"
                                    speak(text)
                                }
                            }

                        } else {
                            // Fallback: ingen operator fundet
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                                let text = useMinus
                                    ? "Hvad er \(q) minus?"
                                    : "Hvad er \(q) plus?"
                                speak(text)
                            }
                        }
                    }

                case .words:
                    if !currentWord.isEmpty {
                        let word = currentWord
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                            speakWordQuestion(word: word)
                        }
                    }
                }
            }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 28, weight: .bold))
                    .padding(12)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }

            Button(action: {
                helpMode.toggle()
            }) {
                Image(systemName: helpMode ? "eye.fill" : "eye")
                    .font(.system(size: 28, weight: .bold))
                    .padding(12)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }

            // A → a / tilbage til letters-mode
            Button(action: {
                if gameMode == .math || gameMode == .words {
                    gameMode = .letters
                    restartGame()
                } else {
                    useUppercase.toggle()
                    restartGame()
                }
            }) {
                Text(useUppercase ? "a → A" : "A → a")
                    .font(.headline.bold())
                    .padding(10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                    .shadow(radius: 3)
            }

            // Math-mode
            Button(action: {
                gameMode = .math
                restartGame()
            }) {
                Text("1 + 1")
                    .font(.headline.bold())
                    .padding(10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                    .shadow(radius: 3)
            }

            // Word-mode
            Button(action: {
                gameMode = .words
                restartGame()
            }) {
                Image(systemName: "textformat.abc")
                    .font(.headline.bold())
                    .padding(10)
                    .background(Color.white.opacity(0.9))
                    .foregroundColor(.green)
                    .cornerRadius(10)
                    .shadow(radius: 3)
            }
        }
    }

    // MARK: - Help Overlays
    private func helpLetterOverlay(target: String) -> some View {
        VStack {
            Spacer()
            Text(target)
                .font(.system(size: 80, weight: .heavy))
                .foregroundColor(.yellow)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .scaleEffect(bounce ? 1.2 : 0.9)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: bounce)
                .onAppear {
                    bounce = true
                }
                .onDisappear { bounce = false }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -400)
    }

    private func helpMathOverlay(question: String) -> some View {
        VStack {
            Spacer()
            Text(question)
                .font(.system(size: 60, weight: .heavy))
                .foregroundColor(.yellow)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .padding()
                .background(Color.black.opacity(0.4))
                .cornerRadius(16)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, -400)
    }

    // MARK: - Score Counter
    private var scoreCounter: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                .font(.system(size: 24, weight: .bold))
            Text("\(startImmediately ? session.allGameScore : score)")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .cornerRadius(12)
        .shadow(radius: 3)
    }

    // MARK: - Word Progress View
    private var wordProgressView: some View {
        let chars = Array(currentWord)
        let solved = solvedLettersCount
        var pieces: [String] = []
        for i in 0..<chars.count {
            if i < solved {
                let ch = chars[i]
                let s = useUppercase ? String(ch).uppercased() : String(ch)
                pieces.append(s)
            } else {
                pieces.append("_")
            }
        }
        let display = pieces.joined(separator: " ")
        return Text(display)
            .font(.system(size: 22, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.35))
            .cornerRadius(12)
            .shadow(radius: 3)
    }

    // MARK: - Start Screen
    var startScreen: some View {
        Group {
            if isPhone {
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height
                    let cardWidth = min(geo.size.width * 0.9, 560)
                    let imageSize: CGFloat = isLandscape ? 108 : 156
                    let titleSize: CGFloat = isLandscape ? 34 : 42
                    let spacing: CGFloat = isLandscape ? 14 : 20
                    let topPad = max(12, geo.safeAreaInsets.top + 4)

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: spacing) {
                            if UIImage(named: "jungleCharacter") != nil {
                                Image("jungleCharacter")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: imageSize, height: imageSize)
                            } else {
                                Text("⛵️")
                                    .font(.system(size: imageSize * 0.72))
                            }

                            Text("Jungle River Labyrint")
                                .font(.system(size: titleSize, weight: .heavy))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .minimumScaleFactor(0.8)
                                .lineLimit(1)
                                .shadow(radius: 4)

                            Text(introText(for: gameMode))
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.black.opacity(0.45))
                                .cornerRadius(12)
                                .shadow(radius: 5)
                                .frame(maxWidth: cardWidth)

                            HStack(spacing: 14) {
                                Button(action: { internalDifficulty = .easy }) {
                                    HStack {
                                        Image(systemName: internalDifficulty == .easy ? "largecircle.fill.circle" : "circle")
                                        Text("Let")
                                    }
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(12)
                                }

                                Button(action: { internalDifficulty = .hard }) {
                                    HStack {
                                        Image(systemName: internalDifficulty == .hard ? "largecircle.fill.circle" : "circle")
                                        Text("Svær")
                                    }
                                    .font(.headline.bold())
                                    .foregroundColor(.white)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.black.opacity(0.4))
                                    .cornerRadius(12)
                                }
                            }
                            .frame(maxWidth: min(cardWidth, 420))

                            Button(action: startGame) {
                                Text("Spil")
                                    .font(.title3.bold())
                                    .frame(maxWidth: min(cardWidth * 0.5, 240))
                                    .padding(.vertical, 12)
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(radius: 5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, topPad)
                        .padding(.bottom, 20)
                        .padding(.horizontal, 16)
                        .frame(minHeight: geo.size.height, alignment: .center)
                    }
                }
            } else {
                VStack(spacing: 24) {
                    Spacer(minLength: 80)
                    if UIImage(named: "jungleCharacter") != nil {
                        Image("jungleCharacter")
                            .resizable()
                            .frame(width: 180, height: 180)
                    } else {
                        Text("⛵️")
                            .font(.system(size: 120))
                    }

                    Text("Jungle River Labyrint")
                        .font(.largeTitle.bold())
                        .foregroundColor(.white)
                        .shadow(radius: 4)

                    Text(introText(for: gameMode))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(12)
                        .shadow(radius: 5)
                        .padding(.horizontal, 24)


                    HStack(spacing: 20) {
                        Button(action: { internalDifficulty = .easy }) {
                            HStack {
                                Image(systemName: internalDifficulty == .easy ? "largecircle.fill.circle" : "circle")
                                Text("Let")
                            }
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                        }

                        Button(action: { internalDifficulty = .hard }) {
                            HStack {
                                Image(systemName: internalDifficulty == .hard ? "largecircle.fill.circle" : "circle")
                                Text("Svær")
                            }
                            .font(.title3.bold())
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(12)
                        }
                    }

                    Button(action: startGame) {
                        Text("Spil")
                            .font(.title2.bold())
                            .padding(.vertical, 12)
                            .padding(.horizontal, 40)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                            .shadow(radius: 5)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Success Overlay
    var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            let targetChar = targetLetter ?? "?"
            let successText: String = {
                switch gameMode {
                case .words:
                    return "Flot! Du fandt ordet \(currentWord)"
                case .letters, .math:
                    return "Flot! Du fandt \(String(targetChar))!"
                }
            }()

            VStack(spacing: 16) {
                if UIImage(named: "successStar") != nil {
                    Image("successStar")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .shadow(radius: 8)
                } else {
                    Text("⭐️")
                        .font(.system(size: 80))
                }

                Text(successText)
                    .font(.title.bold())
                    .foregroundColor(.white)
                    .shadow(radius: 4)

                Button(action: {
                    if startImmediately {
                        // Vi er startet fra AllGamesMode → videre til næste spil
                        onExit()
                    } else {
                        // Vi er startet direkte fra hub → spil igen i samme mode
                        restartGame()
                    }

                }) {
                    Text("Prøv igen")
                        .font(.headline.bold())
                        .padding(.vertical, 10)
                        .padding(.horizontal, 32)
                        .background(Color.white)
                        .foregroundColor(.green)
                        .cornerRadius(14)
                        .shadow(radius: 4)
                }
            }
            .padding()
        }
        .transition(.opacity)
    }

    // MARK: - Game Layer
    private func gameLayer(in size: CGSize, scaleMultiplier: CGFloat, footprintScale: CGFloat = 1.0) -> some View {
        let scaleX = (size.width / canvasWidth) * footprintScale
        let scaleY = (size.height / canvasHeight) * footprintScale
        let objectScale = min(scaleX, scaleY) * scaleMultiplier

        return ZStack {
            if gameStarted {
                drawRivers(scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
                drawGoals(scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
                drawPlayer(scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)

                // Debug visuals: endepunkter og målcentre (kun når debugMode = true)
                // --- Debug: vis koordinater ved punkter og panel ---
                if debugMode {
                    // Tegn og label main river endepunkter (røde)
                    ForEach(0..<labyrinth.mainRiver.segments.count, id: \.self) { i in
                        let p = labyrinth.mainRiver.segments[i].end
                        Circle().fill(Color.red).frame(width: 6, height: 6)
                            .position(x: p.x * scaleX, y: p.y * scaleY)
                        Text("R\(i): \(Int(p.x)),\(Int(p.y))")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .position(x: (p.x * scaleX) + 40, y: (p.y * scaleY) - 8)
                    }

                    // Tegn og label side river endepunkter (orange)
                    ForEach(0..<labyrinth.sideRivers.count, id: \.self) { i in
                        if let last = labyrinth.sideRivers[i].segments.last?.end {
                            Circle().fill(Color.orange).frame(width: 6, height: 6)
                                .position(x: last.x * scaleX, y: last.y * scaleY)
                            Text("S\(i): \(Int(last.x)),\(Int(last.y))")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .position(x: (last.x * scaleX) + 40, y: (last.y * scaleY) - 8)
                        }
                    }

                    // Tegn og label målcentre (gule/green)
                    ForEach(0..<randomizedGoals.count, id: \.self) { i in
                        let r = randomizedGoals[i].rect
                        let center = CGPoint(x: r.midX, y: r.midY)
                        Circle().stroke(Color.yellow, lineWidth: 2)
                            .frame(width: 44 * objectScale, height: 44 * objectScale)
                            .position(x: center.x * scaleX, y: center.y * scaleY)
                        Text("G\(i): \(Int(center.x)),\(Int(center.y))")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .position(x: (center.x * scaleX) + 40, y: (center.y * scaleY) - 8)
                    }

                    // Fast debug‑panel øverst til venstre med en kompakt liste
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEBUG COORDS").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        // Main ends
                        ForEach(0..<labyrinth.mainRiver.segments.count, id: \.self) { i in
                            let p = labyrinth.mainRiver.segments[i].end
                            Text("R\(i): x=\(Int(p.x)) y=\(Int(p.y))")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                        // Side ends
                        ForEach(0..<labyrinth.sideRivers.count, id: \.self) { i in
                            if let last = labyrinth.sideRivers[i].segments.last?.end {
                                Text("S\(i): x=\(Int(last.x)) y=\(Int(last.y))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white)
                            }
                        }
                        // Goals
                        ForEach(0..<randomizedGoals.count, id: \.self) { i in
                            let r = randomizedGoals[i].rect
                            Text("G\(i): x=\(Int(r.midX)) y=\(Int(r.midY))")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(8)
                    .frame(maxWidth: 320, alignment: .leading)
                    .position(x: 160, y: 60) // juster placering hvis nødvendig
                }
                
            }
  

        }
        .contentShape(Rectangle())
    }

    // MARK: - Rivers
    func drawRivers(scaleX: CGFloat, scaleY: CGFloat, objectScale: CGFloat) -> some View {
        let allSegments = labyrinth.mainRiver.segments + labyrinth.sideRivers.flatMap(\.segments)
        let junctions = junctionCenters(for: allSegments, scaleX: scaleX, scaleY: scaleY)

        return ZStack {
            drawRiver(labyrinth.mainRiver.segments, scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
            drawAllSideRivers(scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
            drawJunctionBasins(junctions: junctions, objectScale: objectScale)
        }
    }

    func drawRiver(
        _ curves: [RiverSegment],
        scaleX: CGFloat,
        scaleY: CGFloat,
        objectScale: CGFloat
    ) -> some View {
        let riverPath = Path { path in
            if let first = curves.first {
                path.move(to: CGPoint(x: first.start.x * scaleX, y: first.start.y * scaleY))
                for segment in curves {
                    let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
                    let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
                    path.addQuadCurve(to: e, control: c)
                }
            }
        }

        return drawWaterCorridor(path: riverPath, objectScale: objectScale)
    }

    func drawAllSideRivers(scaleX: CGFloat, scaleY: CGFloat, objectScale: CGFloat) -> some View {
        let sideRiverPath = Path { path in
            for river in labyrinth.sideRivers {
                if let first = river.segments.first {
                    path.move(to: CGPoint(x: first.start.x * scaleX, y: first.start.y * scaleY))
                    for segment in river.segments {
                        let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
                        let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
                        path.addQuadCurve(to: e, control: c)
                    }
                }
            }
        }

        return drawWaterCorridor(path: sideRiverPath, objectScale: objectScale)
    }

    private func drawWaterCorridor(path: Path, objectScale: CGFloat) -> some View {
        return ZStack {
            // Soft outer jungle bank.
            path
                .stroke(
                    Color(red: 0.55, green: 0.45, blue: 0.30).opacity(0.16),
                    style: StrokeStyle(
                        lineWidth: 42 * objectScale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            // Main water corridor.
            path
                .stroke(
                    Color(red: 0.22, green: 0.65, blue: 0.95).opacity(0.95),
                    style: StrokeStyle(
                        lineWidth: 26 * objectScale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            // Soft water highlight.
            path
                .stroke(
                    Color.white.opacity(0.14),
                    style: StrokeStyle(
                        lineWidth: 8 * objectScale,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
        }
        .shadow(color: Color.black.opacity(0.04), radius: 0.9 * objectScale, x: 0, y: 0.6 * objectScale)
    }

    private func drawJunctionBasins(junctions: [CGPoint], objectScale: CGFloat) -> some View {
        ZStack {
            ForEach(junctions.indices, id: \.self) { idx in
                let center = junctions[idx]

                Circle()
                    .fill(Color(red: 0.55, green: 0.45, blue: 0.30).opacity(0.16))
                    .frame(width: 44 * objectScale, height: 44 * objectScale)
                    .position(center)

                Circle()
                    .fill(Color(red: 0.22, green: 0.65, blue: 0.95).opacity(0.95))
                    .frame(width: 30 * objectScale, height: 30 * objectScale)
                    .position(center)

                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 10 * objectScale, height: 10 * objectScale)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
    }

    private func junctionCenters(
        for segments: [RiverSegment],
        scaleX: CGFloat,
        scaleY: CGFloat
    ) -> [CGPoint] {
        struct JunctionBucket {
            var count: Int
            var sumX: CGFloat
            var sumY: CGFloat
        }

        var buckets: [String: JunctionBucket] = [:]
        let snap: CGFloat = 4

        func add(_ point: CGPoint) {
            let x = point.x * scaleX
            let y = point.y * scaleY
            let keyX = Int((x / snap).rounded())
            let keyY = Int((y / snap).rounded())
            let key = "\(keyX):\(keyY)"

            if var bucket = buckets[key] {
                bucket.count += 1
                bucket.sumX += x
                bucket.sumY += y
                buckets[key] = bucket
            } else {
                buckets[key] = JunctionBucket(count: 1, sumX: x, sumY: y)
            }
        }

        for segment in segments {
            add(segment.start)
            add(segment.end)
        }

        return buckets.values.compactMap { bucket in
            // Degree 2 = normal continuation, degree 3+ = branch junction.
            guard bucket.count >= 3 else { return nil }
            let c = CGFloat(bucket.count)
            return CGPoint(x: bucket.sumX / c, y: bucket.sumY / c)
        }
    }

    // MARK: - Goals
    func drawGoals(scaleX: CGFloat, scaleY: CGFloat, objectScale: CGFloat) -> some View {
        ZStack {
            ForEach(0..<randomizedGoals.count, id: \.self) { i in
                let goal = randomizedGoals[i]
                // original center i canvas coords
                let centerCanvas = CGPoint(x: goal.rect.midX, y: goal.rect.midY)
                // konverter til screen coords
                let centerScreen = CGPoint(x: centerCanvas.x * scaleX, y: centerCanvas.y * scaleY)
                // snap i screen space til den synlige kurve
                let snappedScreen = snapPointToRiverScreen(centerScreen, scaleX: scaleX, scaleY: scaleY, threshold: 64)
                // tegn marker i screen coords
                goalMarkerScreen(centerScreen: snappedScreen, label: String(goal.label), objectScale: objectScale)
            }
        }
        .transaction { tx in
            tx.animation = nil
        }
    }


    // Erstat eksisterende goalMarker med denne version
    func goalMarker(
        _ rect: CGRect,
        label: String,
        scaleX: CGFloat,
        scaleY: CGFloat,
        objectScale: CGFloat
    ) -> some View {
        // Beregn center i canvas-koordinater og skaler med scaleX/scaleY
        let centerX = rect.midX * scaleX
        let centerY = rect.midY * scaleY

        // Beregn størrelse på målet med scaleX/scaleY (bredde med scaleX, højde med scaleY)
        let width = rect.width * scaleX
        let height = rect.height * scaleY

        return ZStack {
            Circle()
                .fill(Color.green.opacity(0.9))
                .frame(width: width, height: height)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                )
                .shadow(radius: 4)
                .position(x: centerX, y: centerY)

            Text(label)
                .font(.system(size: 16 * min(scaleX, scaleY), weight: .black))
                .foregroundColor(.white)
                .shadow(radius: 2)
                .position(x: centerX, y: centerY)
        }
    }


    // MARK: - Player (båd)
    func drawPlayer(scaleX: CGFloat, scaleY: CGFloat, objectScale: CGFloat) -> some View {
        let screenPos = CGPoint(
            x: position.x * scaleX,
            y: position.y * scaleY
        )

        return Group {
            if UIImage(named: "playerBoat") != nil {
                Image("playerBoat")
                    .resizable()
                    .frame(width: 80 * objectScale, height: 80 * objectScale)
            } else {
                Text("⛵️")
                    .font(.system(size: 40 * objectScale))
            }
        }
        .shadow(radius: 5 * objectScale)
        .position(screenPos)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let canvasPoint = CGPoint(
                        x: value.location.x / scaleX,
                        y: value.location.y / scaleY
                    )
                    
                    lastBoatPosition = canvasPoint
                    
                    if let last = lastDragPoint {
                        let dx = canvasPoint.x - last.x
                        let dy = canvasPoint.y - last.y
                        let dist = sqrt(dx*dx + dy*dy)
                        if dist < 2 { return }
                    }

                    lastDragPoint = canvasPoint

                    if isOnRiver(canvasPoint) {
                        position = canvasPoint
                    } else {
                        triggerErrorFlash()
                        hapticError()
                    }
                }
                .onEnded { _ in
                    lastDragPoint = nil
                    checkGoal()
                }
        )
    }

    // MARK: - Collision Detection (optimeret)
    func isOnRiver(_ point: CGPoint) -> Bool {
        let allowedDistance: CGFloat = isPhone ? 24 : 20

        func distanceToCurve(start: CGPoint, control: CGPoint, end: CGPoint) -> CGFloat {
            let steps = 16
            var minDist = CGFloat.greatestFiniteMagnitude
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = pow(1 - t, 2) * start.x
                    + 2 * (1 - t) * t * control.x
                    + pow(t, 2) * end.x
                let y = pow(1 - t, 2) * start.y
                    + 2 * (1 - t) * t * control.y
                    + pow(t, 2) * end.y
                let dx = point.x - x
                let dy = point.y - y
                let dist = sqrt(dx*dx + dy*dy)
                if dist < minDist {
                    minDist = dist
                }
            }
            return minDist
        }

        // Main river
        for segment in labyrinth.mainRiver.segments {
            if distanceToCurve(start: segment.start, control: segment.control, end: segment.end) < allowedDistance {
                return true
            }
        }

        // Side rivers
        for river in labyrinth.sideRivers {
            for segment in river.segments {
                if distanceToCurve(start: segment.start, control: segment.control, end: segment.end) < allowedDistance {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Game Control
    func resetGame() {
        labyrinth = generateRandomLabyrinth()
        setBoatToMainStart()
        showSuccessMessage = false
        gameStarted = false
        randomizedGoals = []
        targetLetter = nil
        helpMode = false
        score = 0
        currentWord = ""
        remainingLetters = []
        solvedLettersCount = 0
        currentMathQuestion = nil
    }

    func restartGame() {
        
        lastBoatPosition = position
        labyrinth = generateRandomLabyrinth()
        setBoatToMainStart()
        showSuccessMessage = false
        showErrorFlash = false
        randomizedGoals = []
        targetLetter = nil
        currentWord = ""
        remainingLetters = []
        solvedLettersCount = 0
        currentMathQuestion = nil
        startGame()
    }

    func startGame() {
        gameStarted = true
        labyrinth = generateRandomLabyrinth(seed: nil, internalDifficulty: internalDifficulty)
        setBoatToMainStart()

        // LETTER MODE
        if gameMode == .letters {
            currentMathQuestion = nil
            currentWord = ""
            remainingLetters = []
            solvedLettersCount = 0

            let letters = Array(availableLetters.shuffled().prefix(3)).map {
                useUppercase ? $0.uppercased() : $0.lowercased()
            }

            guard !letters.isEmpty else { return }
            let dynamicGoalRects = ensureThreeGoalRects(from: preferredGoalEndpoints(count: 3))
            let shuffledPositions = dynamicGoalRects.shuffled()

            randomizedGoals = Array(zip(letters, shuffledPositions)).map { letter, rect in
                (label: String(letter), rect: rect)
            }

            targetLetter = String(letters[0])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                let spokenLetter = useUppercase ? String(letters[0]) : String(letters[0]).lowercased()
                speakLetterQuestion(letter: spokenLetter)
            }

            return
        }

        // MATH MODE
        if gameMode == .math {
            currentWord = ""
            remainingLetters = []
            solvedLettersCount = 0

            // Difficulty-styret talområde
            let range: ClosedRange<Int> = (internalDifficulty == .easy) ? 1...6 : 4...15

            // 1) Vælg to tal
            var a = Int.random(in: range)
            var b = Int.random(in: range)
            
            // 2) Sørg for at a altid er størst (så vi undgår negative resultater)
            if b > a {
                swap(&a, &b)
            }
            
            // 3) Vælg tilfældigt om vi bruger minus eller plus
            useMinus = Bool.random()

            // 4) Udregn korrekt svar
            let correct = useMinus ? (a - b) : (a + b)

            // 5) Generér spørgsmålet
            currentMathQuestion = useMinus ? "\(a) - \(b)" : "\(a) + \(b)"
            
            // 6) Result
            let result = correct
            
            // 7) Display results
            let correctString = "\(result)"
            targetLetter = correctString

            var wrongNumbers = Set<Int>()

            // Primære kandidater: result - 1 og result + 1
            let primaryCandidates = [correct - 1, correct + 1]


            // Tilføj gyldige tal (1–30)
            for c in primaryCandidates {
                if c >= 1 && c <= 30 && c != correct {
                    wrongNumbers.insert(c)
                }
            }

            // Hvis vi stadig mangler et tal (fx ved result = 1 eller 30)
            while wrongNumbers.count < 2 {
                let fallback = Int.random(in: max(1, correct - 3)...min(30, correct + 3))
                if fallback != correct {
                    wrongNumbers.insert(fallback)
                }
            }

            let wrongStrings = wrongNumbers.map { "\($0)" }
            var allAnswers: [String] = [correctString] + wrongStrings
            allAnswers.shuffle()
            let dynamicGoalRects = ensureThreeGoalRects(from: preferredGoalEndpoints(count: 3))

            randomizedGoals = Array(zip(allAnswers, dynamicGoalRects)).map { letter, rect in
                (label: letter, rect: rect)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                speakMath(a: a, b: b)
            }


            return
        }

        // WORD MODE
        if gameMode == .words {
            currentMathQuestion = nil
            let availableWords: [String] = (internalDifficulty == .easy) ? easyWords : hardWords
            currentWord = availableWords.randomElement() ?? "kat"
            remainingLetters = Array(currentWord)
            solvedLettersCount = 0

            let firstRaw = remainingLetters.removeFirst()
            let first = useUppercase ? firstRaw.uppercased() : firstRaw.lowercased()
            targetLetter = String(first)

            setupWordChoices()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                speakWordQuestion(word: currentWord)
            }


            return
        }
    }

    // MARK: - pling
    func playSoundEffect(_ name: String, type: String = "wav") {
        if let url = Bundle.main.url(forResource: name, withExtension: type) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
            } catch {
            }
        } else {
        }
    }

    //MARK: MATH HELPER:// Bygger aiFiles + segmentTexts for et simpelt math spørgsmål "Hvad er a plus b"
    private func segmentsForMath(a: Int, b: Int) -> (aiFiles: [String?], segmentTexts: [String?]) {
        var aiFiles: [String?] = []
        var segmentTexts: [String?] = []

        // Indledning
        aiFiles.append("math_q_what_is")
        segmentTexts.append("Hvad er")

        // Venstre operand (brug hour_ tokens)
        aiFiles.append("hour_\(a)")
        segmentTexts.append("\(a)")

        // Operator (plus eller minus)
        if useMinus {
            aiFiles.append("op_minus")
            segmentTexts.append("minus")
        } else {
            aiFiles.append("op_plus")
            segmentTexts.append("plus")
        }

        // Højre operand
        aiFiles.append("hour_\(b)")
        segmentTexts.append("\(b)")

        return (aiFiles, segmentTexts)
    }

    private func speakMath(a: Int, b: Int) {
        let (aiFiles, segmentTexts) = segmentsForMath(a: a, b: b)
        AudioVoiceManager.shared.debugLogging = false
        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: segmentTexts,
            completion: nil
        )
    }
    
    private func speakMathCorrect(result: Int) {
        AudioVoiceManager.shared.debugLogging = true

        // Hvis vi har en hour token for resultatet, brug to segmenter: math_correct + hour_X. Denne if formula styrer til hvilket niveau der er AI
        if (1...30).contains(result) {
            let aiFiles: [String?] = ["math_correct", "hour_\(result)"]
            let fallbackTexts: [String?] = ["Flot, du fandt", "\(result)"]
            AudioVoiceManager.shared.speakSequencePerSegment(
                aiFiles: aiFiles,
                segmentFallbackTexts: fallbackTexts,
                completion: nil
            )
        } else {
            // Ingen token til resultatet — brug TTS fallback for hele beskeden
            speak("Flot! Du fandt \(result)")
        }
    }
    
    private func speakMathWrong(chosen: String) {
        // Prøv AI‑filen math_wrong, ellers fallback til TTS der kun siger det valgte tal
        AudioVoiceManager.shared.debugLogging = false
        AudioVoiceManager.shared.speakWithFallback(aiFile: "math_wrong") {
            // fallback TTS: sig kun hvad barnet valgte
            speak("Ups, det var \(chosen)")
        }
    }

//MARK: MATH Letter:// Bygger aiFiles + segmentTexts for et simpelt letter spørgsmål
    private func letterToken(for letter: String) -> String {
        let l = letter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Håndter specialtegn eksplicit
        switch l {
        case "æ": return "letter_æ"
        case "ø": return "letter_ø"
        case "å": return "letter_å"
        default:
            // Antag A-Z og W etc.
            let safe = l.replacingOccurrences(of: " ", with: "")
            return "letter_\(safe)"
        }
    }
    
    private func segmentsForLetterQuestion(letter: String) -> (aiFiles: [String?], segmentTexts: [String?]) {
        var aiFiles: [String?] = []
        var segmentTexts: [String?] = []

        // Indledning
        aiFiles.append("letter_find")
        segmentTexts.append("Find bogstavet")

        // Bogstavstoken (fx "letter_a", "letter_æ" osv.)
        let token = letterToken(for: letter)
        aiFiles.append(token)
        segmentTexts.append(letter)

        return (aiFiles, segmentTexts)
    }

    // Erstat din eksisterende speakLetterQuestion med denne
    private func speakLetterQuestion(letter: String) {
        // Debug: vis hvad vi forsøger at afspille
        let introToken = "letter_find"
        let letterTokenName = letterToken(for: letter) // fx "letter_a"
        let aiFiles: [String?] = [introToken, letterTokenName]
        let segmentTexts: [String?] = ["Find bogstavet", letter]


        // Helper: tjek om fil findes i bundle (mp3/m4a/wav/caf)
        func fileExists(_ token: String) -> Bool {
            let exts = ["mp3","m4a","wav","caf"]
            for ext in exts {
                if Bundle.main.url(forResource: token, withExtension: ext) != nil { return true }
            }
            return false
        }

        // Print file existence for tokens
        let introExists = fileExists(introToken)
        let letterExists = fileExists(letterTokenName)

        // Hvis mindst én fil findes, kald AudioVoiceManager som i math
        if introExists || letterExists {
            AudioVoiceManager.shared.debugLogging = false
            AudioVoiceManager.shared.speakSequencePerSegment(
                aiFiles: aiFiles,
                segmentFallbackTexts: segmentTexts,
                completion: nil
            )
            return
        }

        // Fallback: hvis ingen filer findes, brug TTS så vi ved at lyd virker
        speak("Find bogstavet \(letter)")
    }

    private func speakLetterCorrect(letter: String) {
        AudioVoiceManager.shared.debugLogging = true

        // Brug samme mønster som math: intro + bogstav token
        let aiFiles: [String?] = ["letter_correct", letterToken(for: letter)]
        let fallbackTexts: [String?] = ["Flot! Du fandt", letter]

        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: fallbackTexts,
            completion: nil
        )
    }

    private func speakLetterWrong(chosen: String) {
        AudioVoiceManager.shared.debugLogging = false

        // Prøv AI token "letter_wrong", ellers fallback TTS i completion
        AudioVoiceManager.shared.speakWithFallback(aiFile: "letter_wrong") {
            speak("Ups, det var \(chosen)")
        }
    }
    
//MARK: WORD HELPER:// Bygger aiFiles + segmentTexts for et simpelt word spørgsmål
    private func segmentsForWordQuestion(word: String) -> (aiFiles: [String?], segmentTexts: [String?]) {
        var aiFiles: [String?] = []
        var segmentTexts: [String?] = []

        aiFiles.append("word_find")
        segmentTexts.append("Find ordet")

        // Vi returnerer kun segmentTexts her; aiFiles bestemmes i speakWordQuestion (prøver flere varianter)
        segmentTexts.append(word)

        return (aiFiles, segmentTexts)
    }

    private func speakWordQuestion(word: String) {

        // Byg kandidat tokens i prioriteret rækkefølge
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ascii = raw
            .replacingOccurrences(of: "å", with: "aa")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "ø", with: "oe")
        let underscored = raw.replacingOccurrences(of: " ", with: "_")

        let candidateTokens = ["word_\(raw)", "word_\(ascii)", "word_\(underscored)"]

        // Helper: tjek om fil findes i bundle (mp3/m4a/wav/caf)
        func fileExists(_ token: String) -> Bool {
            let exts = ["mp3","m4a","wav","caf"]
            for ext in exts {
                if Bundle.main.url(forResource: token, withExtension: ext) != nil { return true }
            }
            return false
        }

        // Find første token der findes
        var chosenWordToken: String? = nil
        for t in candidateTokens {
            if fileExists(t) {
                chosenWordToken = t
                break
            }
        }

        // Byg aiFiles array: intro + valgt word token (eller nil hvis ingen)
        let aiFiles: [String?] = ["word_find", chosenWordToken]
        let segmentTexts: [String?] = ["Find ordet", word]

        if chosenWordToken != nil || fileExists("word_find") {
            AudioVoiceManager.shared.debugLogging = true
            AudioVoiceManager.shared.speakSequencePerSegment(
                aiFiles: aiFiles,
                segmentFallbackTexts: segmentTexts,
                completion: nil
            )
            return
        }

        // Fallback: TTS så vi altid får lyd
        speak("Find ordet \(word)")
    }

    private func speakWordCorrect(word: String) {
        AudioVoiceManager.shared.debugLogging = false

        // Prøv intro + ord token (brug samme tokennavn som i Word voices.xlsx)
        let wordToken = "word_\(word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        let aiFiles: [String?] = ["word_correct", wordToken]
        let fallbackTexts: [String?] = ["Flot! Du fandt", word]


        // Hvis AudioVoiceManager kan afspille, brug den
        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: fallbackTexts,
            completion: nil
        )
    }

    private func speakWordWrong(chosen: String) {
        AudioVoiceManager.shared.debugLogging = true

        // Prøv at afspille generisk wrong token; i completion fallback til TTS med valgt ord
        AudioVoiceManager.shared.speakWithFallback(aiFile: "word_wrong") {
            speak("Ups, det var \(chosen)")
        }
    }

    private func speakWordProgress(ordinalIndex: Int, word: String) {
        AudioVoiceManager.shared.debugLogging = false

        // Map ordinal index → token
        let ordinalToken: String = {
            switch ordinalIndex {
            case 0: return "word_first"
            case 1: return "word_second"
            case 2: return "word_third"
            case 3: return "word_fourth"
            default: return "word_first" // fallback
            }
        }()

        // Word token (fra dit Excel-ark)
        let raw = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let wordToken = "word_\(raw)"

        // Hele AI-sekvensen
        let aiFiles: [String?] = [
            "word_flot",          // Flot!
            ordinalToken,         // første / andet / tredje / fjerde
            "word_letter_count",  // bogstav
            wordToken,            // ordet
            "word_letter_next"    // Find næste bogstav
        ]

        let fallbackTexts: [String?] = [
            "Flot!",
            ordinalWord(for: ordinalIndex),
            "bogstav",
            word,
            "Find næste bogstav"
        ]

        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: fallbackTexts,
            completion: nil
        )
    }


    
    
    // MARK: - Word helpers
    // MARK: - Generér et nyt målpunkt et sted på en flod
    func randomPoint(on river: River) -> CGPoint {
        guard let segment = river.segments.randomElement() else {
            return .zero
        }

        // Vælg et punkt et sted midt på segmentet (ikke helt i enderne)
        let t = CGFloat.random(in: 0.2...0.8)

        return CGPoint(
            x: segment.start.x + (segment.end.x - segment.start.x) * t,
            y: segment.start.y + (segment.end.y - segment.start.y) * t
        )
    }


    // MARK: - Word mode mål-generering
    func setupWordChoices() {
        guard let targetLetter = targetLetter else { return }

        // 1) Primær placering: terminale endpoints (maze-ends)
        let dynamicGoalRects = ensureThreeGoalRects(from: preferredGoalEndpoints(count: 3))

        // 2) Undgå mål for tæt på båden
        let excludeCenter = lastBoatPosition ?? position
        let excludeRadius: CGFloat = 20

        var filteredRects = dynamicGoalRects.filter { rect in
            let dx = rect.midX - excludeCenter.x
            let dy = rect.midY - excludeCenter.y
            return sqrt(dx*dx + dy*dy) > excludeRadius
        }

        // 3) Hvis vi mangler mål: prøv flere terminale endpoints først
        if filteredRects.count < 3 {
            let fallbackEndpointRects = preferredGoalEndpoints(count: 6).map { endPoint in
                goalRectCentered(at: clampGoalCenter(snapPointToRiver(endPoint, threshold: 48), radius: 0), size: CGSize(width: 40, height: 40))
            }

            for rect in fallbackEndpointRects where filteredRects.count < 3 {
                let nearBoat = goalDistance(CGPoint(x: rect.midX, y: rect.midY), excludeCenter) <= excludeRadius
                let overlapsExisting = filteredRects.contains {
                    goalDistance(CGPoint(x: $0.midX, y: $0.midY), CGPoint(x: rect.midX, y: rect.midY)) < 20
                }
                if !nearBoat && !overlapsExisting {
                    filteredRects.append(rect)
                }
            }
        }

        // 4) Sidste endpoint-fallback: kendte river-ends
        if filteredRects.count < 3 {
            let riverEnds: [CGPoint] = [labyrinth.mainRiver.segments.last?.end].compactMap { $0 }
                + labyrinth.sideRivers.compactMap { $0.segments.last?.end }

            for endPoint in riverEnds where filteredRects.count < 3 {
                let snapped = clampGoalCenter(snapPointToRiver(endPoint, threshold: 48), radius: 0)
                let rect = goalRectCentered(at: snapped, size: CGSize(width: 40, height: 40))
                let nearBoat = goalDistance(CGPoint(x: rect.midX, y: rect.midY), excludeCenter) <= excludeRadius
                let overlapsExisting = filteredRects.contains {
                    goalDistance(CGPoint(x: $0.midX, y: $0.midY), CGPoint(x: rect.midX, y: rect.midY)) < 20
                }
                if !nearBoat && !overlapsExisting {
                    filteredRects.append(rect)
                }
            }
        }

        // 5) Absolut nødfallback (kun hvis nødvendigt): midtpunkter på floden
        if filteredRects.count < 3 {
            let missing = 3 - filteredRects.count
            let riverPool = [labyrinth.mainRiver] + labyrinth.sideRivers

            for _ in 0..<missing {
                guard let river = riverPool.randomElement() else { continue }
                let point = randomPoint(on: river)
                let rect = CGRect(x: point.x - 20, y: point.y - 20, width: 40, height: 40)
                let nearBoat = goalDistance(CGPoint(x: rect.midX, y: rect.midY), excludeCenter) <= excludeRadius
                if !nearBoat {
                    filteredRects.append(rect)
                }
            }
        }

        if filteredRects.count < 3, let fallback = filteredRects.first ?? dynamicGoalRects.first {
            while filteredRects.count < 3 {
                filteredRects.append(fallback)
            }
        }

        filteredRects = Array(filteredRects.prefix(3))

        // 6) Generér labels
        var pool = availableLetters.map { String($0) }.filter { letter in
            let correct = useUppercase ? letter.uppercased() : letter.lowercased()
            return correct != targetLetter
        }

        pool.shuffle()

        let wrong1 = useUppercase ? pool[0].uppercased() : pool[0].lowercased()
        let wrong2 = useUppercase ? pool[1].uppercased() : pool[1].lowercased()

        var letters: [String] = [targetLetter, wrong1, wrong2]
        letters.shuffle()

        randomizedGoals = Array(zip(letters, filteredRects)).map { letter, rect in
            (label: letter, rect: rect)
        }
    }




    func ordinalWord(for index: Int) -> String {
        switch index {
        case 0: return "første"
        case 1: return "andet"
        case 2: return "tredje"
        case 3: return "fjerde"
        default: return "\(index + 1)."
        }
    }

    func checkGoal() {
        guard let targetLetter = targetLetter else { return }

        // WORD MODE
        if gameMode == .words {
            if let target = randomizedGoals.first(where: { $0.label == targetLetter }) {
                if target.rect.contains(position) {
                    //Logger bådens position
                    lastBoatPosition = position
                    // Opdater hvor mange bogstaver der er løst
                    solvedLettersCount += 1
                    let solvedIndex = solvedLettersCount - 1
                    let ordinal = ordinalWord(for: solvedIndex)

                    if !remainingLetters.isEmpty {
                        speakWordProgress(ordinalIndex: solvedIndex, word: currentWord)

                        let nextRaw = remainingLetters.removeFirst()
                        let next = useUppercase ? nextRaw.uppercased() : nextRaw.lowercased()
                        self.targetLetter = next
                        setupWordChoices()

                        return
                    }

                    // Ord færdigt
                    score += 1
                    showSuccessMessage = true
                    solvedLettersCount = currentWord.count
                    speakWordCorrect(word: currentWord)
                    return
                }
            }

            for goal in randomizedGoals where goal.label != targetLetter {
                if goal.rect.contains(position) {
                    triggerErrorFlash()
                    hapticError()
                    speakWordWrong(chosen: goal.label)
                    return
                }
            }

            return
        }

        // LETTERS + MATH
        if let target = randomizedGoals.first(where: { $0.label == targetLetter }) {
            if target.rect.contains(position) {
                score += 1
                playSoundEffect("pling")
                showSuccessMessage = true

                if gameMode == .math {
                    if let result = Int(targetLetter) {
                        // Math: sig korrekt resultat (simpelt)
                        speakMathCorrect(result: result)
                    }
                } else if gameMode == .letters {
                    speakLetterCorrect(letter: targetLetter ?? "?")
                } else { // words
                    speakWordCorrect(word: targetLetter ?? "?")
                }
            }
        }

        for goal in randomizedGoals where goal.label != targetLetter {
            if goal.rect.contains(position) {
                triggerErrorFlash()
                hapticError()
                if gameMode == .math {
                    speakMathWrong(chosen: goal.label)
                } else if gameMode == .letters {
                    speakLetterWrong(chosen: goal.label)
                } else { // words
                    speakWordWrong(chosen: goal.label)
                }
                return
            }
        }
    }

    func triggerErrorFlash() {
        showErrorFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showErrorFlash = false
        }
    }

    func hapticError() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    // MARK: - Speech (optimeret)
    private func preloadVoice() {
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = AVSpeechSynthesisVoice(language: "da-DK")
        utterance.rate = 0.4
        synthesizer.speak(utterance)
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
            let utterance = AVSpeechUtterance(string: text)
            
            utterance.voice = AVSpeechSynthesisVoice(language: "da-DK") //Siri stemme
            
            utterance.pitchMultiplier = 1.15
            utterance.rate = 0.40
            utterance.postUtteranceDelay = 0.1
            synthesizer.speak(utterance)
        }

    }
}
