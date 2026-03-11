//  HomeView.swift

import SwiftUI
// Comment IAP 03-04-2026

struct HomeView: View {
    @Binding var difficulty: Difficulty
    let onNotReady: (GameSelection) -> Void
    let onSelectGame: (GameSelection) -> Void

    @EnvironmentObject private var trialManager: TrialManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showParentInfo = false
    @State private var showUnlockScreen = false
    @State private var carouselHintOffset: CGFloat = 0
    @State private var hasPlayedCarouselHint = false

    private struct GameTile: Identifiable {
        let id: String
        let iconName: String
        let selection: GameSelection
        let isHighlighted: Bool

        init(id: String, iconName: String, selection: GameSelection, isHighlighted: Bool = false) {
            self.id = id
            self.iconName = iconName
            self.selection = selection
            self.isHighlighted = isHighlighted
        }
    }

    private var iPadCarouselTiles: [GameTile] {
        [
            GameTile(id: "all_games", iconName: "icon_all_games", selection: .allGames, isHighlighted: true),
            GameTile(id: "labyrinth_abc", iconName: "icon_labyrinth_abc", selection: .labyrinthLetters),
            GameTile(id: "labyrinth_math", iconName: "icon_labyrinth_math", selection: .labyrinthMath),
            GameTile(id: "labyrinth_word", iconName: "icon_labyrinth_word", selection: .labyrinthWords),
            GameTile(id: "clock", iconName: "icon_clock", selection: .clock),
            GameTile(id: "animals", iconName: "icon_animals", selection: .animals),
            GameTile(id: "tictactoe", iconName: "icon_tictactoe", selection: .ticTacToe),
            GameTile(id: "memory", iconName: "icon_MemoryMatchView_animal", selection: .memoryMatch),
            GameTile(id: "guess", iconName: "icon_guess_animal", selection: .guessAnimal)
        ]
    }

    // iPhone original-style list: fixed tiles in pairs, including All Games as normal tile.
    private var iPhoneGridTiles: [GameTile] {
        [
            GameTile(id: "labyrinth_abc", iconName: "icon_labyrinth_abc", selection: .labyrinthLetters),
            GameTile(id: "labyrinth_math", iconName: "icon_labyrinth_math", selection: .labyrinthMath),
            GameTile(id: "labyrinth_word", iconName: "icon_labyrinth_word", selection: .labyrinthWords),
            GameTile(id: "clock", iconName: "icon_clock", selection: .clock),
            GameTile(id: "animals", iconName: "icon_animals", selection: .animals),
            GameTile(id: "tictactoe", iconName: "icon_tictactoe", selection: .ticTacToe),
            GameTile(id: "memory", iconName: "icon_MemoryMatchView_animal", selection: .memoryMatch),
            GameTile(id: "all_games", iconName: "icon_all_games", selection: .allGames),
            GameTile(id: "guess", iconName: "icon_guess_animal", selection: .guessAnimal)
        ]
    }

    var body: some View {
        GeometryReader { geo in
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadHomeContent(size: geo.size)
            } else {
                iPhoneHomeContent(size: geo.size)
            }
        }
        .fullScreenCover(isPresented: $showParentInfo) {
            ParentInfoView(showParentInfo: $showParentInfo)
        }
        .sheet(isPresented: $showUnlockScreen) {
            UnlockFullGameView(isPresented: $showUnlockScreen)
                .environmentObject(trialManager)
        }
    }

    // MARK: - iPad (keep enhanced layout)
    private func iPadHomeContent(size: CGSize) -> some View {
        let layout = iPadLayout(for: size)
        let isLandscape = size.width > size.height

        return VStack(spacing: layout.sectionSpacing) {
            headerRow(title: "Hvad vil du spille?")
                .padding(.horizontal, layout.horizontalPadding)

            if trialManager.shouldShowFivePlaysWarning() {
                trialWarning
                    .padding(.horizontal, layout.horizontalPadding)
            }

            Spacer(minLength: isLandscape ? 18 : 28)

            iPadGamesShelfSection(layout: layout)
                .padding(.horizontal, layout.horizontalPadding)

            Spacer(minLength: isLandscape ? 18 : 28)

            DifficultyPicker(difficulty: $difficulty)
                .padding(.top, 4)
                .padding(.horizontal, layout.horizontalPadding)

            if shouldShowTrialStatusPanel {
                trialStatusPanel
                    .padding(.horizontal, layout.horizontalPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, isLandscape ? 8 : 12)
        .padding(.bottom, isLandscape ? 4 : 8)
        .safeAreaPadding(.top, 6)
        .safeAreaPadding(.bottom, isLandscape ? 10 : 8)
    }

    // MARK: - iPhone (revert original simple paired grid)
    private func iPhoneHomeContent(size: CGSize) -> some View {
        let layout = iPhoneLayout(for: size)

        return ScrollView(.vertical) {
            VStack(spacing: layout.sectionSpacing) {
                headerRow(title: "Vælg et spil")
                    .padding(.horizontal, layout.horizontalPadding)

                if trialManager.shouldShowFivePlaysWarning() {
                    trialWarning
                        .padding(.horizontal, layout.horizontalPadding)
                }

                iPhonePairedGrid(layout: layout)
                    .padding(.horizontal, layout.horizontalPadding)

                DifficultyPicker(difficulty: $difficulty)
                    .padding(.top, 6)
                    .padding(.horizontal, layout.horizontalPadding)

                if shouldShowTrialStatusPanel {
                    trialStatusPanel
                        .padding(.horizontal, layout.horizontalPadding)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.visible)
        .safeAreaPadding(.top, 6)
        .safeAreaPadding(.bottom, 0)
    }

    // MARK: - Shared Elements
    private var trialWarning: some View {
        Text("⭐ 5 spil tilbage i gratisversionen")
            .font(.headline.weight(.semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.85))
            .clipShape(Capsule())
    }

    private func headerRow(title: String) -> some View {
        ZStack(alignment: .trailing) {
            Text(title)
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

    private func handleTileTap(_ tile: GameTile) {
        if tile.selection == .allGames {
            handleAllGamesTap()
        } else {
            onSelectGame(tile.selection)
        }
    }

    private func handleAllGamesTap() {
        if enabledGames.count > 1 {
            onSelectGame(.allGames)
        } else {
            onNotReady(.allGames)
        }
    }

    // MARK: - iPad Section
    private struct IPadLayout {
        let horizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let shelfTileSize: CGFloat
        let shelfSpacing: CGFloat
        let shelfHeight: CGFloat
        let shelfFadeWidth: CGFloat
        let shelfInnerPadding: CGFloat
        let shelfContainerVerticalPadding: CGFloat
    }

    private func iPadLayout(for size: CGSize) -> IPadLayout {
        let isLandscape = size.width > size.height
        let horizontalPadding: CGFloat = size.width > 1100 ? 24 : 20
        let sectionSpacing: CGFloat = isLandscape ? 10 : 16

        let shelfSpacing: CGFloat = isLandscape ? 14 : 14
        let visibleSlots: CGFloat = isLandscape ? 5.1 : 3.95
        let rawShelfTile = (size.width - (horizontalPadding * 2) - (shelfSpacing * (visibleSlots - 1))) / visibleSlots
        let maxShelfTile: CGFloat = isLandscape ? 194 : 224
        let shelfTileSize = max(138, min(maxShelfTile, floor(rawShelfTile)))
        let shelfHeight = shelfTileSize + (isLandscape ? 34 : 40)

        return IPadLayout(
            horizontalPadding: horizontalPadding,
            sectionSpacing: sectionSpacing,
            shelfTileSize: shelfTileSize,
            shelfSpacing: shelfSpacing,
            shelfHeight: shelfHeight,
            shelfFadeWidth: 54,
            shelfInnerPadding: 6,
            shelfContainerVerticalPadding: isLandscape ? 14 : 18
        )
    }

    private func iPadGamesShelfSection(layout: IPadLayout) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                Text("Vælg et spil")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.black.opacity(0.9))

                Spacer(minLength: 8)

                Text("↔")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.black.opacity(0.58))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.45), in: Capsule())
            }

            ZStack(alignment: .trailing) {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: layout.shelfSpacing) {
                        ForEach(iPadCarouselTiles) { tile in
                            IconTileButton(
                                iconName: tile.iconName,
                                tileSize: layout.shelfTileSize,
                                isHighlighted: tile.isHighlighted
                            ) {
                                handleTileTap(tile)
                            }
                        }
                    }
                    .padding(.horizontal, layout.shelfInnerPadding)
                    .padding(.vertical, 8)
                    .offset(x: carouselHintOffset)
                }
                .frame(maxWidth: .infinity)
                .frame(height: layout.shelfHeight)
                .onAppear {
                    playCarouselHintIfNeeded()
                }

                LinearGradient(
                    gradient: Gradient(colors: [Color.clear, Color(.systemBackground).opacity(0.96)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: layout.shelfFadeWidth)
                .padding(.trailing, 6)
                .allowsHitTesting(false)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black.opacity(0.45))
                    .padding(8)
                    .background(Color.white.opacity(0.78), in: Circle())
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
            .frame(height: layout.shelfHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, layout.shelfContainerVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.36))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.52), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }

    private func playCarouselHintIfNeeded() {
        guard !hasPlayedCarouselHint, !reduceMotion else { return }
        hasPlayedCarouselHint = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            withAnimation(.easeInOut(duration: 0.30)) {
                carouselHintOffset = -16
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                withAnimation(.easeInOut(duration: 0.30)) {
                    carouselHintOffset = 0
                }
            }
        }
    }

    // MARK: - iPhone Section
    private struct IPhoneLayout {
        let horizontalPadding: CGFloat
        let sectionSpacing: CGFloat
        let tileSize: CGFloat
        let gridSpacing: CGFloat
        let rowSpacing: CGFloat
    }

    private func iPhoneLayout(for size: CGSize) -> IPhoneLayout {
        let horizontalPadding: CGFloat = size.width < 430 ? 12 : 16
        let sectionSpacing: CGFloat = 14
        let gridSpacing: CGFloat = size.width < 430 ? 10 : 12
        let available = size.width - (horizontalPadding * 2) - gridSpacing
        let rawTile = floor(available / 2)
        let tileSize = max(130, min(190, rawTile))

        return IPhoneLayout(
            horizontalPadding: horizontalPadding,
            sectionSpacing: sectionSpacing,
            tileSize: tileSize,
            gridSpacing: gridSpacing,
            rowSpacing: gridSpacing
        )
    }

    private func iPhonePairedGrid(layout: IPhoneLayout) -> some View {
        let rows = pairedRows(from: iPhoneGridTiles)

        return VStack(spacing: layout.rowSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: layout.gridSpacing) {
                    ForEach(row) { tile in
                        IconTileButton(iconName: tile.iconName, tileSize: layout.tileSize) {
                            handleTileTap(tile)
                        }
                    }

                    if row.count == 1 {
                        Spacer(minLength: 0)
                            .frame(width: layout.tileSize)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pairedRows(from tiles: [GameTile]) -> [[GameTile]] {
        var rows: [[GameTile]] = []
        var index = 0
        while index < tiles.count {
            let end = min(index + 2, tiles.count)
            rows.append(Array(tiles[index..<end]))
            index += 2
        }
        return rows
    }

    // MARK: - Trial UI
    private var trialPlaysUsed: Int {
        max(0, trialManager.configuredTrialPlayLimit - trialManager.freePlaysRemaining)
    }

    private var shouldShowTrialStatusPanel: Bool {
        #if DEBUG && TRIAL_DEBUG_UI
        true
        #else
        !trialManager.hasUnlockedFullGame
        #endif
    }

    private var trialStatusPanel: some View {
        VStack(spacing: 8) {
            if !trialManager.hasUnlockedFullGame {
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
            }

            #if DEBUG && TRIAL_DEBUG_UI
            debugControls
            #endif
        }
        .padding(10)
        .background(Color.white.opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct IconTileButton: View {
    let iconName: String
    let tileSize: CGFloat
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: tileSize, height: tileSize)
                .padding(4)
                .background(highlightBackground)
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    @ViewBuilder
    private var highlightBackground: some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: tileSize * 0.16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color(red: 1.0, green: 0.94, blue: 0.70).opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: tileSize * 0.16, style: .continuous)
                        .stroke(Color.white.opacity(0.65), lineWidth: 1.2)
                )
                .shadow(color: Color(red: 0.98, green: 0.72, blue: 0.20).opacity(0.20), radius: 12, y: 5)
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
