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

    let motionController: MarbleTiltController

    private var currentBoard: MarbleBoardConfiguration
    private var nextBoardSeed: UInt64
    private var cancellables: Set<AnyCancellable> = []

    var boardAspectRatio: CGFloat {
        let size = currentBoard.boardSize
        guard size.height > 0 else { return 1.0 }
        return size.width / size.height
    }

    init() {
        let controller = MarbleTiltController()
        let initialSeed: UInt64 = 1001
        let board = MarbleBoardConfiguration.generated(seed: initialSeed)
        self.motionController = controller
        self.currentBoard = board
        self.nextBoardSeed = initialSeed + 1
        self.scene = MarbleLabyrinthScene(board: board, motionController: controller)
        attachSceneHandler(to: scene)

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
        motionController.refresh()
        scene.resetMarble(manual: true)
    }

    func startNextGame() {
        let previousBoard = currentBoard
        let nextBoard = generateNextBoard(from: previousBoard)
        phase = .playing
        motionController.refresh()
        currentBoard = nextBoard

        replaceScene(for: nextBoard)
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

    private func generateNextBoard(from previousBoard: MarbleBoardConfiguration) -> MarbleBoardConfiguration {
        var candidateSeed = max(nextBoardSeed, previousBoard.boardSeed + 1)
        var attempts = 0
        let maximumAttempts = 1024

        while attempts < maximumAttempts {
            let candidate = MarbleBoardConfiguration.generated(seed: candidateSeed)
            let topologyChanged = !candidate.hasSameMazeTopology(as: previousBoard)

            if topologyChanged {
                nextBoardSeed = candidateSeed + 1
                return candidate
            }

            candidateSeed += 1
            attempts += 1
        }

        assertionFailure("Unable to generate a fresh maze topology for the next game")
        nextBoardSeed = candidateSeed + 1
        return MarbleBoardConfiguration.generated(seed: candidateSeed)
    }

    private func handle(_ event: MarbleLabyrinthScene.Event) {
        switch event {
        case .started:
            phase = .playing
        case .marbleStartedMoving:
            gameplayHintDismissToken = UUID()
        case .manualReset:
            phase = .playing
        case .failed:
            phase = .failed
        case .success:
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

                    if viewModel.motionController.isUsingFallback {
                        simulatorControls(width: metrics.simulatorWidth)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(.top, proxy.safeAreaInsets.top + metrics.topBarPadding)
                .padding(.bottom, max(8, proxy.safeAreaInsets.bottom + metrics.bottomPadding))
                .padding(.horizontal, metrics.horizontalPadding)
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
            withAnimation(.easeOut(duration: 0.18)) {
                isGameplayHintVisible = true
            }

            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) {
                isGameplayHintVisible = false
            }
        }
        .onChange(of: viewModel.gameplayHintDismissToken) { _, _ in
            withAnimation(.easeOut(duration: 0.24)) {
                isGameplayHintVisible = false
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

                chromeButton(
                    title: "Nulstil",
                    systemImage: "arrow.counterclockwise",
                    fill: Color(red: 1.0, green: 0.90, blue: 0.65).opacity(0.18),
                    stroke: Color(red: 0.92, green: 0.72, blue: 0.20).opacity(0.22),
                    action: viewModel.resetBoard
                )
            }

            VStack(spacing: 2) {
                Text("Kuglebane")
                    .font(.system(size: isLandscape ? 19 : 21, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.62))
                    .lineLimit(1)

                Text("Vip iPad'en og hjælp kuglen i mål. Pas på hullerne undervejs.")
                    .font(.system(size: isLandscape ? 11.5 : 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .opacity(isGameplayHintVisible ? 1 : 0)
            }
            .padding(.horizontal, 84)
        }
        .padding(.horizontal, isLandscape ? 8 : 10)
        .frame(height: isLandscape ? 72 : 80)
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

            if viewModel.phase != .playing {
                overlayCard(width: min(size.width * 0.52, 520))
                    .padding(.horizontal, 18)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private func overlayCard(width: CGFloat) -> some View {
        let isSuccess = viewModel.phase == .success

        ZStack {
            overlayBackdrop(width: width, isSuccess: isSuccess)

            VStack(spacing: 14) {
                if isSuccess {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Du fandt målet!")
                    }
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(red: 0.73, green: 0.47, blue: 0.09))
                } else {
                    Text("Prøv igen")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.black.opacity(0.82))
                }

                Text(isSuccess ? "Kuglen klarede banen." : "En ny bane er klar.")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black.opacity(0.70))

                overlayActionButton(
                    title: "Prøv igen",
                    systemImage: "arrow.clockwise",
                    fill: Color(red: 1.0, green: 0.84, blue: 0.43),
                    stroke: Color(red: 0.93, green: 0.66, blue: 0.16).opacity(0.42),
                    action: viewModel.startNextGame
                )
                .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(maxWidth: width)
        }
        .shadow(
            color: (isSuccess ? Color(red: 1.0, green: 0.78, blue: 0.26) : Color.black).opacity(0.12),
            radius: 22,
            y: 12
        )
    }

    private func overlayBackdrop(width: CGFloat, isSuccess: Bool) -> some View {
        ZStack {
            Ellipse()
                .fill(Color.white.opacity(isSuccess ? 0.28 : 0.24))
                .frame(width: width * 0.96, height: 188)
                .blur(radius: 10)

            Ellipse()
                .fill(
                    LinearGradient(
                        colors: isSuccess
                            ? [Color.white.opacity(0.92), Color(red: 1.0, green: 0.96, blue: 0.80).opacity(0.84)]
                            : [Color.white.opacity(0.88), Color(red: 0.91, green: 0.97, blue: 1.0).opacity(0.80)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: width * 0.92, height: 172)

            Circle()
                .fill(Color.white.opacity(isSuccess ? 0.24 : 0.18))
                .frame(width: 86, height: 86)
                .offset(x: -width * 0.18, y: -40)

            Circle()
                .fill((isSuccess ? Color(red: 1.0, green: 0.92, blue: 0.58) : Color(red: 0.78, green: 0.93, blue: 1.0)).opacity(0.18))
                .frame(width: 62, height: 62)
                .offset(x: width * 0.22, y: -28)
        }
        .allowsHitTesting(false)
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
        let simulatorHeight: CGFloat = viewModel.motionController.isUsingFallback ? (isLandscape ? 196 : 220) : 0
        let verticalChrome: CGFloat = isLandscape ? 18 : 24
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
        }
        .buttonStyle(.plain)
    }
}
