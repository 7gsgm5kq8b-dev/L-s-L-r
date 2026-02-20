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

// MARK: - Randomiseret Labyrinth (V7.1 – mindre snørklet main river, bedre side separation, 1 loop)
func generateRandomLabyrinth(seed: UInt64? = nil, internalDifficulty: Difficulty = .easy) -> Labyrinth {
    var rng = seed.map { SeededGenerator(seed: $0) } ?? SeededGenerator(seed: UInt64(Date().timeIntervalSince1970))

    let leftBound: CGFloat = 222
    let rightBound: CGFloat = 770
    let bottomY: CGFloat = 1265
    let topYMin: CGFloat = 410

    func rand(_ range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &rng)
    }

    // MARK: 1) MAIN RIVER – flere punkter, mindre zig-zag
    let start = CGPoint(x: (leftBound + rightBound) / 2, y: bottomY)
    var nodes: [CGPoint] = [start]

    let segmentsCount = 12  // flere punkter → glattere flod
    var currentY = start.y
    var lastX = start.x

    for _ in 1...segmentsCount {
        let stepY = rand(70...95)  // mindre vertikale spring
        currentY -= stepY
        if currentY < topYMin { currentY = topYMin }

        // retningstræghed: små x-jitter
        let xJitter = rand(-60...60)
        let nextX = min(max(leftBound, lastX + xJitter), rightBound)
        lastX = nextX

        nodes.append(CGPoint(x: nextX, y: currentY))
    }

    // Blødere kontrolpunkter
    var mainSegments: [RiverSegment] = []
    for i in 0..<(nodes.count - 1) {
        let s = nodes[i]
        let e = nodes[i + 1]
        let mid = CGPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2)

        let perpOffset = rand(-35...35)  // mindre offset → mindre snørklet
        let control = CGPoint(
            x: min(max(leftBound, mid.x + perpOffset), rightBound),
            y: mid.y + rand(-15...15)
        )

        mainSegments.append(RiverSegment(start: s, control: control, end: e))
    }

    // MARK: 2) SIDE RIVERS – større separation i X og Y
    var sideRivers: [River] = []
    let desiredBranches = 3  // 3 side rivers er nok og giver plads

    var candidateIndices = Array(2..<(nodes.count - 3))
    candidateIndices.shuffle(using: &rng)

    var chosen: [Int] = []
    let minXSep: CGFloat = 150
    let minYSep: CGFloat = 150

    for idx in candidateIndices {
        let p = nodes[idx]
        var ok = true

        for c in chosen {
            let cp = nodes[c]
            if abs(cp.x - p.x) < minXSep { ok = false; break }
            if abs(cp.y - p.y) < minYSep { ok = false; break }
        }

        if ok {
            chosen.append(idx)
            if chosen.count == desiredBranches { break }
        }
    }

    // Generér side rivers
    var sideEnds: [CGPoint] = []

    for idx in chosen {
        let start = nodes[idx]
        let branchLen = Int.random(in: 2...3, using: &rng)

        var prev = start
        var segments: [RiverSegment] = []

        // retning baseret på placering
        var direction: CGFloat = start.x > (leftBound + rightBound)/2 ? -1 : 1

        for _ in 0..<branchLen {
            var end: CGPoint
            var attempt = 0

            repeat {
                let dx = rand(90...150) * direction
                let dy = rand(80...150)

                let endX = min(max(leftBound, prev.x + dx), rightBound)
                let endY = min(max(topYMin, prev.y - dy), bottomY - 40)

                end = CGPoint(x: endX, y: endY)
                attempt += 1

                if sideEnds.contains(where: { hypot($0.x - end.x, $0.y - end.y) < 120 }) {
                    direction *= -1
                } else {
                    break
                }
            } while attempt < 6

            let mid = CGPoint(x: (prev.x + end.x)/2, y: (prev.y + end.y)/2)
            let control = CGPoint(
                x: min(max(leftBound, mid.x + rand(-30...30)), rightBound),
                y: mid.y + rand(-20...20)
            )

            segments.append(RiverSegment(start: prev, control: control, end: end))
            prev = end
        }

        if let last = segments.last?.end { sideEnds.append(last) }
        sideRivers.append(River(segments: segments))
    }

    // MARK: 3) LOOP – kun ét, og kun hvis der er plads
    if let side = sideRivers.randomElement(using: &rng),
       let sideEnd = side.segments.last?.end {

        let mainCandidates = nodes.filter { abs($0.y - sideEnd.y) > 180 }

        if let mainPoint = mainCandidates.randomElement(using: &rng) {
            let mid = CGPoint(
                x: (sideEnd.x + mainPoint.x)/2 + rand(-25...25),
                y: (sideEnd.y + mainPoint.y)/2 + rand(-25...25)
            )

            let control = CGPoint(
                x: min(max(leftBound, mid.x + rand(-30...30)), rightBound),
                y: mid.y + rand(-20...20)
            )

            let loopSegment = RiverSegment(start: sideEnd, control: control, end: mainPoint)
            sideRivers.append(River(segments: [loopSegment]))
        }
    }

    // MARK: Goals (uændret)
    let leftEnd = sideRivers.first?.segments.last?.end ?? mainSegments.last!.end
    let rightEnd = sideRivers.dropFirst().first?.segments.last?.end ?? mainSegments.last!.end
    let topEnd = mainSegments.last!.end

    let goalPositions = [
        goalRect(from: leftEnd),
        goalRect(from: rightEnd),
        goalRect(from: topEnd)
    ]

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

    // MARK: - Helper: vælg op til `count` unikke endepunkter med en mindsteafstand
    private func pickDistinctGoalEnds(from candidates: [CGPoint], count: Int = 3, minDistance: CGFloat = 60) -> [CGPoint] {
        var chosen: [CGPoint] = []
        let shuffled = candidates.shuffled()
        for p in shuffled {
            var ok = true
            for c in chosen {
                let dx = p.x - c.x
                let dy = p.y - c.y
                if sqrt(dx*dx + dy*dy) < minDistance {
                    ok = false
                    break
                }
            }
            if ok { chosen.append(p) }
            if chosen.count == count { break }
        }
        return chosen
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

        // main river (skaler segmentpunkter til screen coords før beregning)
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

        // side rivers
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
        } else {
            return pScreen
        }
    }


    // Tegn mål direkte i screen coords (brug når vi allerede har snapped screen center)
    func goalMarkerScreen(centerScreen: CGPoint, label: String, objectScale: CGFloat) -> some View {
        let size = CGSize(width: 40 * objectScale, height: 40 * objectScale)
        return ZStack {
            Circle()
                .fill(Color.green.opacity(0.9))
                .frame(width: size.width, height: size.height)
                .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 2))
                .shadow(radius: 4)
                .position(x: centerScreen.x, y: centerScreen.y)

            Text(label)
                .font(.system(size: 16 * objectScale, weight: .black))
                .foregroundColor(.white)
                .shadow(radius: 2)
                .position(x: centerScreen.x, y: centerScreen.y)
        }
    }

    
    // MARK: - Helper: snap et punkt til nærmeste punkt på alle floder hvis indenfor threshold
    private func snapPointToRiver(_ p: CGPoint, threshold: CGFloat = 48) -> CGPoint {
        var bestPoint: CGPoint? = nil
        var bestDist = CGFloat.greatestFiniteMagnitude

        // tjek main river
        for segment in labyrinth.mainRiver.segments {
            let res = nearestPointOnQuadCurve(start: segment.start, control: segment.control, end: segment.end, to: p, samples: 48)
            if res.distance < bestDist {
                bestDist = res.distance
                bestPoint = res.point
            }
        }

        // tjek side rivers
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
        } else {
            return p
        }
    }

    // MARK: - Helper: sikre præcis 3 synlige målrektangler (snap + centreret clamp)
    private func ensureThreeGoalRects(from possibleEnds: [CGPoint]) -> [CGRect] {
        // 1) vælg op til 3 distinkte ends (centers)
        var ends = pickDistinctGoalEnds(from: possibleEnds, count: 3, minDistance: 60)

        // 2) hvis vi mangler, brug main end + små offsets som fallback (offsets i Int)
        if ends.count < 3 {
            if let mainEnd = labyrinth.mainRiver.segments.last?.end {
                var offset = 0
                while ends.count < 3 {
                    let dx = CGFloat((offset % 2 == 0) ? -40 : 40) * CGFloat((offset / 2) + 1)
                    let dy: CGFloat = 0
                    let candidate = CGPoint(x: min(max(222, mainEnd.x + dx), 770),
                                            y: min(max(410, mainEnd.y + dy), 1265))
                    if !ends.contains(where: { abs($0.x - candidate.x) < 1 && abs($0.y - candidate.y) < 1 }) {
                        ends.append(candidate)
                    }
                    offset += 1
                    if offset > 10 { break }
                }
            }
        }

        // 3) snap hver center til nærmeste punkt på floden (hvis tæt nok), så clamp center og lav rect centreret
        let radius: CGFloat = 0
        let snapThreshold: CGFloat = 48
        var rects: [CGRect] = []
        for e in ends {
            let snapped = snapPointToRiver(e, threshold: snapThreshold)
            let clampedCenter = clampGoalCenter(snapped, radius: radius)
            let rect = goalRectCentered(at: clampedCenter, size: CGSize(width: 40, height: 40))
            rects.append(rect)
        }

        // 4) hvis vi stadig ikke har 3, brug main end fallback
        if rects.count < 3 {
            if let mainEnd = labyrinth.mainRiver.segments.last?.end {
                let fallbackCenter = clampGoalCenter(snapPointToRiver(mainEnd, threshold: snapThreshold), radius: radius)
                let fallbackRect = goalRectCentered(at: fallbackCenter, size: CGSize(width: 40, height: 40))
                while rects.count < 3 { rects.append(fallbackRect) }
            }
        }

        return rects
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                Image("jungleBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .ignoresSafeArea()

                gameLayer(in: geo.size)
                    .offset(x: gameOffsetX, y: gameOffsetY)

                uiOverlay(in: geo.size)
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

    // MARK: - UI Overlay
    private func uiOverlay(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if !gameStarted {
                startScreen
            }

            if gameStarted {
                HStack {
                    topButtonBar
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 35)
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
                .padding(.top, 35)
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
    private var topButtonBar: some View {
        HStack(spacing: 20) {
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
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        bounce = true
                    }
                }
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
    private func gameLayer(in size: CGSize) -> some View {
        let scaleX = size.width / canvasWidth
        let scaleY = size.height / canvasHeight
        let objectScale = min(scaleX, scaleY) * gameScaleMultiplier

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
        ZStack {
            drawRiver(labyrinth.mainRiver.segments, scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
            drawAllSideRivers(scaleX: scaleX, scaleY: scaleY, objectScale: objectScale)
        }
    }

    func drawRiver(
        _ curves: [RiverSegment],
        scaleX: CGFloat,
        scaleY: CGFloat,
        objectScale: CGFloat
    ) -> some View {
        Path { path in
            for segment in curves {
                let s = CGPoint(x: segment.start.x * scaleX, y: segment.start.y * scaleY)
                let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
                let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
                path.move(to: s)
                path.addQuadCurve(to: e, control: c)
            }
        }
        .stroke(
            Color.blue.opacity(0.95),
            style: StrokeStyle(lineWidth: 30 * objectScale, lineCap: .round)
        )
        .shadow(color: Color.cyan.opacity(0.6), radius: 3 * objectScale)
    }

    func drawAllSideRivers(scaleX: CGFloat, scaleY: CGFloat, objectScale: CGFloat) -> some View {
        Path { path in
            for river in labyrinth.sideRivers {
                for segment in river.segments {
                    let s = CGPoint(x: segment.start.x * scaleX, y: segment.start.y * scaleY)
                    let c = CGPoint(x: segment.control.x * scaleX, y: segment.control.y * scaleY)
                    let e = CGPoint(x: segment.end.x * scaleX, y: segment.end.y * scaleY)
                    path.move(to: s)
                    path.addQuadCurve(to: e, control: c)
                }
            }
        }
        .stroke(
            Color.blue.opacity(0.95),
            style: StrokeStyle(lineWidth: 30 * objectScale, lineCap: .round)
        )
        .shadow(color: Color.cyan.opacity(0.6), radius: 3 * objectScale)
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
        let allowedDistance: CGFloat = 20

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
        
        // Brug difficulty senere til at styre labyrintens kompleksitet
        labyrinth = generateRandomLabyrinth(
            seed: nil,
            internalDifficulty: internalDifficulty
        )
        
        labyrinth = generateRandomLabyrinth()
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

            let possibleGoalEnds: [CGPoint] = [
                labyrinth.mainRiver.segments.last!.end
            ] + labyrinth.sideRivers.compactMap { $0.segments.last?.end }

            let dynamicGoalRects = ensureThreeGoalRects(from: possibleGoalEnds)
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

            let possibleGoalEnds: [CGPoint] = [
                labyrinth.mainRiver.segments.last!.end
            ] + labyrinth.sideRivers.compactMap { $0.segments.last?.end }

            let dynamicGoalRects = ensureThreeGoalRects(from: possibleGoalEnds)

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

        // 1. Find alle endepunkter fra main river + side rivers
        let possibleGoalEnds: [CGPoint] = [
            labyrinth.mainRiver.segments.last!.end
        ] + labyrinth.sideRivers.compactMap { $0.segments.last?.end }

        // 2. Lav rects ud fra disse punkter
        let dynamicGoalRects = ensureThreeGoalRects(from: possibleGoalEnds)

        // 3. Filtrér mål der ligger for tæt på båden
        let excludeCenter = lastBoatPosition ?? position
        let excludeRadius: CGFloat = 20

        var filteredRects = dynamicGoalRects.filter { rect in
            let dx = rect.midX - excludeCenter.x
            let dy = rect.midY - excludeCenter.y
            return sqrt(dx*dx + dy*dy) > excludeRadius
        }

        // 4. Hvis vi mangler mål, generér nye mål på floderne
        if filteredRects.count < 3 {
            let missing = 3 - filteredRects.count

            var newRects: [CGRect] = []

            for _ in 0..<missing {
                // Vælg en flod (main eller side)
                let riverPool = [labyrinth.mainRiver] + labyrinth.sideRivers
                let river = riverPool.randomElement()!

                // Generér et nyt punkt på floden
                let p = randomPoint(on: river)

                let rect = CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40)

                // Undgå overlap med båden
                let dx = rect.midX - excludeCenter.x
                let dy = rect.midY - excludeCenter.y
                let dist = sqrt(dx*dx + dy*dy)

                if dist > excludeRadius {
                    newRects.append(rect)
                }
            }

            filteredRects.append(contentsOf: newRects)
        }

        // 5. Nu har vi 3 mål — generér bogstaver
        var pool = availableLetters.map { String($0) }.filter { letter in
            let correct = useUppercase ? letter.uppercased() : letter.lowercased()
            return correct != targetLetter
        }

        pool.shuffle()

        let wrong1 = useUppercase ? pool[0].uppercased() : pool[0].lowercased()
        let wrong2 = useUppercase ? pool[1].uppercased() : pool[1].lowercased()

        var letters: [String] = [targetLetter, wrong1, wrong2]
        letters.shuffle()

        // 6. Map bogstaver til mål
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




