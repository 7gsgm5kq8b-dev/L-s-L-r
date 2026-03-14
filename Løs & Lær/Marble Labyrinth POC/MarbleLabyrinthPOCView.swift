import Combine
import SpriteKit
import SwiftUI

final class MarbleLabyrinthPOCViewModel: ObservableObject {
    enum GamePhase {
        case playing
        case success
        case failed
    }

    @Published var phase: GamePhase = .playing
    @Published var debugX: Double = 0
    @Published var debugY: Double = 0
    @Published private(set) var scene: MarbleLabyrinthScene
    @Published private(set) var sceneReloadToken = UUID()
    @Published private(set) var gameplayHintToken = UUID()
    @Published private(set) var gameplayHintDismissToken = UUID()
    @Published private(set) var isStartingNextGame = false
    @Published private(set) var roundCollectedStars = 0
    @Published private(set) var roundTotalStars = 0
    @Published private(set) var totalScore = 0

    let motionController: MarbleTiltController

    private static var lastPresentedBoard: MarbleBoardConfiguration?
    private let nextBoardQueue = DispatchQueue(label: "com.loslær.marble.next-board", qos: .userInitiated)

    private var currentBoard: MarbleBoardConfiguration
    private var preparedNextBoard: MarbleBoardConfiguration?
    private var preparedNextBoardSourceSeed: UInt64?
    private var nextBoardGenerationID = 0
    private var committedScore = 0
    private var cancellables: Set<AnyCancellable> = []

    var boardAspectRatio: CGFloat {
        let size = currentBoard.boardSize
        guard size.height > 0 else { return 1.0 }
        return size.width / size.height
    }

    init() {
        let controller = MarbleTiltController()
        let board = Self.generateFreshBoard(after: Self.lastPresentedBoard)
        self.motionController = controller
        self.currentBoard = board
        self.roundTotalStars = board.stars.count
        self.scene = MarbleLabyrinthScene(board: board, motionController: controller)
        attachSceneHandler(to: scene)
        Self.lastPresentedBoard = board
        prepareNextBoard(after: board)

        motionController.$debugSample
            .receive(on: DispatchQueue.main)
            .sink { [weak self] sample in
                self?.debugX = sample.x
                self?.debugY = sample.y
            }
            .store(in: &cancellables)

    }

    func onAppear() {
        motionController.start()
    }

    func onDisappear() {
        motionController.stop()
    }

    func refreshMotionForCurrentScene() {
        motionController.refresh()
    }

    func replayCurrentBoard() {
        phase = .playing
        resetStarProgress(for: currentBoard)
        motionController.refresh()
        scene.resetMarble(manual: true)
    }

    func startNextGame() {
        guard !isStartingNextGame else { return }
        isStartingNextGame = true

        let previousBoard = currentBoard
        let nextBoard = takePreparedNextBoard(after: previousBoard) ?? Self.generateFreshBoard(after: previousBoard)
        phase = .playing
        resetStarProgress(for: nextBoard)
        motionController.refresh()
        currentBoard = nextBoard
        Self.lastPresentedBoard = nextBoard

        replaceScene(for: nextBoard)
        prepareNextBoard(after: nextBoard)
        isStartingNextGame = false
    }

    func resetBoard() {
        replayCurrentBoard()
    }

    func updateSimulatorTilt(x: Double, y: Double) {
        motionController.updateFallbackTilt(x: x, y: y)
    }

    private func attachSceneHandler(to scene: MarbleLabyrinthScene) {
        scene.eventHandler = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
    }

    private func replaceScene(for board: MarbleBoardConfiguration) {
        let newScene = MarbleLabyrinthScene(board: board, motionController: motionController)
        attachSceneHandler(to: newScene)
        scene = newScene
        sceneReloadToken = UUID()
        gameplayHintToken = UUID()
    }

    private func resetStarProgress(for board: MarbleBoardConfiguration) {
        roundCollectedStars = 0
        roundTotalStars = board.stars.count
        totalScore = committedScore
    }

    private func takePreparedNextBoard(after board: MarbleBoardConfiguration) -> MarbleBoardConfiguration? {
        guard preparedNextBoardSourceSeed == board.boardSeed, let preparedNextBoard else {
            return nil
        }

        self.preparedNextBoard = nil
        self.preparedNextBoardSourceSeed = nil
        return preparedNextBoard
    }

    private func prepareNextBoard(after board: MarbleBoardConfiguration) {
        nextBoardGenerationID += 1
        let generationID = nextBoardGenerationID
        let sourceBoard = board

        preparedNextBoard = nil
        preparedNextBoardSourceSeed = nil

        nextBoardQueue.async { [weak self] in
            let nextBoard = Self.generateFreshBoard(after: sourceBoard)

            DispatchQueue.main.async {
                guard let self else { return }
                guard self.nextBoardGenerationID == generationID else { return }
                guard self.currentBoard.boardSeed == sourceBoard.boardSeed else { return }

                self.preparedNextBoard = nextBoard
                self.preparedNextBoardSourceSeed = sourceBoard.boardSeed
            }
        }
    }

    private static func generateFreshBoard(after previousBoard: MarbleBoardConfiguration?) -> MarbleBoardConfiguration {
        let maximumAttempts = 1024
        var attemptedSeeds: Set<UInt64> = []

        for _ in 0..<maximumAttempts {
            let candidateSeed = randomBoardSeed(excluding: attemptedSeeds)
            attemptedSeeds.insert(candidateSeed)

            let candidate = MarbleBoardConfiguration.generated(seed: candidateSeed)
            if let previousBoard, candidate.hasSameMazeTopology(as: previousBoard) {
                continue
            }

            if let previousBoard, candidate.hasSameHoleZonePattern(as: previousBoard) {
                continue
            }

            return candidate
        }

        assertionFailure("Unable to generate a fresh random maze for Kuglebane")
        return MarbleBoardConfiguration.generated(seed: randomBoardSeed(excluding: attemptedSeeds))
    }

    private static func randomBoardSeed(excluding attemptedSeeds: Set<UInt64>) -> UInt64 {
        var candidateSeed = UInt64.random(in: 1...UInt64.max)
        while attemptedSeeds.contains(candidateSeed) {
            candidateSeed = UInt64.random(in: 1...UInt64.max)
        }
        return candidateSeed
    }

    private func handle(_ event: MarbleLabyrinthScene.Event) {
        switch event {
        case .started:
            phase = .playing
        case .marbleStartedMoving:
            gameplayHintDismissToken = UUID()
        case .manualReset:
            phase = .playing
        case let .starsUpdated(collected, total):
            roundCollectedStars = collected
            roundTotalStars = total
            totalScore = committedScore + collected
        case .failed:
            replayCurrentBoard()
        case .success:
            committedScore += roundCollectedStars
            totalScore = committedScore
            phase = .success
        }
    }
}

struct MarbleLabyrinthPOCView: View {
    private struct LayoutMetrics {
        let isLandscape: Bool
        let horizontalPadding: CGFloat
        let boardSize: CGSize
        let simulatorWidth: CGFloat
        let topBarPadding: CGFloat
        let bottomPadding: CGFloat
        let stackSpacing: CGFloat
    }

    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    @StateObject private var viewModel = MarbleLabyrinthPOCViewModel()
    @State private var isGameplayHintVisible = true
    @State private var gameplayHintVisibleUntil = Date.distantPast
    @State private var gameplayHintSessionID = UUID()

    private var shouldShowSimulatorControls: Bool {
#if targetEnvironment(simulator)
        viewModel.motionController.isUsingFallback
#else
        false
#endif
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(in: proxy)

            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.93, blue: 0.86), Color(red: 0.88, green: 0.94, blue: 0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: metrics.stackSpacing) {
                    topBar(isLandscape: metrics.isLandscape)
                        .padding(.horizontal, max(10, metrics.horizontalPadding + 8))

                    boardCard(size: metrics.boardSize)
                        .frame(maxWidth: .infinity)

                    scoreCounter

                    if shouldShowSimulatorControls {
                        simulatorControls(width: metrics.simulatorWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, proxy.safeAreaInsets.top + metrics.topBarPadding)
                .padding(.bottom, max(8, proxy.safeAreaInsets.bottom + metrics.bottomPadding))
                .padding(.horizontal, metrics.horizontalPadding)

                if viewModel.phase == .success {
                    successOverlay
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .task(id: viewModel.gameplayHintToken) {
            let sessionID = UUID()
            let visibleUntil = Date().addingTimeInterval(5)
            gameplayHintSessionID = sessionID
            gameplayHintVisibleUntil = visibleUntil

            withAnimation(.easeOut(duration: 0.18)) {
                isGameplayHintVisible = true
            }

            try? await Task.sleep(for: .seconds(5))

            guard !Task.isCancelled else { return }
            guard gameplayHintSessionID == sessionID else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                isGameplayHintVisible = false
            }
        }
        .onChange(of: viewModel.gameplayHintDismissToken) { _, _ in
            let sessionID = gameplayHintSessionID
            let remainingDelay = max(0, gameplayHintVisibleUntil.timeIntervalSinceNow)

            Task { @MainActor in
                if remainingDelay > 0 {
                    try? await Task.sleep(for: .seconds(remainingDelay))
                }

                guard gameplayHintSessionID == sessionID else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    isGameplayHintVisible = false
                }
            }
        }
        .task(id: viewModel.sceneReloadToken) {
            try? await Task.sleep(for: .milliseconds(350))

            guard !Task.isCancelled else { return }
            viewModel.refreshMotionForCurrentScene()
        }
    }

    private func topBar(isLandscape: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: isLandscape ? 24 : 26, style: .continuous)
                .fill(Color.white.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: isLandscape ? 24 : 26, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                )

            HStack(spacing: 12) {
                chromeButton(
                    title: "Tilbage",
                    systemImage: "chevron.left",
                    fill: Color.white.opacity(0.14),
                    stroke: Color.white.opacity(0.18),
                    action: onExit
                )

                Spacer(minLength: 10)
            }

            VStack(spacing: 2) {
                Text("Kuglebane")
                    .font(.system(size: isLandscape ? 19 : 21, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                Text("Vip iPad'en og hjælp kuglen i mål. Saml stjerner, men pas på hullerne undervejs.")
                    .font(.system(size: isLandscape ? 11.5 : 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .opacity(isGameplayHintVisible ? 1 : 0)
            }
            .padding(.horizontal, 84)
        }
        .padding(.horizontal, isLandscape ? 8 : 10)
        .frame(height: isLandscape ? 78 : 88)
    }

    private func boardCard(size: CGSize) -> some View {
        ZStack {
            boardHeroBackdrop(size: size)
                .frame(width: size.width, height: size.height)

            SpriteView(scene: viewModel.scene, options: [.allowsTransparency])
                .id(viewModel.sceneReloadToken)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 14, y: 6)
                .allowsHitTesting(viewModel.phase != .success)
        }
        .frame(width: size.width, height: size.height)
    }

    private var scoreCounter: some View {
        HStack {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)

            Text("\(viewModel.totalScore)")
                .font(.title.bold())
        }
        .padding(12)
        .background(Color.black.opacity(0.1))
        .cornerRadius(12)
    }

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    ForEach(0..<max(viewModel.roundTotalStars, 1), id: \.self) { index in
                        Image(systemName: index < viewModel.roundCollectedStars ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .padding(.bottom, 4)

                Text("Du fandt målet!")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Kuglen klarede banen.")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white.opacity(0.88))

                Button(action: viewModel.startNextGame) {
                    Text("Prøv igen")
                        .font(.headline.bold())
                        .padding(.vertical, 10)
                        .padding(.horizontal, 32)
                        .background(Color.white)
                        .foregroundColor(.green)
                        .cornerRadius(14)
                        .shadow(radius: 4)
                }
                .disabled(viewModel.isStartingNextGame)
                .opacity(viewModel.isStartingNextGame ? 0.72 : 1)
            }
            .padding()
        }
    }

    private func boardHeroBackdrop(size: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color(red: 0.83, green: 0.94, blue: 1.0).opacity(0.16),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: size.width * 0.58
                    )
                )
                .frame(width: size.width * 1.08, height: size.height * 1.06)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.71, green: 0.90, blue: 1.0).opacity(0.18),
                            Color(red: 1.0, green: 0.95, blue: 0.77).opacity(0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size.width * 1.12, height: size.height * 0.92)
                .blur(radius: 24)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func simulatorControls(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            Text("Simulator-kontrol")
                .font(.headline.weight(.bold))

            VStack(alignment: .leading, spacing: 10) {
                Text("Vip side")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { viewModel.debugX },
                        set: { viewModel.updateSimulatorTilt(x: $0, y: viewModel.debugY) }
                    ),
                    in: -0.7...0.7
                )

                Text("Vip frem")
                    .font(.subheadline.weight(.semibold))
                Slider(
                    value: Binding(
                        get: { viewModel.debugY },
                        set: { viewModel.updateSimulatorTilt(x: viewModel.debugX, y: $0) }
                    ),
                    in: -0.7...0.7
                )
            }

            Button("Nulstil simulator-tilt") {
                viewModel.updateSimulatorTilt(x: 0, y: 0)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: width)
        .padding(18)
        .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func layoutMetrics(in proxy: GeometryProxy) -> LayoutMetrics {
        let safeWidth = max(320, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing)
        let safeHeight = max(320, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom)
        let isLandscape = safeWidth > safeHeight
        let horizontalPadding: CGFloat = isLandscape ? max(4, safeWidth * 0.004) : 10
        let contentWidth = max(320, safeWidth - horizontalPadding * 2)
        let boardAspectRatio = max(viewModel.boardAspectRatio, 1.0)
        let topBarHeight: CGFloat = isLandscape ? 72 : 80
        let simulatorHeight: CGFloat = shouldShowSimulatorControls ? (isLandscape ? 196 : 220) : 0
        let scoreCounterHeight: CGFloat = 54
        let verticalChrome: CGFloat = (isLandscape ? 18 : 24) + scoreCounterHeight
        let maxBoardHeight = max(220, safeHeight - topBarHeight - simulatorHeight - verticalChrome)
        let boardWidth = min(contentWidth, maxBoardHeight * boardAspectRatio)
        let boardHeight = boardWidth / boardAspectRatio

        return LayoutMetrics(
            isLandscape: isLandscape,
            horizontalPadding: horizontalPadding,
            boardSize: CGSize(width: boardWidth, height: boardHeight),
            simulatorWidth: boardWidth,
            topBarPadding: isLandscape ? 8 : 12,
            bottomPadding: isLandscape ? 10 : 18,
            stackSpacing: isLandscape ? 12 : 16
        )
    }

    private func chromeButton(
        title: String,
        systemImage: String,
        fill: Color,
        stroke: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black.opacity(0.64))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(fill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(stroke, lineWidth: 0.9)
                )
        }
        .buttonStyle(.plain)
    }

    private func overlayActionButton(
        title: String,
        systemImage: String,
        fill: Color,
        stroke: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.bold))
                .foregroundColor(.black.opacity(0.82))
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(fill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(stroke, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
