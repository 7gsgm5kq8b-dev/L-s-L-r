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

    func playAgain() {
        phase = .playing
        scene.resetMarble(manual: true)
    }

    func loadNextBoard() {
        let previousBoard = currentBoard
        let nextBoard = generateNextBoard(from: previousBoard)
        currentBoard = nextBoard

        replaceScene(for: nextBoard)
        phase = .playing
    }

    func resetBoard() {
        playAgain()
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
    }

    private func generateNextBoard(from previousBoard: MarbleBoardConfiguration) -> MarbleBoardConfiguration {
        var candidateSeed = max(nextBoardSeed, previousBoard.boardSeed + 1)
        var attempts = 0

        while true {
            let candidate = MarbleBoardConfiguration.generated(seed: candidateSeed)
            let layoutChanged = !candidate.hasSameLayout(as: previousBoard)

            if layoutChanged || attempts >= 24 {
                nextBoardSeed = candidateSeed + 1
                return candidate
            }

            candidateSeed += 1
            attempts += 1
        }
    }

    private func handle(_ event: MarbleLabyrinthScene.Event) {
        switch event {
        case .started:
            phase = .playing
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
        let horizontalPadding: CGFloat
        let boardSize: CGSize
        let simulatorWidth: CGFloat
    }

    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    @StateObject private var viewModel = MarbleLabyrinthPOCViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(in: proxy)

            VStack(spacing: 10) {
                topBar

                boardCard(size: metrics.boardSize)

                if viewModel.motionController.isUsingFallback {
                    simulatorControls(width: metrics.simulatorWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, max(4, proxy.safeAreaInsets.top + 2))
            .padding(.bottom, max(4, proxy.safeAreaInsets.bottom + 2))
            .background(
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.93, blue: 0.86), Color(red: 0.88, green: 0.94, blue: 0.97)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            MarbleOrientationLock.lockGameplayOrientation()
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
            MarbleOrientationLock.unlockAppOrientation()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            MarbleOrientationLock.lockGameplayOrientation()
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button(action: onExit) {
                Label("Tilbage", systemImage: "chevron.left")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.76), in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 12)

            VStack(spacing: 4) {
                Text("Kuglebane")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text("Vip iPad'en og rul kuglen gennem banen")
                    .font(.headline)
                    .foregroundColor(.black.opacity(0.68))
            }

            Spacer(minLength: 12)

            Button(action: viewModel.resetBoard) {
                Label("Nulstil", systemImage: "arrow.counterclockwise")
                    .font(.headline.weight(.bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.98, green: 0.78, blue: 0.37), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func boardCard(size: CGSize) -> some View {
        ZStack {
            SpriteView(scene: viewModel.scene, options: [.allowsTransparency])
                .id(viewModel.sceneReloadToken)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.72), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.14), radius: 18, y: 8)

            if viewModel.phase != .playing {
                overlayCard(width: min(size.width * 0.60, size.width - 40))
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
    }

    @ViewBuilder
    private func overlayCard(width: CGFloat) -> some View {
        let isSuccess = viewModel.phase == .success

        VStack(spacing: 16) {
            Text(isSuccess ? "Du kom i mål" : "Prøv en gang til")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.black.opacity(0.88))

            Text(isSuccess ? "Kuglen fandt vejen gennem banen." : "Kuglen faldt i et hul, men du kan hurtigt starte igen.")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(.black.opacity(0.72))

            HStack(spacing: 14) {
                Button(action: viewModel.playAgain) {
                    Label(isSuccess ? "Spil igen" : "Prøv igen", systemImage: "arrow.counterclockwise")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: viewModel.loadNextBoard) {
                    Label("Ny bane", systemImage: "sparkles")
                        .font(.headline.weight(.bold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.98, green: 0.78, blue: 0.37), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
        .frame(maxWidth: width)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.white.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.82), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
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
        let horizontalPadding: CGFloat = isLandscape ? max(10, safeWidth * 0.012) : 16
        let contentWidth = max(320, safeWidth - horizontalPadding * 2)
        let boardAspectRatio = max(viewModel.boardAspectRatio, 1.0)
        let topBarHeight: CGFloat = isLandscape ? 82 : 96
        let simulatorHeight: CGFloat = viewModel.motionController.isUsingFallback ? (isLandscape ? 196 : 220) : 0
        let verticalChrome: CGFloat = isLandscape ? 24 : 36
        let maxBoardHeight = max(220, safeHeight - topBarHeight - simulatorHeight - verticalChrome)
        let boardWidth = min(contentWidth, maxBoardHeight * boardAspectRatio)
        let boardHeight = boardWidth / boardAspectRatio

        return LayoutMetrics(
            horizontalPadding: horizontalPadding,
            boardSize: CGSize(width: boardWidth, height: boardHeight),
            simulatorWidth: boardWidth
        )
    }
}
