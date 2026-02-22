// MemoryMatchView.swift
// Opdateret version: tre modes + AI flip notification + turn behaviour per mode
import SwiftUI
import Combine
import AVFoundation

// MARK: - Model

struct Card: Identifiable, Equatable {
    let id = UUID()
    let animalName: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

// MARK: - Turn enum

enum Turn {
    case player1
    case player2 // in singlePlayer this is AI
}

// MARK: - MemoryMatchMode (lokal til MemoryMatchView)
enum MemoryMatchMode {
    case solo        // 1 spiller (ingen modstander)
    case vsAI        // 1 spiller mod (spiller mod AI)
    case twoPlayer   // 2 spillere (lokal)
}


// MARK: - Notification name for AI flips (ViewModel -> View)
extension Notification.Name {
    static let memoryMatchSpeakCard = Notification.Name("memoryMatchSpeakCard")
}

// MARK: - ViewModel

final class MemoryMatchViewModel: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published var moves: Int = 0
    @Published var matchesFound: Int = 0
    @Published var disableInput: Bool = false

    // Multiplayer / AI state (tilføjet)
    @Published var currentTurn: Turn = .player1
    @Published var gridColumns: Int = 4
    @Published var pairCount: Int = 8
    @Published var isSinglePlayer: Bool = false // betyder "er der en AI modstander?" — set fra view
    @Published var aiDifficulty: Difficulty = .easy

    // Scores (bevares mellem runder)
    @Published var player1Score: Int = 0
    @Published var player2Score: Int = 0

    private var firstSelectedIndex: Int? = nil
    private let flipBackDelay: TimeInterval = 0.7
    

    
    // For AI memory
    private var seenCards: [String: Set<Int>] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    // AI tuning
    /// aiMistakeChance: Sandsynlighed (0.0..1.0) for at AI laver en "fejl" i stedet for at vælge det kendte rigtige kort.
    /// Højere = mere fejl (fx 0.80 betyder 0% chance for at lave en fejl).
    /// 4‑årig niveau: `aiMistakeChance =0.6 … 0.75, `aiFlipDelayMultiplier= 1.6 … 2.2
    /// Let voksen‑niveau: `aiMistakeChance= 0.25, aiFlipDelayMultiplier = 1.0
    /// Voksen/hard: `aiMistakeChance = 0.05 aiFlipDelayMultiplier = 0.9
        var aiMistakeChance: Double = 0.80

    /// Multiplikator for AI's flip/tænkeforsinkelser. 1.0 = normal, >1 = langsommere.
        var aiFlipDelayMultiplier: Double = 2.0

    

    init(animalNames: [String], pairCount: Int = 8, singlePlayer: Bool = false, aiDifficulty: Difficulty = .easy) {
        self.pairCount = pairCount
        self.isSinglePlayer = singlePlayer
        self.aiDifficulty = aiDifficulty
        self.gridColumns = (pairCount == 8) ? 4 : 8
        setupCards(with: animalNames)
    }

    func setupCards(with animalNames: [String]) {
        var deck: [Card] = []
        for name in animalNames {
            deck.append(Card(animalName: name))
            deck.append(Card(animalName: name))
        }
        deck.shuffle()
        self.cards = deck
        self.moves = 0
        self.matchesFound = 0
        self.firstSelectedIndex = nil
        self.disableInput = false
        self.currentTurn = .player1
        self.seenCards.removeAll()
        // scores intentionally preserved
    }

    func resetScores() {
        player1Score = 0
        player2Score = 0
    }

    func generateRandomAnimals(count: Int) -> [String] {
        let all = AnimalDatabase.all.map { $0.imageName }
        let take = min(count, all.count)
        return Array(all.shuffled().prefix(take))
    }

    static func pairCount(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 8
        case .hard: return 16
        default: return 8
        }
    }

    // MARK: - Choose card (main game flow)
    func chooseCard(at index: Int) {
        guard !disableInput else { return }
        guard cards.indices.contains(index) else { return }
        guard !cards[index].isFaceUp && !cards[index].isMatched else { return }

        cards[index].isFaceUp = true
        rememberCard(at: index)

        if let first = firstSelectedIndex {
            moves += 1
            disableInput = true

            if cards[first].animalName == cards[index].animalName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.cards[first].isMatched = true
                    self.cards[index].isMatched = true
                    self.matchesFound += 1

                    // Update score for current player if multiplayer/AI mode
                    switch self.currentTurn {
                    case .player1:
                        self.player1Score += 1
                    case .player2:
                        self.player2Score += 1
                    }

                    self.forgetMatchedCard(self.cards[first].animalName)
                    self.firstSelectedIndex = nil
                    self.disableInput = false

                    // If singleplayer (AI) and AI keeps turn, schedule AI
                    if self.isSinglePlayer && self.currentTurn == .player2 && !self.isGameComplete {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.aiTakeTurnIfNeeded()
                        }
                    }
                }
            } else {
                let effectiveFlipBack = flipBackDelay * (isSinglePlayer && currentTurn == .player2 ? aiFlipDelayMultiplier : 1.0)

                DispatchQueue.main.asyncAfter(deadline: .now() + effectiveFlipBack) {
                    self.cards[first].isFaceUp = false
                    self.cards[index].isFaceUp = false
                    self.firstSelectedIndex = nil
                    self.disableInput = false

                    // Switch turn (only relevant in multiplayer/AI modes)
                    self.currentTurn = (self.currentTurn == .player1) ? .player2 : .player1

                    if self.isSinglePlayer && self.currentTurn == .player2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) {
                            self.aiTakeTurnIfNeeded()
                        }
                    }
                }

            }
        } else {
            firstSelectedIndex = index
        }
    }

    // MARK: - AI memory helpers
    private func rememberCard(at index: Int) {
        guard cards.indices.contains(index) else { return }
        let name = cards[index].animalName
        var set = seenCards[name] ?? Set<Int>()
        set.insert(index)
        seenCards[name] = set
    }

    private func forgetMatchedCard(_ name: String) {
        seenCards[name] = nil
    }

    private func findKnownUnmatchedPair() -> (Int, Int)? {
        for (name, indices) in seenCards {
            let valid = indices.filter { idx in
                cards.indices.contains(idx) && !cards[idx].isMatched
            }
            if valid.count >= 2 {
                let arr = Array(valid)
                return (arr[0], arr[1])
            }
        }
        return nil
    }

    private func findMatchForCard(at index: Int) -> Int? {
        guard cards.indices.contains(index) else { return nil }
        let name = cards[index].animalName
        let indices = seenCards[name] ?? Set<Int>()
        for i in indices {
            if i != index && cards.indices.contains(i) && !cards[i].isMatched {
                return i
            }
        }
        return nil
    }

    private func indicesOfUnknownCards() -> [Int] {
        return cards.indices.filter { idx in
            !cards[idx].isFaceUp && !cards[idx].isMatched
        }
    }

    // MARK: - AI logic (kopieret fra 202000 med små tilpasninger)
    private func aiThinkDelay() -> TimeInterval {
        let base: TimeInterval
        switch aiDifficulty {
        case .easy: base = 0.35
        case .hard: base = 0.35
        default: base = 0.5
        }
        // Gør AI langsommere ved at gange med multiplikator
        return base * max(1.0, aiFlipDelayMultiplier)
    }


    func aiTakeTurnIfNeeded() {
        guard isSinglePlayer else { return }
        guard currentTurn == .player2 else { return }
        guard !disableInput else { return }

        disableInput = true
        DispatchQueue.main.asyncAfter(deadline: .now() + aiThinkDelay()) {
            self.performAIMove()
        }
    }

    private func performAIMove() {
        // 1) known pair
        if let (i, j) = findKnownUnmatchedPair() {
            // With some probability, make a mistake and flip a random unknown instead
            if Double.random(in: 0...1) < aiMistakeChance {
                let unknowns = indicesOfUnknownCards()
                if let randomIdx = unknowns.randomElement() {
                    cards[randomIdx].isFaceUp = true
                    rememberCard(at: randomIdx)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) { [weak self] in
                        guard let self = self else { return }
                        // Try to continue from this random flip
                        if let matchIndex = self.findMatchForCard(at: randomIdx) {
                            if !self.cards[matchIndex].isFaceUp && !self.cards[matchIndex].isMatched {
                                self.cards[matchIndex].isFaceUp = true
                                self.rememberCard(at: matchIndex)
                            }
                            self.evaluateAIPair(first: randomIdx, second: matchIndex)
                        } else {
                            // Flip another random if no known match
                            let otherUnknowns = unknowns.filter { $0 != randomIdx }
                            if let b = otherUnknowns.randomElement() {
                                if !self.cards[b].isFaceUp && !self.cards[b].isMatched {
                                    self.cards[b].isFaceUp = true
                                    self.rememberCard(at: b)
                                }
                                self.evaluateAIPair(first: randomIdx, second: b)
                            } else {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * self.aiFlipDelayMultiplier) { [weak self] in
                                    guard let self = self else { return }
                                    self.disableInput = false
                                }
                            }
                        }
                    }
                    return
                }
            }

            // Normal (non-mistake) behaviour: flip i then j
            if !cards[i].isFaceUp && !cards[i].isMatched {
                cards[i].isFaceUp = true
                rememberCard(at: i)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) { [weak self] in
                guard let self = self else { return }
                if !self.cards[j].isFaceUp && !self.cards[j].isMatched {
                    self.cards[j].isFaceUp = true
                    self.rememberCard(at: j)
                }
                self.evaluateAIPair(first: i, second: j)
            }
            return
        }

        // 2) flip random unknown A
        let unknowns = indicesOfUnknownCards()
        guard !unknowns.isEmpty else {
            self.disableInput = false
            return
        }
        guard let a = unknowns.randomElement() else {
            self.disableInput = false
            return
        }

        cards[a].isFaceUp = true
        rememberCard(at: a)

        // If we already know a matching index for A, maybe make a mistake and ignore it
        if let matchIndex = findMatchForCard(at: a) {
            if Double.random(in: 0...1) < aiMistakeChance {
                // choose another random unknown instead of the known match
                let otherUnknowns = unknowns.filter { $0 != a }
                if let b = otherUnknowns.randomElement() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) { [weak self] in
                        guard let self = self else { return }
                        if !self.cards[b].isFaceUp && !self.cards[b].isMatched {
                            self.cards[b].isFaceUp = true
                            self.rememberCard(at: b)
                        }
                        self.evaluateAIPair(first: a, second: b)
                    }
                    return
                }
            }

            // Normal behaviour: flip the known match
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) { [weak self] in
                guard let self = self else { return }
                if !self.cards[matchIndex].isFaceUp && !self.cards[matchIndex].isMatched {
                    self.cards[matchIndex].isFaceUp = true
                    self.rememberCard(at: matchIndex)
                }
                self.evaluateAIPair(first: a, second: matchIndex)
            }
            return
        }

        // Else flip another random unknown B
        let otherUnknowns = unknowns.filter { $0 != a }
        guard let b = otherUnknowns.randomElement() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * self.aiFlipDelayMultiplier) { [weak self] in
                guard let self = self else { return }
                self.disableInput = false
            }
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * self.aiFlipDelayMultiplier) { [weak self] in
            guard let self = self else { return }
            if !self.cards[b].isFaceUp && !self.cards[b].isMatched {
                self.cards[b].isFaceUp = true
                self.rememberCard(at: b)
            }
            self.evaluateAIPair(first: a, second: b)
        }
    }


    private func evaluateAIPair(first: Int, second: Int) {
        guard cards.indices.contains(first), cards.indices.contains(second) else {
            self.disableInput = false
            return
        }
        if cards[first].isMatched || cards[second].isMatched {
            self.disableInput = false
            return
        }

        moves += 1

        if cards[first].animalName == cards[second].animalName {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                let name = self.cards[first].animalName
                self.cards[first].isMatched = true
                self.cards[second].isMatched = true
                self.matchesFound += 1
                self.player2Score += 1
                self.forgetMatchedCard(name)
                self.disableInput = false

                if !self.isGameComplete {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.aiTakeTurnIfNeeded()
                    }
                }
            }
        } else {
            let effectiveFlipBack = flipBackDelay * (isSinglePlayer && currentTurn == .player2 ? aiFlipDelayMultiplier : 1.0)

            DispatchQueue.main.asyncAfter(deadline: .now() + effectiveFlipBack) {
                self.cards[first].isFaceUp = false
                self.cards[second].isFaceUp = false
                self.disableInput = false
                self.currentTurn = .player1
            }

        }
    }

    var isGameComplete: Bool {
        cards.allSatisfy { $0.isMatched }
    }
}

// MARK: - MemoryMatchView (View)

struct MemoryMatchView: View {
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    @StateObject private var vm: MemoryMatchViewModel
    @StateObject private var speechManager = SpeechManager()
    
    @State private var audioPlayer: AVAudioPlayer? = nil

    //enable allgamemode
    @EnvironmentObject var session: GameSessionManager

    // UI state
    @State private var showStartScreen: Bool = true
    @State private var showSuccessButton: Bool = false
    @State private var showSuccess: Bool = false
    @State private var successMessage: String = ""
    @State private var showSettingsDifficulty: Difficulty = .easy

    // New: selected game mode
    @State private var selectedMode: MemoryMatchMode = .solo

    // Speak control for cards
    @State private var lastSpokenCardID: UUID? = nil
    @State private var speakingLock: Bool = false

    // Turn pulse animation
    @State private var turnPulse: Bool = false

    private let tileSpacing: CGFloat = 12

    // Mapping image->audio (keep your mapping)
    private let imageToAudioMap: [String: String] = [
        "animal_antelope": "animal_antelope",
        "animal_armadillo": "animal_armadillo",
        "animal_axolotl": "animal_axolotl",
        "animal_bat": "animal_bat",
        "animal_beaver": "animal_beaver",
        "animal_buffalo": "animal_buffalo",
        "animal_butterfly": "animal_butterfly",
        "animal_cat": "animal_cat",
        "animal_chameleon": "animal_chameleon",
        "animal_cheetah": "animal_cheetah",
        "animal_chimpanzee": "animal_chimpanzee",
        "animal_cow": "animal_cow",
        "animal_crab": "animal_crab",
        "animal_dog": "animal_dog",
        "animal_dolphin": "animal_dolphin",
        "animal_elephant": "animal_elephant",
        "animal_flamingo": "animal_flamingo",
        "animal_flying_fish": "animal_flying_fish",
        "animal_giraffe": "animal_giraffe",
        "animal_gorilla": "animal_gorilla",
        "animal_hedgehog": "animal_hedgehog",
        "animal_hippo": "animal_hippo",
        "animal_hummingbird": "animal_hummingbird",
        "animal_hyena": "animal_hyena",
        "animal_jellyfish": "animal_jellyfish",
        "animal_kangaroo": "animal_kangaroo",
        "animal_koala": "animal_koala",
        "animal_lemur": "animal_lemur",
        "animal_lion": "animal_lion",
        "animal_mandrill": "animal_mandrill",
        "animal_meerkat": "animal_meerkat",
        "animal_mole": "animal_mole",
        "animal_mongoose": "animal_mongoose",
        "animal_monkey": "animal_monkey",
        "animal_moose": "animal_moose",
        "animal_octopus": "animal_octopus",
        "animal_okapi": "animal_okapi",
        "animal_orca": "animal_orca",
        "animal_ostrich": "animal_ostrich",
        "animal_otter": "animal_otter",
        "animal_owl": "animal_owl",
        "animal_panda": "animal_panda",
        "animal_pangolin": "animal_pangolin",
        "animal_parrot": "animal_parrot",
        "animal_penguin": "animal_penguin",
        "animal_polar_bear": "animal_polar_bear",
        "animal_puffin": "animal_puffin",
        "animal_quokka": "animal_quokka",
        "animal_rabbit": "animal_rabbit",
        "animal_raccoon": "animal_raccoon",
        "animal_reindeer": "animal_reindeer",
        "animal_rhino": "animal_rhino",
        "animal_seal": "animal_seal",
        "animal_sheep": "animal_sheep",
        "animal_sloth": "animal_sloth",
        "animal_slow_loris": "animal_slow_loris",
        "animal_snow_leopard": "animal_snow_leopard",
        "animal_squirrel": "animal_squirrel",
        "animal_swordfish": "animal_swordfish",
        "animal_tiger": "animal_tiger",
        "animal_toucan": "animal_toucan",
        "animal_turtle": "animal_turtle",
        "animal_viscacha": "animal_viscacha",
        "animal_vulture": "animal_vulture",
        "animal_walrus": "animal_walrus",
        "animal_wild_boar": "animal_wild_boar",
        "animal_wolverine": "animal_wolverine",
        "animal_zebra": "animal_zebra"
    ]


    // MARK: - Init
    init(
        difficulty: Difficulty,
        startImmediately: Bool = false,
        onExit: @escaping () -> Void,
        onBackToHub: @escaping () -> Void
    ) {
        self.difficulty = difficulty
        self.startImmediately = startImmediately
        self.onExit = onExit
        self.onBackToHub = onBackToHub

        let initialPairs = MemoryMatchViewModel.pairCount(for: difficulty)
        let all = AnimalDatabase.all.map { $0.imageName }
        let chosen = Array(all.shuffled().prefix(initialPairs))

        _vm = StateObject(wrappedValue: MemoryMatchViewModel(animalNames: chosen, pairCount: initialPairs, singlePlayer: false, aiDifficulty: difficulty))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let horizontalPadding: CGFloat = 24
            let approxTopArea: CGFloat = 120
            let approxFooterArea: CGFloat = 64
            let verticalReserved = safeTop + approxTopArea + approxFooterArea + safeBottom
            let availableWidth = geo.size.width - horizontalPadding
            let availableHeight = max(0, geo.size.height - verticalReserved)

            let cols = vm.gridColumns
            let rows = max(1, (vm.pairCount * 2) / cols)
            let cardWidth = (availableWidth - CGFloat(cols - 1) * tileSpacing) / CGFloat(cols)
            let cardHeight = (availableHeight - CGFloat(rows - 1) * tileSpacing) / CGFloat(rows)
            let cardSize = max(48, min(cardWidth, cardHeight))

            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 8) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    if showStartScreen && !startImmediately {
                        startScreen
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        // Header with optional turnIndicator
                        HStack {
                            Spacer()
                            if selectedMode != .solo { // show banana/apple only in vsAI or twoPlayer
                                turnIndicator
                                    .padding(.bottom, 6)
                            }
                            Spacer()
                        }
                        .padding(.top, 6)
                        .padding(.horizontal, 12)

                        // Grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: tileSpacing), count: cols), spacing: tileSpacing) {
                            ForEach(vm.cards.indices, id: \.self) { idx in
                                cardView(for: vm.cards[idx], index: idx, size: cardSize)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                        Spacer(minLength: 8)
                    }
                }

                if showSuccess {
                    successOverlay
                }
            }
            .onAppear {
                speechManager.preload()

                // Listen for AI flip notifications so view can speak AI‑flipped cards
                NotificationCenter.default.addObserver(forName: .memoryMatchSpeakCard, object: nil, queue: .main) { note in
                    // Kun tal AI‑vendte kort hvis vi er i solo mode (barnet spiller alene)
                    guard selectedMode == .solo else { return }

                    if let card = note.object as? Card {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                            speakAnimalIfNeeded(for: card)
                        }
                    }
                }

                if startImmediately {
                    // AllGames: start MemoryMatch i SOLO mode, skip startskærm og brug global score
                    showStartScreen = false
                    selectedMode = .solo

                    // Ingen AI i solo mode: isSinglePlayer = false (i din ViewModel betyder isSinglePlayer "er der en AI modstander?")
                    vm.isSinglePlayer = false
                    vm.aiDifficulty = difficulty // hold sync, selvom ikke brugt i solo

                    // Brug global score fra session som player1Score (samme mønster som i TicTacToeView)
                    vm.player1Score = session.allGameScore

                    // Opsæt kort og grid som normalt
                    let pairs = MemoryMatchViewModel.pairCount(for: difficulty)
                    vm.pairCount = pairs
                    vm.gridColumns = (pairs == 8) ? 4 : 8
                    let animals = vm.generateRandomAnimals(count: pairs)
                    vm.setupCards(with: animals)

                    // Ingen AI tur i solo, så vi kalder ikke vm.aiTakeTurnIfNeeded()
                } else {
                    // Normal flow når ikke startet fra AllGames
                    showSettingsDifficulty = difficulty
                }
            }

            .onChange(of: vm.matchesFound) { _ in
                if vm.isGameComplete {
                    if selectedMode == .solo {
                        // Enkel solo‑besked og/eller solo‑audio
                        successMessage = "Flot, du vandt!"
                        // Hvis du har en solo MP3, skift "Solo_Win" til dit filnavn; ellers fallback til TTS
                        if Bundle.main.url(forResource: "Solo_Win", withExtension: "mp3") != nil {
                            playVictoryAudio(named: "Solo_Win", fallbackText: successMessage)
                        } else {
                            speechManager.speak(successMessage)
                        }
                    } else {
                        // Multiplayer / vsAI: brug de specifikke vindere eller uafgjort lyde
                        if vm.player1Score > vm.player2Score {
                            successMessage = "Spiller 1 vandt runden!"
                            playVictoryAudio(named: "Win_Player1", fallbackText: successMessage)
                        } else if vm.player2Score > vm.player1Score {
                            successMessage = "Spiller 2 vandt runden!"
                            playVictoryAudio(named: "Win_Player2", fallbackText: successMessage)
                        } else {
                            successMessage = "Runden endte uafgjort"
                            playVictoryAudio(named: "Memory_Draw", fallbackText: successMessage)
                        }
                    }

                    showSuccess = true
                }
            }


            // Turn change: only play banana/apple turn audio when mode is vsAI or twoPlayer
            .onChange(of: vm.currentTurn) { newTurn in
                guard selectedMode != .solo else { return } // only in vsAI or twoPlayer
                switch newTurn {
                case .player1:
                    AudioVoiceManager.shared.speakWithFallback(aiFile: "Turn_Banana") {
                        speechManager.speak("Din tur banan")
                    }
                case .player2:
                    AudioVoiceManager.shared.speakWithFallback(aiFile: "Turn_Apple") {
                        speechManager.speak("Din tur æble")
                    }
                }
                // Pulse animation
                withAnimation(.easeOut(duration: 0.28)) {
                    turnPulse = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.easeIn(duration: 0.18)) {
                        turnPulse = false
                    }
                }
            }
            // Pin footer only when game is running or startImmediately
            .safeAreaInset(edge: .bottom) {
                Group {
                    if !showStartScreen || startImmediately {
                        footerBar
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.001))
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { onBackToHub() }) {
                Text("← Tilbage")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(10)
            }

            // Nyt spil ved siden af Tilbage
            Button(action: {
                let animals = vm.generateRandomAnimals(count: vm.pairCount)
                vm.setupCards(with: animals)
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Nyt spil")
                        .font(.headline.bold())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.06))
                .cornerRadius(10)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Turn Indicator
    private var turnIndicator: some View {
        let isPlayer1 = vm.currentTurn == .player1
        let label: String = {
            if selectedMode == .vsAI {
                return isPlayer1 ? "Din tur — Banan" : "Computerens tur — Æble"
            } else {
                return isPlayer1 ? "Spiller 1s tur — Banan" : "Spiller 2s tur — Æble"
            }
        }()

        return HStack(spacing: 10) {
            Image(isPlayer1 ? "food_banana" : "food_apple")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(label)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(isPlayer1 ? Color.green : Color.blue))
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
        .scaleEffect(turnPulse ? 1.04 : 1.0)
        .accessibilityLabel(label)
    }

    // MARK: - Card View
    private func cardView(for card: Card, index: Int, size: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                vm.chooseCard(at: index)
            }

            // Speak the animal after flip (small delay)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard vm.cards.indices.contains(index) else { return }
                let updated = vm.cards[index]
                speakAnimalIfNeeded(for: updated)
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 214/255, green: 238/255, blue: 255/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

                if card.isFaceUp || card.isMatched {
                    Image(card.animalName)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.12)
                        .accessibilityLabel(localizedAnimalName(for: card.animalName))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .padding(size * 0.12)
                        .overlay(
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: size * 0.32))
                                .foregroundColor(Color.blue.opacity(0.6))
                        )
                }

                if card.isMatched {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 3)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(vm.disableInput || card.isMatched)
    }

    // MARK: - Speak helpers
    private func speakAnimalIfNeeded(for card: Card) {
        // Avoid repeating same card rapidly or overlapping speech
        guard selectedMode == .solo else { return }
        guard lastSpokenCardID != card.id, !speakingLock else { return }
        lastSpokenCardID = card.id
        speakingLock = true

        let aiFile = imageToAudioMap[card.animalName]
        let fallbackText = localizedAnimalName(for: card.animalName)

        if let ai = aiFile {
            AudioVoiceManager.shared.speakWithFallback(aiFile: ai) {
                DispatchQueue.main.async {
                    self.speechManager.speak(fallbackText)
                }
            }
        } else {
            speechManager.speak(fallbackText)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.speakingLock = false
        }
    }

    private func localizedAnimalName(for animalName: String) -> String {
        if let animal = AnimalDatabase.all.first(where: { $0.imageName == animalName }) {
            return animal.displayName
        }
        let base = animalName.replacingOccurrences(of: "animal_", with: "")
        return base.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Speak helpers WIN
    private func playVictoryAudio(named fileName: String, fallbackText: String) {
        // Forsøg at finde filen i bundle
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            // fallback til TTS hvis fil mangler
            speechManager.speak(fallbackText)
            return
        }

        do {
            // Sørg for at lyd kan afspilles (duck others så UI‑lyde ikke forsvinder helt)
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            // Hvis afspilning fejler, fallback til TTS
            speechManager.speak(fallbackText)
        }
    }


    // MARK: - Footer Bar
    private var footerBar: some View {
        HStack(spacing: 16) {
            // Moves
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Træk")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("\(vm.moves)")
                        .font(.headline.bold())
                        .accessibilityLabel("Træk")
                        .accessibilityValue("\(vm.moves)")
                }
            }

            Spacer()

            // Player 1 (vis kun i vsAI eller twoPlayer)
            if selectedMode != .solo {
                HStack(spacing: 10) {
                    Image("food_banana")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spiller 1")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(vm.player1Score)")
                            .font(.headline.bold())
                            .accessibilityLabel("Spiller 1 score")
                            .accessibilityValue("\(vm.player1Score)")
                    }
                }
            }


            Spacer(minLength: 12)

            // Player 2 (vis kun i vsAI eller twoPlayer)
            if selectedMode != .solo {
                HStack(spacing: 10) {
                    Image("food_apple")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spiller 2")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(vm.player2Score)")
                            .font(.headline.bold())
                            .accessibilityLabel("Spiller 2 score")
                            .accessibilityValue("\(vm.player2Score)")
                    }
                }
            }


            Spacer()

            // Matches (vis kun i solo)
            if selectedMode == .solo {
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Stik")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(vm.matchesFound)")
                            .font(.headline.bold())
                            .accessibilityLabel("Stik")
                            .accessibilityValue("\(vm.matchesFound)")
                    }
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            Group {
                if #available(iOS 15.0, *) {
                    Color(.systemBackground).opacity(0.95)
                } else {
                    Color.white
                }
            }
        )
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }

    // MARK: - Start Screen (grafiske bokse)
    private var startScreen: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 40)

            Text("Vendespil")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            Text("Vælg spiltype og sværhedsgrad.")
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.03))
                .cornerRadius(12)

            // Tre grafiske bokse
            GeometryReader { geo in
                let boxWidth = max(120, min(360, (geo.size.width - 48) / 3))
                HStack(spacing: 12) {
                    // Solo (1 spiller, ingen modstander)
                    modeBox(
                        title: "1 spiller",
                        subtitle: "Spil alene — ingen modstander",
                        systemImage: "person.fill",
                        isSelected: selectedMode == .solo,
                        width: boxWidth
                    ) {
                        selectedMode = .solo
                    }

                    // Vs AI (1 spiller mod)
                    modeBox(
                        title: "1 spiller mod",
                        subtitle: "Spil mod computeren",
                        systemImage: "person.crop.circle.badge.checkmark",
                        isSelected: selectedMode == .vsAI,
                        width: boxWidth
                    ) {
                        selectedMode = .vsAI
                    }

                    // Two player
                    modeBox(
                        title: "2 spiller",
                        subtitle: "To spillere lokalt",
                        systemImage: "person.2.fill",
                        isSelected: selectedMode == .twoPlayer,
                        width: boxWidth
                    ) {
                        selectedMode = .twoPlayer
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 140)
            .padding(.horizontal, 16)

            // Difficulty buttons
            HStack(spacing: 12) {
                Button(action: { showSettingsDifficulty = .easy }) {
                    Text("Let")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(showSettingsDifficulty == .easy ? Color.green : Color.black.opacity(0.06))
                        .foregroundColor(showSettingsDifficulty == .easy ? .white : .black)
                        .cornerRadius(12)
                }
                Button(action: { showSettingsDifficulty = .hard }) {
                    Text("Svær")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(showSettingsDifficulty == .hard ? Color.green : Color.black.opacity(0.06))
                        .foregroundColor(showSettingsDifficulty == .hard ? .white : .black)
                        .cornerRadius(12)
                }
            }

            // Startknap
            Button(action: {
                // Start game with chosen settings
                showStartScreen = false

                // Configure VM based on selectedMode
                switch selectedMode {
                case .solo:
                    vm.isSinglePlayer = false
                case .vsAI:
                    vm.isSinglePlayer = true
                    vm.aiDifficulty = showSettingsDifficulty
                    // Tuning for child level
                    vm.aiMistakeChance = 0.75            // 60% chance for at lave "fejl"
                    vm.aiFlipDelayMultiplier = 2.0      // ca. 1.8x langsommere flips
                case .twoPlayer:
                    vm.isSinglePlayer = false
                }

                let pairs = MemoryMatchViewModel.pairCount(for: showSettingsDifficulty)
                vm.pairCount = pairs
                vm.gridColumns = (pairs == 8) ? 4 : 8
                let animals = vm.generateRandomAnimals(count: pairs)
                vm.setupCards(with: animals)

                if vm.isSinglePlayer && vm.currentTurn == .player2 {
                    vm.aiTakeTurnIfNeeded()
                }
            }) {
                Text("Spil")
                    .font(.title2.bold())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 40)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
        .onAppear {
            // default selection
            if selectedMode == nil {
                selectedMode = .solo
            }
            showSettingsDifficulty = difficulty
        }
    }

    // MARK: - Mode box helper
    @ViewBuilder
    private func modeBox(title: String, subtitle: String, systemImage: String, isSelected: Bool, width: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(isSelected ? .white : .black)
                    .padding(12)
                    .background(isSelected ? Color.green.opacity(0.95) : Color.black.opacity(0.06))
                    .clipShape(Circle())

                Text(title)
                    .font(.headline)
                    .foregroundColor(isSelected ? .white : .black)

                Text(subtitle)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(isSelected ? Color.white.opacity(0.9) : Color.gray)
                    .lineLimit(2)
                    .frame(maxWidth: width * 0.9)
            }
            .padding(12)
            .frame(width: width, height: 120)
            .background(isSelected ? Color.green : Color.white)
            .cornerRadius(12)
            .shadow(color: isSelected ? Color.black.opacity(0.18) : Color.black.opacity(0.04), radius: isSelected ? 8 : 4, x: 0, y: 4)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green.opacity(0.9) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }


    private func isSinglePlayerSelectionDefault() {
        // default selection
        selectedMode = .solo
        showSettingsDifficulty = difficulty
    }

    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(successMessage)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                Button(action: {
                    showSuccess = false
                    showSuccessButton = false

                    if !startImmediately {
                        // Normal flow: genstart MemoryMatch lokalt
                        // Nulstil scores for multiplayer modes hvis ønsket
                        if selectedMode != .solo {
                            vm.resetScores()
                        }

                        // Genstart runden lokalt
                        let animals = vm.generateRandomAnimals(count: vm.pairCount)
                        vm.setupCards(with: animals)

                        // Sørg for at turen starter ved player1
                        vm.currentTurn = .player1

                        // Hvis vi spiller mod AI og AI starter, trig AI
                        if vm.isSinglePlayer && vm.currentTurn == .player2 {
                            vm.aiTakeTurnIfNeeded()
                        }
                    } else {
                        // AllGames flow: signaler til AllGames at spillet er færdigt
                        // AllGamesModeView's onExit closure håndterer nextGame() og session.increment()
                        onExit()
                    }
                }) {
                    Text("Spil igen")
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
    }
}

// MARK: - Preview
struct MemoryMatchView_Previews: PreviewProvider {
    static var previews: some View {
        MemoryMatchView(
            difficulty: .easy,
            startImmediately: false,
            onExit: {},
            onBackToHub: {}
        )
    }
}
