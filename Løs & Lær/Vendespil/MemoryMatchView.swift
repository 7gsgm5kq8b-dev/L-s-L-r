import SwiftUI
import Combine

// MARK: - Model
struct Card: Identifiable, Equatable {
    let id = UUID()
    let animalName: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

// MARK: - Turn enum (internal so it can be used by published properties)
enum Turn {
    case player1
    case player2 // in singlePlayer this is AI
}

// MARK: - ViewModel
final class MemoryMatchViewModel: ObservableObject {
    // Public state
    @Published private(set) var cards: [Card] = []
    @Published var moves: Int = 0
    @Published var matchesFound: Int = 0
    @Published var disableInput: Bool = false
    @Published var currentTurn: Turn = .player1
    @Published var gridColumns: Int = 4
    @Published var pairCount: Int = 8 // number of pairs (8 = 4x4, 16 = 8x4)
    @Published var isSinglePlayer: Bool = true
    @Published var aiDifficulty: Difficulty = .easy

    // Scores preserved between rounds (same philosophy as TicTacToe)
    @Published var player1Score: Int = 0
    @Published var player2Score: Int = 0

    // Internal
    private var firstSelectedIndex: Int? = nil
    private let flipBackDelay: TimeInterval = 0.7
    private var seenCards: [String: Set<Int>] = [:] // animalName -> indices seen (for AI)
    private var cancellables = Set<AnyCancellable>()

    init(animalNames: [String], pairCount: Int = 8, singlePlayer: Bool = true, aiDifficulty: Difficulty = .easy) {
        self.pairCount = pairCount
        self.isSinglePlayer = singlePlayer
        self.aiDifficulty = aiDifficulty
        self.gridColumns = (pairCount == 8) ? 4 : 8
        setupCards(with: animalNames)
    }

    // MARK: - Setup
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
        // Note: player1Score/player2Score are intentionally NOT reset here
    }

    // Reset scores (call only if you want to clear tournament/session)
    func resetScores() {
        player1Score = 0
        player2Score = 0
    }

    // Helper to generate random animals
    func generateRandomAnimals(count: Int) -> [String] {
        let all = AnimalDatabase.all.map { $0.imageName }
        let take = min(count, all.count)
        return Array(all.shuffled().prefix(take))
    }

    // Pair count mapping (keeps it explicit)
    static func pairCount(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 8   // 4x4
        case .hard: return 16  // 8x4 (32 cards)
        default: return 8
        }
    }

    // MARK: - Choose card (main game flow)
    func chooseCard(at index: Int) {
        guard !disableInput else { return }
        guard cards.indices.contains(index) else { return }
        guard !cards[index].isFaceUp && !cards[index].isMatched else { return }

        // Flip the card
        cards[index].isFaceUp = true
        rememberCard(at: index)

        // If first selected exists -> evaluate pair
        if let first = firstSelectedIndex {
            // Two cards are face up now
            moves += 1
            disableInput = true

            if cards[first].animalName == cards[index].animalName {
                // Match: mark matched, increment matches and current player's score
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.cards[first].isMatched = true
                    self.cards[index].isMatched = true
                    self.matchesFound += 1

                    // Update score for current player
                    switch self.currentTurn {
                    case .player1:
                        self.player1Score += 1
                    case .player2:
                        self.player2Score += 1
                    }

                    // Remove matched from memory
                    self.forgetMatchedCard(self.cards[first].animalName)

                    self.firstSelectedIndex = nil
                    self.disableInput = false

                    // If game complete, leave overlay handling to view
                    // If AI and singleplayer and same player continues, schedule AI again
                    if self.isSinglePlayer && self.currentTurn == .player2 && !self.isGameComplete {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.aiTakeTurnIfNeeded()
                        }
                    }
                }
            } else {
                // Not a match: flip back and switch turn
                DispatchQueue.main.asyncAfter(deadline: .now() + flipBackDelay) {
                    self.cards[first].isFaceUp = false
                    self.cards[index].isFaceUp = false
                    self.firstSelectedIndex = nil
                    self.disableInput = false

                    // Switch turn
                    self.currentTurn = (self.currentTurn == .player1) ? .player2 : .player1

                    // If singleplayer and it's AI's turn, schedule AI
                    if self.isSinglePlayer && self.currentTurn == .player2 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            self.aiTakeTurnIfNeeded()
                        }
                    }
                }
            }
        } else {
            // No first selected yet
            firstSelectedIndex = index
        }
    }

    // MARK: - Remembering cards for AI
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

    // Find known unmatched pair indices (both not matched)
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

    // Find a match index for a given card index if known
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

    // MARK: - AI logic
    private func aiThinkDelay() -> TimeInterval {
        switch aiDifficulty {
        case .easy: return 0.45
        case .hard: return 0.7
        default: return 0.5
        }
    }

    func aiTakeTurnIfNeeded() {
        guard isSinglePlayer else { return }
        guard currentTurn == .player2 else { return }
        guard !disableInput else { return }
        // Schedule AI action
        disableInput = true
        DispatchQueue.main.asyncAfter(deadline: .now() + aiThinkDelay()) {
            self.performAIMove()
        }
    }

    private func performAIMove() {
        // 1) If known pair exists, take it
        if let (i, j) = findKnownUnmatchedPair() {
            if !cards[i].isFaceUp && !cards[i].isMatched {
                cards[i].isFaceUp = true
                rememberCard(at: i)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if !self.cards[j].isFaceUp && !self.cards[j].isMatched {
                    self.cards[j].isFaceUp = true
                    self.rememberCard(at: j)
                }
                self.evaluateAIPair(first: i, second: j)
            }
            return
        }

        // 2) Otherwise flip a random unknown card A
        let unknowns = indicesOfUnknownCards()
        guard !unknowns.isEmpty else {
            self.disableInput = false
            return
        }
        guard let a = unknowns.randomElement() else {
            self.disableInput = false
            return
        }
        // Flip A
        cards[a].isFaceUp = true
        rememberCard(at: a)

        // If we already know a matching index for A, flip it
        if let matchIndex = findMatchForCard(at: a) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.disableInput = false
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if !self.cards[b].isFaceUp && !self.cards[b].isMatched {
                self.cards[b].isFaceUp = true
                self.rememberCard(at: b)
            }
            self.evaluateAIPair(first: a, second: b)
        }
    }

    // Evaluate pair for AI (reuses same match/miss logic)
    private func evaluateAIPair(first: Int, second: Int) {
        // Safety checks
        guard cards.indices.contains(first), cards.indices.contains(second) else {
            self.disableInput = false
            return
        }
        // If already matched by some race, release
        if cards[first].isMatched || cards[second].isMatched {
            self.disableInput = false
            return
        }

        // Increase moves
        moves += 1

        if cards[first].animalName == cards[second].animalName {
            // Match
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                let name = self.cards[first].animalName
                self.cards[first].isMatched = true
                self.cards[second].isMatched = true
                self.matchesFound += 1

                // AI is player2
                self.player2Score += 1

                // forget matched from memory
                self.forgetMatchedCard(name)
                self.disableInput = false
                // AI keeps turn if not finished
                if !self.isGameComplete {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        self.aiTakeTurnIfNeeded()
                    }
                }
            }
        } else {
            // Miss: flip back and switch turn
            DispatchQueue.main.asyncAfter(deadline: .now() + flipBackDelay) {
                self.cards[first].isFaceUp = false
                self.cards[second].isFaceUp = false
                self.disableInput = false
                // switch turn to player1
                self.currentTurn = .player1
            }
        }
    }

    // MARK: - Helpers
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

    @State private var showStartScreen: Bool = true
    @State private var showSuccess: Bool = false
    @State private var successMessage: String = ""
    @State private var showSettingsDifficulty: Difficulty = .easy
    @State private var isSinglePlayerSelection: Bool = true

    // Speak control for cards
    @State private var lastSpokenCardID: UUID? = nil
    @State private var speakingLock: Bool = false

    private let tileSpacing: CGFloat = 12

    // Mapping image->audio (use your full mapping from your project)
    private let imageToAudioMap: [String: String] = [
        // keep full mapping from your project; shortened here for brevity
        "animal_lion": "animal_løve",
        "animal_elephant": "animal_elefant",
        "animal_monkey": "animal_monkey",
        "animal_owl": "animal_owl",
        "animal_tiger": "animal_tiger",
        "animal_giraffe": "animal_giraf",
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

        // Default initial animals (will be replaced by startNewRound)
        let initialPairs = MemoryMatchViewModel.pairCount(for: difficulty)
        let all = AnimalDatabase.all.map { $0.imageName }
        let chosen = Array(all.shuffled().prefix(initialPairs))
        _vm = StateObject(wrappedValue: MemoryMatchViewModel(animalNames: chosen, pairCount: initialPairs, singlePlayer: true, aiDifficulty: difficulty))
    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            // Safe area aware sizing
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let horizontalPadding: CGFloat = 24
            let approxTopArea: CGFloat = 120
            let approxFooterArea: CGFloat = 64
            let verticalReserved = safeTop + approxTopArea + approxFooterArea + safeBottom

            let availableWidth = geo.size.width - horizontalPadding
            let availableHeight = max(0, geo.size.height - verticalReserved)

            // compute columns and rows
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
                        // Game header
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Vendespil")
                                    .font(.largeTitle.bold())
                                Text("Find parene")
                                    .foregroundColor(.gray)
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
                if startImmediately {
                    // Called from AllGames: force singleplayer and start immediately
                    showStartScreen = false
                    vm.isSinglePlayer = true
                    vm.aiDifficulty = difficulty
                    let pairs = MemoryMatchViewModel.pairCount(for: difficulty)
                    vm.pairCount = pairs
                    vm.gridColumns = (pairs == 8) ? 4 : 8
                    let animals = vm.generateRandomAnimals(count: pairs)
                    vm.setupCards(with: animals)
                    // If AI should start sometimes, you can randomize currentTurn here
                    if vm.currentTurn == .player2 {
                        vm.aiTakeTurnIfNeeded()
                    }
                }
            }
            .onChange(of: vm.matchesFound) { _ in
                if vm.isGameComplete {
                    // Determine winner by comparing player scores for this round
                    // (If you prefer to determine winner by who found last pair, adjust accordingly)
                    if vm.player1Score > vm.player2Score {
                        successMessage = "Spiller 1 vandt runden!"
                    } else if vm.player2Score > vm.player1Score {
                        successMessage = "Spiller 2 vandt runden!"
                    } else {
                        successMessage = "Runden endte uafgjort"
                    }

                    AudioVoiceManager.shared.speakWithFallback(aiFile: "win_match") {
                        speechManager.speak(successMessage)
                    }
                    showSuccess = true
                }
            }
            // Pin footer so it's always visible
            .safeAreaInset(edge: .bottom) {
                footerBar
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.001))
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

            Button(action: {
                // New random game with same settings (scores preserved)
                let animals = vm.generateRandomAnimals(count: vm.pairCount)
                vm.setupCards(with: animals)
            }) {
                Text("Nyt spil")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Spacer()

            Button(action: { speechManager.speak("Vendespil. Find parene.") }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .bold))
                    .padding(10)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Card View
    private func cardView(for card: Card, index: Int, size: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                vm.chooseCard(at: index)
            }
            // Speak the animal after flip
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

    // MARK: - Footer Bar (uden dyreikoner)
    private var footerBar: some View {
        HStack(spacing: 16) {
            // Venstre: Moves
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

            // Spiller 1 (tekst + score)
            VStack(alignment: .center, spacing: 2) {
                Text("Spiller 1")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(vm.player1Score)")
                    .font(.headline.bold())
                    .accessibilityLabel("Spiller 1 score")
                    .accessibilityValue("\(vm.player1Score)")
            }

            Spacer(minLength: 12)

            // Spiller 2 (tekst + score)
            VStack(alignment: .center, spacing: 2) {
                Text("Spiller 2")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("\(vm.player2Score)")
                    .font(.headline.bold())
                    .accessibilityLabel("Spiller 2 score")
                    .accessibilityValue("\(vm.player2Score)")
            }

            Spacer()

            // Højre: Matches
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
                Image(systemName: "suit.club.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.gray)
                    .accessibilityHidden(true)
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



    // MARK: - Start Screen
    private var startScreen: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)

            Text("Vendespil")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            Text("Vælg 1 eller 2 spillere og sværhedsgrad.")
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.03))
                .cornerRadius(12)

            HStack(spacing: 16) {
                playerChoiceBox(count: 1, selected: isSinglePlayerSelection)
                    .onTapGesture { isSinglePlayerSelection = true }
                playerChoiceBox(count: 2, selected: !isSinglePlayerSelection)
                    .onTapGesture { isSinglePlayerSelection = false }
            }
            .padding(.horizontal, 24)

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

            Button(action: {
                // Start game with chosen settings
                showStartScreen = false
                vm.isSinglePlayer = isSinglePlayerSelection
                vm.aiDifficulty = showSettingsDifficulty
                let pairs = MemoryMatchViewModel.pairCount(for: showSettingsDifficulty)
                vm.pairCount = pairs
                vm.gridColumns = (pairs == 8) ? 4 : 8
                let animals = vm.generateRandomAnimals(count: pairs)
                vm.setupCards(with: animals)
                // If AI should start, schedule it
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
            isSinglePlayerSelection = true
            showSettingsDifficulty = difficulty
        }
    }

    private func playerChoiceBox(count: Int, selected: Bool) -> some View {
        VStack {
            Image(systemName: count == 1 ? "person.fill" : "person.2.fill")
                .font(.system(size: 44))
                .foregroundColor(selected ? .white : .black)
                .padding(18)
                .background(selected ? Color.green : Color.black.opacity(0.06))
                .cornerRadius(12)

            Text(count == 1 ? "1 spiller" : "2 spillere")
                .font(.headline)
                .foregroundColor(.black)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: selected ? 6 : 0)
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
                    // Start a fully randomized new round with same settings (scores preserved)
                    let animals = vm.generateRandomAnimals(count: vm.pairCount)
                    vm.setupCards(with: animals)
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
