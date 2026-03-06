//  HomeView.swift

import SwiftUI
// Comment IAP 03-04-2026

struct HomeView: View {
    @Binding var difficulty: Difficulty
    let onNotReady: (GameSelection) -> Void
    let onSelectGame: (GameSelection) -> Void

    @EnvironmentObject private var trialManager: TrialManager
    @State private var showParentInfo = false
    @State private var showUnlockScreen = false

    var body: some View {
        GeometryReader { geo in
            let layout = homeLayout(for: geo.size.width)

            ScrollView(.vertical) {
                VStack(spacing: 18) {
                    headerRow

                    if trialManager.shouldShowFivePlaysWarning() {
                        Text("⭐ 5 spil tilbage i gratisversionen")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.85))
                            .clipShape(Capsule())
                    }

                    LazyVGrid(columns: layout.columns, spacing: layout.gridSpacing) {
                        IconTileButton(iconName: "icon_labyrinth_abc", tileSize: layout.tileSize) {
                            onSelectGame(.labyrinthLetters)
                        }

                        IconTileButton(iconName: "icon_labyrinth_math", tileSize: layout.tileSize) {
                            onSelectGame(.labyrinthMath)
                        }

                        IconTileButton(iconName: "icon_labyrinth_word", tileSize: layout.tileSize) {
                            onSelectGame(.labyrinthWords)
                        }

                        IconTileButton(iconName: "icon_clock", tileSize: layout.tileSize) {
                            onSelectGame(.clock)
                        }

                        IconTileButton(iconName: "icon_animals", tileSize: layout.tileSize) {
                            onSelectGame(.animals)
                        }

                        IconTileButton(iconName: "icon_tictactoe", tileSize: layout.tileSize) {
                            onSelectGame(.ticTacToe)
                        }

                        IconTileButton(iconName: "icon_MemoryMatchView_animal", tileSize: layout.tileSize) {
                            onSelectGame(.memoryMatch)
                        }

                        IconTileButton(iconName: "icon_all_games", tileSize: layout.tileSize) {
                            if enabledGames.count > 1 {
                                onSelectGame(.allGames)
                            } else {
                                onNotReady(.allGames)
                            }
                        }

                        IconTileButton(iconName: "icon_guess_animal", tileSize: layout.tileSize) {
                            onSelectGame(.guessAnimal)
                        }
                    }

                    DifficultyPicker(difficulty: $difficulty)
                        .padding(.top, 6)

                    trialStatusPanel
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, layout.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.visible)
            .safeAreaPadding(.top, 6)
        }
        .fullScreenCover(isPresented: $showParentInfo) {
            ParentInfoView(showParentInfo: $showParentInfo)
        }
        .sheet(isPresented: $showUnlockScreen) {
            UnlockFullGameView(isPresented: $showUnlockScreen)
                .environmentObject(trialManager)
        }
    }

    private var headerRow: some View {
        ZStack(alignment: .trailing) {
            Text("Vælg et spil")
                .font(.largeTitle.bold())
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 4) {
                if !trialManager.hasUnlockedFullGame {
                    Button(action: { showUnlockScreen = true }) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.gray)
                            .padding(6)
                    }
                }

                Button(action: { showParentInfo = true }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.gray)
                        .padding(6)
                }
            }
        }
    }

    private struct HomeLayout {
        let columns: [GridItem]
        let tileSize: CGFloat
        let gridSpacing: CGFloat
        let horizontalPadding: CGFloat
    }

    private func homeLayout(for screenWidth: CGFloat) -> HomeLayout {
        let horizontalPadding: CGFloat
        let columnCount: Int
        let spacing: CGFloat

        if screenWidth < 430 {
            horizontalPadding = 12
            columnCount = 2
            spacing = 10
        } else if screenWidth < 900 {
            horizontalPadding = 16
            columnCount = 3
            spacing = 12
        } else {
            horizontalPadding = 20
            columnCount = 3
            spacing = 16
        }

        let available = screenWidth - (horizontalPadding * 2) - (CGFloat(columnCount - 1) * spacing)
        let rawTile = floor(available / CGFloat(columnCount))
        let maxTile: CGFloat = screenWidth < 430 ? 170 : (screenWidth < 900 ? 210 : 190)
        let tileSize = max(120, min(maxTile, rawTile))

        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnCount)
        return HomeLayout(columns: columns, tileSize: tileSize, gridSpacing: spacing, horizontalPadding: horizontalPadding)
    }

    private var trialPlaysUsed: Int {
        max(0, trialManager.configuredTrialPlayLimit - trialManager.freePlaysRemaining)
    }

    private var trialStatusPanel: some View {
        VStack(spacing: 8) {
            ViewThatFits {
                HStack(spacing: 12) {
                    Text("Tilbage: \(trialManager.freePlaysRemaining)")
                    Text("Spillet: \(trialPlaysUsed)")
                    Text("Unlocked: \(trialManager.hasUnlockedFullGame ? "ja" : "nej")")
                }
                VStack(spacing: 4) {
                    Text("Tilbage: \(trialManager.freePlaysRemaining)")
                    Text("Spillet: \(trialPlaysUsed)")
                    Text("Unlocked: \(trialManager.hasUnlockedFullGame ? "ja" : "nej")")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.black.opacity(0.8))

            #if DEBUG && TRIAL_DEBUG_UI
            debugControls
            #endif
        }
        .padding(10)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    #if DEBUG && TRIAL_DEBUG_UI
    private var debugControls: some View {
        VStack(spacing: 8) {
            Text("DEBUG Trial")
                .font(.footnote.bold())
                .foregroundColor(.black.opacity(0.75))

            ViewThatFits {
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

                VStack(spacing: 6) {
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
        }
    }
    #endif
}

struct IconTileButton: View {
    let iconName: String
    let tileSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: tileSize, height: tileSize)
                .padding(4)
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
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
    }
}
