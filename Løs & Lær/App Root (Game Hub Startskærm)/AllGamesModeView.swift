//
//  AllGamesModeView.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 25/01/2026.
//

import SwiftUI
// Comment IAP 03-04-2026

struct AllGamesModeView: View {

    let difficulty: Difficulty
    let onExit: () -> Void

    @StateObject var session = GameSessionManager()

    // Kun de spil, der er aktive (kilde)
    private var activeGames: [GameSelection] {
        enabledGames.filter { $0 != .none }
    }

    @State private var currentIndex: Int = 0
    @State private var shuffledGames: [GameSelection]

    // Husk sidste Labyrinth-mode på tværs af runder
    private static var lastLabyrinthMode: GameMode = .words

    init(difficulty: Difficulty, onExit: @escaping () -> Void) {
        self.difficulty = difficulty
        self.onExit = onExit
        _shuffledGames = State(initialValue: enabledGames.filter { $0 != .none }.shuffled())
    }

    private var currentGame: GameSelection? {
        guard shuffledGames.indices.contains(currentIndex) else { return nil }
        return shuffledGames[currentIndex]
    }

    var body: some View {
        if activeGames.isEmpty {
            VStack {
                Text("Ingen spil er aktiveret endnu.")
                Button("Tilbage") { onExit() }
            }
        } else if let currentGame {
            ZStack {
                switch currentGame {
                case .labyrinthLetters:
                    LabyrinthGameView(
                        difficulty: difficulty,
                        randomizeInternalModes: false,              // rotation inde i Labyrint
                        startImmediately: true,                     //⭐ vigtig: tving AllGames-mode
                        initialMode: consumeNextLabyrinthMode(),
                        onExit: {                                   // Next game in rotation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit                         // tilbage til hub
                    )
                    .environmentObject(session)   // ⭐ Global score

                case .labyrinthMath:
                    LabyrinthGameView(
                        difficulty: difficulty,
                        randomizeInternalModes: false,
                        startImmediately: true,
                        initialMode: .math,
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)   // ⭐ Global score

                case .labyrinthWords:
                    LabyrinthGameView(
                        difficulty: difficulty,
                        randomizeInternalModes: false,
                        startImmediately: true,
                        initialMode: .words,
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)   // ⭐ Global score

                case .animals:
                    AnimalGameView(
                        difficulty: difficulty,
                        startImmediately: true,
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)   // ⭐ Global score

                case .marbleLabyrinthPOC:
                    MarbleLabyrinthGameControllerContainer(
                        difficulty: difficulty,
                        startImmediately: true,
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame(scoreIncrement: 0)
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)
                    .ignoresSafeArea()

                case .clock:
                    ClockGameView(
                        difficulty: difficulty,
                        startImmediately: true,
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)   // ⭐ Global score

                case .ticTacToe:
                    TicTacToeView(
                        difficulty: difficulty,
                        startImmediately: true,     // ⭐ vigtig: tving AllGames-mode
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session)   // ⭐

                case .memoryMatch:
                    MemoryMatchView(
                        difficulty: difficulty,
                        startImmediately: true, // ⭐ tving AllGames-mode til at starte direkte
                        onExit: {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                nextGame()
                            }
                        },
                        onBackToHub: onExit
                    )
                    .environmentObject(session) // vigtig: del global session (global score)

                default:
                    EmptyView()
                }
            }
            .onAppear {
                print("ACTIVE GAMES:", activeGames)
                session.resetAllGameScore()   // ⭐ reset global score
            }
        } else {
            Color.clear
                .onAppear {
                    if shuffledGames.isEmpty {
                        shuffledGames = activeGames.shuffled()
                        currentIndex = 0
                    }
                }
        }
    }

    private func nextGame(scoreIncrement: Int = 1) {
        guard !activeGames.isEmpty else { return }

        // ⭐ Increment global score for hvert afsluttet spil
        session.add(points: scoreIncrement)

        // Hvis vi ikke har en shuffle endnu, så lav en
        if shuffledGames.isEmpty {
            shuffledGames = activeGames.shuffled()
            currentIndex = 0
            return
        }

        let nextIndex = currentIndex + 1

        if nextIndex >= shuffledGames.count {
            // Ny runde: reshuffle rækkefølgen
            shuffledGames = activeGames.shuffled()
            currentIndex = 0
        } else {
            currentIndex = nextIndex
        }
    }

    // Rotation: letters -> math -> words -> letters -> ...
    private func consumeNextLabyrinthMode() -> GameMode {
        let next: GameMode
        switch AllGamesModeView.lastLabyrinthMode {
        case .letters:
            next = .math
        case .math:
            next = .words
        case .words:
            next = .letters
        }
        AllGamesModeView.lastLabyrinthMode = next
        return next
    }
}
