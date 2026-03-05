//  HomeView.swift

import SwiftUI
// Comment IAP 03-04-2026

struct HomeView: View {
    @Binding var difficulty: Difficulty
    let onNotReady: (GameSelection) -> Void
    let onSelectGame: (GameSelection) -> Void

    @EnvironmentObject private var trialManager: TrialManager
    @State private var showParentInfo = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)

            Text("Vælg et spil")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            if trialManager.shouldShowFivePlaysWarning() {
                Text("⭐ 5 spil tilbage i gratisversionen")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.85))
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: columns, spacing: 16) {
                IconTileButton(iconName: "icon_labyrinth_abc") {
                    onSelectGame(.labyrinthLetters)
                }

                IconTileButton(iconName: "icon_labyrinth_math") {
                    onSelectGame(.labyrinthMath)
                }

                IconTileButton(iconName: "icon_labyrinth_word") {
                    onSelectGame(.labyrinthWords)
                }

                IconTileButton(iconName: "icon_clock") {
                    onSelectGame(.clock)
                }

                IconTileButton(iconName: "icon_animals") {
                    onSelectGame(.animals)
                }

                IconTileButton(iconName: "icon_tictactoe") {
                    onSelectGame(.ticTacToe)
                }

                IconTileButton(iconName: "icon_MemoryMatchView_animal") {
                    onSelectGame(.memoryMatch)
                }

                IconTileButton(iconName: "icon_all_games") {
                    if enabledGames.count > 1 {
                        onSelectGame(.allGames)
                    } else {
                        onNotReady(.allGames)
                    }
                }

                IconTileButton(iconName: "icon_guess_animal") {
                    onSelectGame(.guessAnimal)
                }
            }
            .padding(.horizontal, 20)

            DifficultyPicker(difficulty: $difficulty)
                .padding(.top, 10)

            #if DEBUG
            debugPanel
            #endif

            Spacer()
        }
        .overlay(alignment: .topTrailing) {
            Button(action: { showParentInfo = true }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.gray)
                    .padding()
            }
            .offset(x: -20, y: 20)
        }
        .fullScreenCover(isPresented: $showParentInfo) {
            ParentInfoView(showParentInfo: $showParentInfo)
        }
    }

    #if DEBUG
    private var debugTrialLimit: Int { 3 }

    private var debugPlaysUsed: Int {
        max(0, debugTrialLimit - trialManager.freePlaysRemaining)
    }

    private var debugPanel: some View {
        VStack(spacing: 8) {
            Text("DEBUG Trial")
                .font(.footnote.bold())
                .foregroundColor(.black.opacity(0.75))

            HStack(spacing: 12) {
                Text("Tilbage: \(trialManager.freePlaysRemaining)")
                Text("Spillet: \(debugPlaysUsed)")
                Text("Unlocket: \(trialManager.hasUnlockedFullGame ? "ja" : "nej")")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.black.opacity(0.8))

            HStack(spacing: 8) {
                Button("Reset trial") {
                    trialManager.resetTrial()
                }
                .buttonStyle(.bordered)

                Button("Simulate purchase") {
                    trialManager.simulatePurchase()
                }
                .buttonStyle(.borderedProminent)

                Button("Print status") {
                    trialManager.printCurrentTrialStatus()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    #endif
}

struct IconTileButton: View {
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .padding(8)
        }
    }
}

struct DifficultyPicker: View {
    @Binding var difficulty: Difficulty

    var body: some View {
        VStack(spacing: 8) {
            Text("Sværhedsgrad")
                .font(.headline)
                .foregroundColor(.black)

            Picker("Sværhedsgrad", selection: $difficulty) {
                Text("Let").tag(Difficulty.easy)
                Text("Svær").tag(Difficulty.hard)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }
}
