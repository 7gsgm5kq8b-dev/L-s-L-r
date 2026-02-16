import SwiftUI
import AVFoundation
import Combine

// MARK: - Enums & Models

enum Player {
    case none
    case lion      // spiller 1 (brugeren i singleplayer)
    case elephant  // spiller 2 eller AI
}

// NOTE: Difficulty forventes defineret i din fælles kodebase (bruges af Animal osv.)

// MARK: - TicTacToeView

struct TicTacToeView: View {
    // Inputs (samme signatur som AnimalGameView)
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void
    
    @EnvironmentObject var session: GameSessionManager


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
    }

    // MARK: - State
    @State private var gameStarted: Bool = false
    @State private var board: [Player] = Array(repeating: .none, count: 9)
    @State private var currentPlayer: Player = .lion
    @State private var modeSinglePlayer: Bool = true // true = 1 player, false = 2 player
    @State private var aiDifficulty: Difficulty = .easy
    @State private var showSuccess: Bool = false
    @State private var successMessage: String = ""
    @State private var showSuccessButton: Bool = false
    @State private var showHelp: Bool = false
    @State private var debugMode: Bool = false
    @State private var disableInput: Bool = false
    @State private var selectedPieceIndex: Int? = nil // index på valgt egen brik når man skal flytte
    // Score tællere (bevares mellem runder)
    @State private var lionScore: Int = 0
    @State private var elephantScore: Int = 0
    @State private var drawCount: Int = 0
    @State private var lastSpokenPlayer: Player? = nil



    @StateObject private var speechManager = SpeechManager()

    // MARK: - Layout constants
    private let gridSpacing: CGFloat = 12
    private let cellSize: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                if gameStarted {
                    VStack {
                        topBar
                            .padding(.top, 18)
                            .padding(.horizontal, 16)

                        Spacer(minLength: 8)

                        HStack(spacing: 8) {
                            if currentPlayer == .lion {
                                Image("animal_lion")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                            } else if currentPlayer == .elephant {
                                Image("animal_elephant")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                            }

                            Text(turnText)
                                .font(.title2.bold())
                                .foregroundColor(.black)
                        }
                        .padding(.vertical, 6)


                        boardView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.horizontal, 24)

                        Spacer(minLength: 8)

                        HStack {
                            Spacer()
                            scoreLegend
                            Spacer()
                        }
                        .padding(.bottom, 20)
                    }
                } else {
                    startScreen
                }

                if showSuccess {
                    successOverlay
                }

                if showHelp && gameStarted {
                    helpOverlay
                }
            }
            .onAppear {
                speechManager.preload()
                if startImmediately {
                    // AllGames: force singleplayer and skip start screen
                    modeSinglePlayer = true
                    gameStarted = true
                    aiDifficulty = difficulty
                    startNewRound()
                } else {
                    // normal flow: show start screen
                    speakIntro()
                }
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: { onBackToHub() }) {
                Text("← Tilbage")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(10)
            }

            Spacer()

            Button(action: { speechManager.speak(turnText) }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .bold))
                    .padding(10)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Start Screen
    private var startScreen: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 60)

            Text("Kryds og Bolle")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            Text("Vælg 1 eller 2 spillere og sværhedsgrad. Løve vs Elefant.")
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.03))
                .cornerRadius(12)

            HStack(spacing: 16) {
                playerChoiceBox(count: 1, selected: modeSinglePlayer)
                    .onTapGesture { modeSinglePlayer = true }

                playerChoiceBox(count: 2, selected: !modeSinglePlayer)
                    .onTapGesture { modeSinglePlayer = false }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button(action: { aiDifficulty = .easy }) {
                    Text("Let")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(aiDifficulty == .easy ? Color.green : Color.black.opacity(0.06))
                        .foregroundColor(aiDifficulty == .easy ? .white : .black)
                        .cornerRadius(12)
                }

                Button(action: { aiDifficulty = .hard }) {
                    Text("Svær")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 22)
                        .background(aiDifficulty == .hard ? Color.green : Color.black.opacity(0.06))
                        .foregroundColor(aiDifficulty == .hard ? .white : .black)
                        .cornerRadius(12)
                }
            }

            Button(action: {
                gameStarted = true
                // ensure singleplayer default if AllGames later forces it
                startNewRound()
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
            modeSinglePlayer = true
            aiDifficulty = difficulty
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

    // MARK: - Board View
    private var boardView: some View {
        VStack(spacing: gridSpacing) {
            ForEach(0..<3) { row in
                HStack(spacing: gridSpacing) {
                    ForEach(0..<3) { col in
                        let idx = row * 3 + col
                        cellView(index: idx)
                    }
                }
            }
        }
        .padding(12)
    }

    private func cellView(index: Int) -> some View {
        Button(action: { cellTapped(index: index) }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 214/255, green: 238/255, blue: 255/255)) // #D6EEFF
                    .frame(width: cellSize, height: cellSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)



                if board[index] == .lion {
                    Image("animal_lion")
                        .resizable()
                        .scaledToFit()
                        .frame(width: cellSize * 0.7, height: cellSize * 0.7)
                        .transition(.scale)
                } else if board[index] == .elephant {
                    Image("animal_elephant")
                        .resizable()
                        .scaledToFit()
                        .frame(width: cellSize * 0.7, height: cellSize * 0.7)
                        .transition(.scale)
                }

                // Highlight selected piece
                if let sel = selectedPieceIndex, sel == index {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 4)
                        .frame(width: cellSize, height: cellSize)
                        .animation(.easeInOut, value: selectedPieceIndex)
                }
            }
        }
        .disabled(disableInput || (board[index] != .none && !(isCurrentPlayersPiece(at: index) && canSelectPiece())) || showSuccess)
    }

    // MARK: - Score Legend (placeholder)
    private var scoreLegend: some View {
        HStack(spacing: 18) {
            HStack(spacing: 8) {
                Image("animal_lion")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Løve")
                        .font(.subheadline.bold())
                    Text("\(startImmediately ? session.allGameScore : lionScore)")
                        .font(.headline)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image("animal_elephant")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Elefant")
                        .font(.subheadline.bold())
                    Text("\(elephantScore)")
                        .font(.headline)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.gray)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uafgjort")
                        .font(.subheadline.bold())
                    Text("\(drawCount)")
                        .font(.headline)
                }
            }
        }
        .padding(.horizontal, 8)
        .foregroundColor(.black)
    }


    // MARK: - Help Overlay
    private var helpOverlay: some View {
        VStack {
            Spacer()
            Text("Sæt tre på stribe for at vinde.")
                .font(.title2.bold())
                .padding()
                .background(Color.white)
                .cornerRadius(12)
            Spacer()
        }
        .background(Color.black.opacity(0.25).ignoresSafeArea())
        .onTapGesture { showHelp = false }
    }

    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(successMessage)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                if showSuccessButton {

                    Button(action: {

                        showSuccess = false
                        showSuccessButton = false

                        if !startImmediately {
                            startNewRound()
                        } else {
                            onExit()   // AllGame-mode → videre til næste spil
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

            }
            .padding()
        }
    }

    // MARK: - Game Logic

    private var turnText: String {
        if showSuccess { return "" }
        switch currentPlayer {
        case .lion:
            return modeSinglePlayer ? "Din tur (Løve)" : "Spiller 1 (Løve)"
        case .elephant:
            return modeSinglePlayer ? "Computerens tur (Elefant)" : "Spiller 2 (Elefant)"
        case .none:
            return ""
        }
    }

    private func cellTapped(index: Int) {
        guard !showSuccess, !disableInput else { return }

        // Hvis der er en valgt brik (vi er i "flyt"-mode), og brugeren trykker et tomt felt -> flyt
        if let from = selectedPieceIndex {
            // kun tillad flyt til tomt felt
            guard board[index] == .none else {
                // hvis brugeren trykker sin egen brik igen, afvælg
                if isCurrentPlayersPiece(at: index) {
                    selectedPieceIndex = nil
                }
                return
            }
            performMove(from: from, to: index)
            return
        }

        // Hvis feltet er tomt og spilleren har mindre end 3 brikker -> placer
        if board[index] == .none && piecesCount(for: currentPlayer) < 3 {
            board[index] = currentPlayer
            playPlaceSound()
            checkForEndOrContinue()
            return
        }

        // Hvis feltet er en af spillerens egne brikker og spilleren allerede har 3 brikker -> vælg den for at flytte
        if isCurrentPlayersPiece(at: index) && canSelectPiece() {
            selectedPieceIndex = index
            AudioVoiceManager.shared.speakWithFallback(
                aiFile: "move_piece",
                fallback: {
                    speechManager.speak("Flyt denne brik")
                }
            )

            return
        }

        // Ellers ignorer trykket
    }

    private func performMove(from: Int, to: Int) {
        board[to] = board[from]
        board[from] = .none
        selectedPieceIndex = nil
        playPlaceSound()
        checkForEndOrContinue()
    }

    private func aiThinkDelay() -> TimeInterval {
        // Slightly longer on hard to feel thoughtful
        switch aiDifficulty {
        case .easy: return 0.45
        case .hard: return 0.6
        }
    }

    private func aiMakeMove() {
        // AI must either place (if <3 pieces) or move (if already 3)
        if piecesCount(for: .elephant) < 3 {
            // place
            let moveIndex: Int?
            switch aiDifficulty {
            case .easy:
                moveIndex = aiMoveEasy()
            case .hard:
                moveIndex = aiMoveHard()
            }

            if let idx = moveIndex {
                board[idx] = .elephant
                playPlaceSound()
            }
            disableInput = false
            checkForEndOrContinue()
            
            return
        } else {
            // move one piece
            if aiDifficulty == .easy {
                // easy: choose random own piece and random empty
                let own = board.indices.filter { board[$0] == .elephant }
                let empties = board.indices.filter { board[$0] == .none }
                if let from = own.randomElement(), let to = empties.randomElement() {
                    board[to] = .elephant
                    board[from] = .none
                    playPlaceSound()
                }
                disableInput = false
                checkForEndOrContinue()
                return
            } else {
                // hard: try to find best (from,to)
                if let (from, to) = aiFindBestMoveForMoving() {
                    board[to] = .elephant
                    board[from] = .none
                    playPlaceSound()
                    disableInput = false
                    checkForEndOrContinue()
                    return
                }
            }

            // fallback: random move
            let own = board.indices.filter { board[$0] == .elephant }
            let empties = board.indices.filter { board[$0] == .none }
            if let from = own.randomElement(), let to = empties.randomElement() {
                board[to] = .elephant
                board[from] = .none
                playPlaceSound()
            }
            disableInput = false
            checkForEndOrContinue()
            return
        }
    }

    // Easy AI: mostly random, sometimes blocks (used for placing)
    private func aiMoveEasy() -> Int? {
        // small chance to block or win
        if TTTRandom.bool(probability: 0.25) {
            if let win = findWinningMove(for: .elephant) { return win }
            if let block = findWinningMove(for: .lion) { return block }
        }
        // otherwise random empty
        let empties = board.indices.filter { board[$0] == .none }
        return empties.randomElement()
    }

    // Hard AI: try win, block, fork, center, corner, edge (used for placing)
    private func aiMoveHard() -> Int? {
        // 1) Win
        if let win = findWinningMove(for: .elephant) { return win }
        // 2) Block
        if let block = findWinningMove(for: .lion) { return block }
        // 3) Fork attempt (simple heuristic: take center if available)
        if board[4] == .none { return 4 }
        // 4) Take opposite corner if opponent in corner
        let corners = [0,2,6,8]
        for c in corners {
            let opp = 8 - c
            if board[c] == .none && board[opp] == .lion { return c }
        }
        // 5) Take any corner
        let freeCorners = corners.filter { board[$0] == .none }
        if let c = freeCorners.randomElement() { return c }
        // 6) Take any side
        let sides = [1,3,5,7].filter { board[$0] == .none }
        if let s = sides.randomElement() { return s }
        // fallback random
        let empties = board.indices.filter { board[$0] == .none }
        return empties.randomElement()
    }

    private func findWinningMove(for player: Player) -> Int? {
        for idx in board.indices where board[idx] == .none {
            var copy = board
            copy[idx] = player
            if winner(in: copy) == player { return idx }
        }
        return nil
    }

    private func checkForEndOrContinue() {
        if let w = winner(in: board) {
            // someone won
            showWin(winner: w)
            return
        }

        if board.allSatisfy({ $0 != .none }) {
            // draw
            showDraw()
            return
        }

        // switch turn
        currentPlayer = (currentPlayer == .lion) ? .elephant : .lion
        
        // Sig kun hvem der har tur hvis det er en menneskelig tur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            // Hvis spillet er slut, eller vi allerede har sagt denne spiller, så gør ikke noget
            guard !showSuccess && lastSpokenPlayer != currentPlayer else { return }

            // I singleplayer: sig kun når det er menneskets tur (lion)
            if modeSinglePlayer {
                if currentPlayer == .lion {
                    lastSpokenPlayer = currentPlayer
                    speakQuestion()
                } else {
                    // AI's tur: opdater lastSpokenPlayer så vi ikke siger AI's tur ved næste check
                    lastSpokenPlayer = currentPlayer
                }
            } else {
                // I multiplayer: sig for begge spillere
                lastSpokenPlayer = currentPlayer
                speakQuestion()
            }
        }

        // clear any selected piece when turn changes
        selectedPieceIndex = nil

        // If singleplayer and it's AI's turn, schedule AI
        if modeSinglePlayer && currentPlayer == .elephant && !showSuccess {
            disableInput = true
            DispatchQueue.main.asyncAfter(deadline: .now() + aiThinkDelay()) {
                aiMakeMove()
            }
        }
    }

    private func winner(in b: [Player]) -> Player? {
        let lines = [
            [0,1,2], [3,4,5], [6,7,8], // rows
            [0,3,6], [1,4,7], [2,5,8], // cols
            [0,4,8], [2,4,6]           // diags
        ]
        for line in lines {
            let a = b[line[0]], c = b[line[1]], d = b[line[2]]
            if a != .none && a == c && c == d {
                return a
            }
        }
        return nil
    }

    private func showWin(winner: Player) {

        // Opdater score før overlay
        if winner == .lion {
            lionScore += 1
        } else if winner == .elephant {
            elephantScore += 1
        }

        showSuccess = true
        showSuccessButton = true

        if winner == .lion {
            successMessage = "Flot! Løven vandt!"
            AudioVoiceManager.shared.speakWithFallback(
                aiFile: "win_lion",
                fallback: {
                    speechManager.speak("Flot! Du vandt!")
                }
            )
        } else {
            successMessage = "Åh nej — Elefanten vandt"
            AudioVoiceManager.shared.speakWithFallback(
                aiFile: "win_elephant",
                fallback: {
                    speechManager.speak("Elefanten vandt")
                }
            )
        }
    }


    private func showDraw() {

        drawCount += 1

        showSuccess = true
        showSuccessButton = true

        successMessage = "Uafgjort"

        AudioVoiceManager.shared.speakWithFallback(
            aiFile: "draw",
            fallback: {
                speechManager.speak("Uafgjort")
            }
        )
    }


    private func startNewRound() {
        board = Array(repeating: .none, count: 9)
        currentPlayer = .lion
        showSuccess = false
        showSuccessButton = false
        disableInput = false
        selectedPieceIndex = nil
        // If singleplayer and AI should start sometimes, you can randomize; default human starts
        
        lastSpokenPlayer = nil
        // Sig hvem starter (valgfrit: kald speakIntro() i stedet)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            lastSpokenPlayer = currentPlayer
            speakQuestion()
        }

    }

    private func playPlaceSound() {
        // placeholder for pling sound; reuse your audio player if you have one
    }

    private func speakIntro() {
        AudioVoiceManager.shared.speakWithFallback(
            aiFile: "intro_TicTacToe",
            fallback: {
                speechManager.speak("Velkommen til Kryds og Bolle. Vælg 1 eller 2 spillere og tryk spil.")
            }
        )
    }


    private func speakQuestion() {
        AudioVoiceManager.shared.speakWithFallback(
            aiFile: currentPlayer == .lion ? "turn_lion" : "turn_elephant",
            fallback: {
                speechManager.speak(turnText)
            }
        )
    }



    // MARK: - Helpers for piece-moving variant

    private func piecesCount(for player: Player) -> Int {
        board.filter { $0 == player }.count
    }

    private func isCurrentPlayersPiece(at index: Int) -> Bool {
        return board[index] == currentPlayer
    }

    private func canSelectPiece() -> Bool {
        // Spilleren kan vælge en brik hvis de allerede har 3 brikker
        return piecesCount(for: currentPlayer) >= 3
    }

    // Find best (from,to) for AI when it must move (hard)
    private func aiFindBestMoveForMoving() -> (Int, Int)? {
        let ownIndices = board.indices.filter { board[$0] == .elephant }
        let empties = board.indices.filter { board[$0] == .none }

        // 1) Can we move to win?
        for from in ownIndices {
            for to in empties {
                var copy = board
                copy[to] = .elephant
                copy[from] = .none
                if winner(in: copy) == .elephant {
                    return (from, to)
                }
            }
        }

        // 2) Try moves that don't allow immediate opponent win (simple block heuristic)
        for from in ownIndices {
            for to in empties {
                var copy = board
                copy[to] = .elephant
                copy[from] = .none
                // If opponent has a winning move after this, skip
                if findWinningMove(for: .lion, inBoard: copy) != nil {
                    continue
                } else {
                    return (from, to)
                }
            }
        }

        // 3) Heuristics: center, corners, sides
        if empties.contains(4), let from = ownIndices.first {
            return (from, 4)
        }

        let corners = [0,2,6,8]
        for c in corners where empties.contains(c) {
            if let from = ownIndices.first {
                return (from, c)
            }
        }

        // 4) fallback random
        if let from = ownIndices.randomElement(), let to = empties.randomElement() {
            return (from, to)
        }

        return nil
    }

    // Helper: find winning move for a player in a given board (used for simulation)
    private func findWinningMove(for player: Player, inBoard b: [Player]) -> Int? {
        for idx in b.indices where b[idx] == .none {
            var copy = b
            copy[idx] = player
            if winner(in: copy) == player { return idx }
        }
        return nil
    }
}

// MARK: - Helpers

// Lokal random helper for TicTacToe — undgår global navnekollision
private enum TTTRandom {
    static func bool(probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }
    static func bool(probability: Float) -> Bool {
        Double.random(in: 0...1) < Double(probability)
    }
    static func bool(probability: Int) -> Bool {
        Double.random(in: 0...1) < Double(probability)
    }
    static func bool(probability: UInt8) -> Bool {
        Double.random(in: 0...1) < Double(probability) / 255.0
    }
}

// MARK: - Preview

struct TicTacToeView_Previews: PreviewProvider {
    static var previews: some View {
        TicTacToeView(
            difficulty: .easy,
            startImmediately: false,
            onExit: {},
            onBackToHub: {}
        )
    }
}
