//
//  AppRoot.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 25/01/2026.
//

import SwiftUI
// Comment IAP 03-04-2026

// Hvilke spil findes i platformen
enum GameSelection: CaseIterable {
    case none
    case labyrinthLetters
    case labyrinthMath
    case labyrinthWords
    case clock
    case animals
    case ticTacToe
    case memoryMatch
    case guessAnimal
    case allGames
}

// Her styrer du, hvilke spil der er "aktive" i random/allGames
let enabledGames: [GameSelection] = [
    .labyrinthLetters,
    .labyrinthMath,
    .labyrinthWords,
    .animals,
    .ticTacToe,
    .memoryMatch,
    .clock
]

struct ContentView: View {
    @StateObject var session = GameSessionManager()
    @StateObject private var trialManager = TrialManager.shared

    @State private var selectedGame: GameSelection = .none
    @State private var difficulty: Difficulty = .easy
    @State private var showNotReadyAlert = false
    @State private var pendingSelection: GameSelection? = nil
    @State private var showUnlockScreen = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            switch selectedGame {
            case .none:
                HomeView(
                    difficulty: $difficulty,
                    onNotReady: { game in
                        pendingSelection = game
                        showNotReadyAlert = true
                    },
                    onSelectGame: { game in
                        startGameSelection(game)
                    }
                )

            case .labyrinthLetters:
                LabyrinthGameView(
                    difficulty: difficulty,
                    randomizeInternalModes: false,
                    startImmediately: false,
                    initialMode: .letters,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .labyrinthMath:
                LabyrinthGameView(
                    difficulty: difficulty,
                    randomizeInternalModes: false,
                    startImmediately: false,
                    initialMode: .math,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .labyrinthWords:
                LabyrinthGameView(
                    difficulty: difficulty,
                    randomizeInternalModes: false,
                    startImmediately: false,
                    initialMode: .words,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .animals:
                AnimalGameView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .memoryMatch:
                MemoryMatchView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .allGames:
                AllGamesModeView(
                    difficulty: difficulty,
                    onExit: { selectedGame = .none }
                )
                .environmentObject(session)

            case .ticTacToe:
                TicTacToeView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .clock:
                ClockGameView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            case .guessAnimal:
                GuessAnimalView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )
                .environmentObject(session)
            }
        }
        .environmentObject(trialManager)
        .alert("Spillet er endnu ikke klart", isPresented: $showNotReadyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let game = pendingSelection {
                Text(messageFor(game: game))
            } else {
                Text("Der arbejdes på at gøre dette spil klar.")
            }
        }
        .fullScreenCover(isPresented: $showUnlockScreen) {
            UnlockFullGameView(isPresented: $showUnlockScreen)
                .environmentObject(trialManager)
        }
        .task {
            await trialManager.refreshStoreState()
        }
        .onChange(of: trialManager.hasUnlockedFullGame) { _, unlocked in
            if unlocked {
                showUnlockScreen = false
            }
        }
    }

    private func startGameSelection(_ game: GameSelection) {
        guard game != .none else { return }

        if trialManager.canStartGame() {
            trialManager.registerGamePlay()
            selectedGame = game
        } else {
            showUnlockScreen = true
        }
    }

    private func messageFor(game: GameSelection) -> String {
        switch game {
        case .allGames:
            return "“Spil alle spil” bliver aktiveret, når flere spil er klar."
        default:
            return "Der arbejdes på at gøre dette spil klar."
        }
    }
}
