//
//  AppRoot.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 25/01/2026.
//

import SwiftUI

// Hvilke spil findes i platformen
enum GameSelection: CaseIterable {
    case none
    case labyrinthLetters
    case labyrinthMath
    case labyrinthWords
    case clock
    case animals
    case ticTacToe
    case allGames
}

// Her styrer du, hvilke spil der er "aktive" i random/allGames
// For nu: kun labyrinten er aktiv
let enabledGames: [GameSelection] = [
    .labyrinthLetters,
    .labyrinthMath,
    .labyrinthWords,
    .animals,
    .ticTacToe,
    .clock
    // Senere kan du tilføje: .clock,
]

// Din eksisterende Difficulty enum genbruges
// enum Difficulty { case easy, hard }

struct ContentView: View {
    @StateObject var session = GameSessionManager()
    
    @State private var selectedGame: GameSelection = .none
    @State private var difficulty: Difficulty = .easy
    @State private var showNotReadyAlert = false
    @State private var pendingSelection: GameSelection? = nil

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            switch selectedGame {
            case .none:
                HomeView(
                    selectedGame: $selectedGame,
                    difficulty: $difficulty,
                    onNotReady: { game in
                        pendingSelection = game
                        showNotReadyAlert = true
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
                    onExit: { selectedGame = .none },      // når spillet afslutter sig selv
                    onBackToHub: { selectedGame = .none }  // når brugeren trykker tilbage
                )

            case .allGames:
                AllGamesModeView(
                    difficulty: difficulty,
                    onExit: { selectedGame = .none }        // når rotationen er færdig
                )

                .environmentObject(session)   // ⭐ vigtig linje
                
            case .ticTacToe:
                TicTacToeView(
                    difficulty: difficulty,
                    startImmediately: false,                 // hub: vis startskærm
                    onExit: { selectedGame = .none },        // når spillet afslutter sig selv
                    onBackToHub: { selectedGame = .none }    // når brugeren trykker tilbage
                )
                
            case .clock:
                ClockGameView(
                    difficulty: difficulty,
                    startImmediately: false,
                    onExit: { selectedGame = .none },
                    onBackToHub: { selectedGame = .none }
                )

            }
        }
        .alert("Spillet er endnu ikke klart", isPresented: $showNotReadyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            if let game = pendingSelection {
                Text(messageFor(game: game))
            } else {
                Text("Der arbejdes på at gøre dette spil klar.")
            }
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
