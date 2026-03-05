import SwiftUI
import AVFoundation
import Combine

// MARK: - Models

struct DragLine {
    let start: CGPoint
    let end: CGPoint
}

struct Animal {
    let id: String
    let displayName: String
    let imageName: String
    let eats: String // FoodOption.id
}

struct FoodOption: Identifiable, Hashable {
    let id: String
    let title: String
    let imageName: String
}

struct AnimalQuestion {
    let animal: Animal
    let questionText: String
    let options: [FoodOption]
    let correctOptionID: String
    var correctOption: FoodOption? {
        options.first { $0.id == correctOptionID }
    }
}

// MARK: - Databases & Generator

struct FoodDatabase {
    static let all: [FoodOption] = [
        FoodOption(id: "KOED", title: "Kød", imageName: "food_meat"),
        FoodOption(id: "FRUGT", title: "Frugt", imageName: "food_fruit"),
        FoodOption(id: "PLANTER", title: "Planter", imageName: "food_plants"),
        FoodOption(id: "BLADE", title: "Blade", imageName: "food_leaves"),
        FoodOption(id: "EUKALYPTUS", title: "Eukalyptus", imageName: "food_eucalyptus"),
        FoodOption(id: "BARK", title: "Bark", imageName: "food_bark"),
        FoodOption(id: "ALGER", title: "Alger", imageName: "food_algae"),
        FoodOption(id: "BAMBUS", title: "Bambus", imageName: "food_bamboo"),
        FoodOption(id: "INSEKTER", title: "Insekter", imageName: "food_insects"),
        FoodOption(id: "ALT", title: "Alt muligt", imageName: "food_omnivore"),
        FoodOption(id: "ROEDDER", title: "Rødder", imageName: "food_roots"),
        FoodOption(id: "GRAS", title: "Græs", imageName: "food_grass"),
        FoodOption(id: "FISK", title: "Fisk", imageName: "food_fish"),
        FoodOption(id: "ORME", title: "Orme", imageName: "food_worms"),
        FoodOption(id: "PLANKTON", title: "Plankton", imageName: "food_plankton"),
        FoodOption(id: "BANAN", title: "Banan", imageName: "food_banana"),
        FoodOption(id: "SKALDYR", title: "Skaldyr", imageName: "food_shellfish"),
        FoodOption(id: "NEKTAR", title: "Nektar", imageName: "food_nectar"),
        FoodOption(id: "NOEDDER", title: "Nødder", imageName: "food_nuts"),
        FoodOption(id: "FUGLEFRO", title: "Fuglefrø", imageName: "food_seeds"),
        FoodOption(id: "KORN", title: "Korn", imageName: "food_grains"),
        FoodOption(id: "KREBS", title: "Krebs", imageName: "food_krill"),
    ]
}

struct AnimalDatabase {
    static let all: [Animal] = [
        Animal(id: "LOEVE", displayName: "Løve", imageName: "animal_lion", eats: "KOED"),
        Animal(id: "TIGER", displayName: "Tiger", imageName: "animal_tiger", eats: "KOED"),
        Animal(id: "GORILLA", displayName: "Gorilla", imageName: "animal_gorilla", eats: "FRUGT"),
        Animal(id: "CHIMPANSE", displayName: "Chimpanse", imageName: "animal_chimpanzee", eats: "FRUGT"),
        Animal(id: "ELEFANT", displayName: "Elefant", imageName: "animal_elephant", eats: "PLANTER"),
        Animal(id: "GIRAFF", displayName: "Giraf", imageName: "animal_giraffe", eats: "BLADE"),
        Animal(id: "HYAENE", displayName: "Hyæne", imageName: "animal_hyena", eats: "KOED"),
        Animal(id: "KOALA", displayName: "Koala", imageName: "animal_koala", eats: "EUKALYPTUS"),
        Animal(id: "SLOTH", displayName: "Dovendyr", imageName: "animal_sloth", eats: "BLADE"),
        Animal(id: "BAEVER", displayName: "Bæver", imageName: "animal_beaver", eats: "BARK"),
        Animal(id: "FLAMINGO", displayName: "Flamingo", imageName: "animal_flamingo", eats: "ALGER"),
        Animal(id: "ROED_PANDA", displayName: "Panda", imageName: "animal_panda", eats: "BAMBUS"),
        Animal(id: "FLAGERMUS", displayName: "Flagermus", imageName: "animal_bat", eats: "INSEKTER"),
        Animal(id: "LEMUR", displayName: "Lemur", imageName: "animal_lemur", eats: "FRUGT"),
        Animal(id: "VASKEBJOERN", displayName: "Vaskebjørn", imageName: "animal_raccoon", eats: "ALT"),
        Animal(id: "PINDSVIN", displayName: "Pindsvin", imageName: "animal_hedgehog", eats: "INSEKTER"),
        Animal(id: "VILDSVIN", displayName: "Vildsvin", imageName: "animal_wild_boar", eats: "ROEDDER"),
        Animal(id: "ANTILOPE", displayName: "Antilope", imageName: "animal_antelope", eats: "GRAS"),
        Animal(id: "BOEFFEL", displayName: "Skovbøffel", imageName: "animal_buffalo", eats: "GRAS"),
        Animal(id: "MUNGOS", displayName: "Mungos", imageName: "animal_mongoose", eats: "INSEKTER"),
        Animal(id: "ODDER", displayName: "Odder", imageName: "animal_otter", eats: "FISK"),
        Animal(id: "MULDVARP", displayName: "Muldvarp", imageName: "animal_mole", eats: "ORME"),
        Animal(id: "NAESEHORN", displayName: "Næsehorn", imageName: "animal_rhino", eats: "GRAS"),
        Animal(id: "FLODHHEST", displayName: "Flodhest", imageName: "animal_hippo", eats: "GRAS"),
        Animal(id: "OKAPI", displayName: "Okapi", imageName: "animal_okapi", eats: "BLADE"),
        Animal(id: "GEPARD", displayName: "Gepard", imageName: "animal_cheetah", eats: "KOED"),
        Animal(id: "BAELTEDYR", displayName: "Bæltedyr", imageName: "animal_armadillo", eats: "INSEKTER"),
        Animal(id: "SNELEOPARD", displayName: "Sneleopard", imageName: "animal_snow_leopard", eats: "KOED"),
        Animal(id: "FLYVEFISK", displayName: "Flyvefisk", imageName: "animal_flying_fish", eats: "PLANKTON"),
        Animal(id: "ABE", displayName: "Abe", imageName: "animal_monkey", eats: "BANAN"),
        Animal(id: "KO", displayName: "Ko", imageName: "animal_cow", eats: "GRAS"),
        Animal(id: "PINGVIN", displayName: "Pingvin", imageName: "animal_penguin", eats: "FISK"),
        Animal(id: "KANIN", displayName: "Kanin", imageName: "animal_rabbit", eats: "PLANTER"),
        Animal(id: "KAT", displayName: "Kat", imageName: "animal_cat", eats: "ALT"),
        Animal(id: "HUND", displayName: "Hund", imageName: "animal_dog", eats: "ALT"),
        Animal(id: "SAEL", displayName: "Sæl", imageName: "animal_seal", eats: "FISK"),
        Animal(id: "PAPEGOEJE", displayName: "Papegøje", imageName: "animal_parrot", eats: "FRUGT"),
        Animal(id: "EGERN", displayName: "Egern", imageName: "animal_squirrel", eats: "NOEDDER"),
        Animal(id: "SKILDPADDE", displayName: "Skildpadde", imageName: "animal_turtle", eats: "PLANTER"),
        Animal(id: "DELFIN", displayName: "Delfin", imageName: "animal_dolphin", eats: "FISK"),
        Animal(id: "ISBJORN", displayName: "Isbjørn", imageName: "animal_polar_bear", eats: "FISK"),
        Animal(id: "QUOKKA", displayName: "Quokka", imageName: "animal_quokka", eats: "FRUGT"),
        Animal(id: "UGLE", displayName: "Ugle", imageName: "animal_owl", eats: "FUGLEFRO"),
        Animal(id: "KOLIBRI", displayName: "Kolibri", imageName: "animal_hummingbird", eats: "NEKTAR"),
        Animal(id: "KAMAELEON", displayName: "Kamæleon", imageName: "animal_chameleon", eats: "INSEKTER"),
        Animal(id: "SURIKAT", displayName: "Surikat", imageName: "animal_meerkat", eats: "INSEKTER"),
        Animal(id: "LUNDE", displayName: "Lunde", imageName: "animal_puffin", eats: "FISK"),
        Animal(id: "TUKAN", displayName: "Tukan", imageName: "animal_toucan", eats: "FRUGT"),
        Animal(id: "AXOLOTL", displayName: "Axolotl", imageName: "animal_axolotl", eats: "ORME"),
        Animal(id: "SOMMERFUGL", displayName: "Sommerfugl", imageName: "animal_butterfly", eats: "NEKTAR"),
        Animal(id: "GRIB", displayName: "Grib", imageName: "animal_vulture", eats: "KOED"),
        Animal(id: "KAEGURU", displayName: "Kænguru", imageName: "animal_kangaroo", eats: "KORN"),
        Animal(id: "ZEBRA", displayName: "Zebra", imageName: "animal_zebra", eats: "GRAS"),
        Animal(id: "STRUDS", displayName: "Struds", imageName: "animal_ostrich", eats: "KORN"),
        Animal(id: "FAAR", displayName: "Får", imageName: "animal_sheep", eats: "GRAS"),
        Animal(id: "RENSDYR", displayName: "Rensdyr", imageName: "animal_reindeer", eats: "ROEDDER"),
        Animal(id: "ELG", displayName: "Elg", imageName: "animal_moose", eats: "BLADE"),
        Animal(id: "HVALROS", displayName: "Hvalros", imageName: "animal_walrus", eats: "SKALDYR"),
        Animal(id: "SPAEKHUGGER", displayName: "Spækhugger", imageName: "animal_orca", eats: "FISK"),
        Animal(id: "SVAERDFISK", displayName: "Sværdfisk", imageName: "animal_swordfish", eats: "FISK"),
        Animal(id: "KRABBE", displayName: "Krabbe", imageName: "animal_crab", eats: "SKALDYR"),
        Animal(id: "GOPLER", displayName: "Gopler", imageName: "animal_jellyfish", eats: "PLANKTON"),
        Animal(id: "BLÆKSPRUTTE", displayName: "Blæksprutte", imageName: "animal_octopus", eats: "SKALDYR"),
        Animal(id: "PLUMPLORI", displayName: "Plumplori", imageName: "animal_slow_loris", eats: "INSEKTER"),
        Animal(id: "MANDRIL", displayName: "Mandril", imageName: "animal_mandrill", eats: "FRUGT"),
        Animal(id: "VISACHA", displayName: "Viscacha", imageName: "animal_viscacha", eats: "GRAS"),
        Animal(id: "JAEV", displayName: "Jærv", imageName: "animal_wolverine", eats: "KOED"),
        Animal(id: "SKAELDYR", displayName: "Skældyr", imageName: "animal_pangolin", eats: "INSEKTER")
    ]
}

struct QuestionGenerator {
    static func randomQuestion(optionCount: Int = 3) -> AnimalQuestion {
        let animal = AnimalDatabase.all.randomElement()!
        let correctFood = FoodDatabase.all.first { $0.id == animal.eats }!
        let wrongFoods = FoodDatabase.all
            .filter { $0.id != animal.eats }
            .shuffled()
            .prefix(max(0, optionCount - 1))
        let options = ([correctFood] + wrongFoods).shuffled()
        return AnimalQuestion(
            animal: animal,
            questionText: "Hvad spiser \(animal.displayName.lowercased())?",
            options: Array(options),
            correctOptionID: correctFood.id
        )
    }
}

// MARK: - PreferenceKey for anchors

struct AnswerAnchorKey: PreferenceKey {
    typealias Value = [String: Anchor<CGRect>]
    static var defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - SpeechManager (uændret, bruges til fallback TTS)

final class SpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func preload() {
        let utterance = AVSpeechUtterance(string: " ")
        utterance.voice = AVSpeechSynthesisVoice(language: "da-DK")
        utterance.rate = 0.4
        synthesizer.speak(utterance)
    }

    func speak(_ text: String, completion: (() -> Void)? = nil) {
        self.completion = completion
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "da-DK")
        utterance.pitchMultiplier = 1.10
        utterance.rate = 0.40
        utterance.postUtteranceDelay = 0.25
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            self?.completion?()
            self?.completion = nil
        }
    }
}

// MARK: - AnimalGameView

struct AnimalGameView: View {
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
    @State private var score: Int = 0
    @State private var helpMode: Bool = false
    @State private var debugMode: Bool = false
    @State private var currentQuestion: AnimalQuestion = QuestionGenerator.randomQuestion()
    @State private var dragLine: DragLine? = nil
    @State private var answerAnchors: [String: Anchor<CGRect>] = [:]
    @State private var answerFramesGlobal: [String: CGRect] = [:]
    @State private var cursorPosition: CGPoint = .zero
    @State private var dropPoint: CGPoint? = nil
    @State private var dragStart: CGPoint? = nil
    @State private var showSuccess: Bool = false
    @State private var showSuccessButton: Bool = false
    @State private var showErrorFlash: Bool = false
    @StateObject private var speechManager = SpeechManager()
    private let hitPadding: CGFloat = 40
    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    var body: some View {
        GeometryReader { outerGeo in
            ZStack {
                Color.white.ignoresSafeArea()
                if gameStarted {
                    VStack(spacing: 0) {
                        topButtonBar
                            .padding(.top, 8)
                        Spacer(minLength: 8)
                        gameLayout(outerGeo: outerGeo)
                        Spacer(minLength: 8)
                        scoreCounter
                            .padding(.bottom, 20)
                    }
                    .safeAreaPadding(.horizontal, horizontalContentPadding(for: outerGeo))
                    .safeAreaPadding(.bottom, 8)
                }
                if !gameStarted {
                    startScreen
                }
                if helpMode, gameStarted {
                    helpOverlay
                }
                if showSuccess {
                    successOverlay
                }
                if showErrorFlash {
                    Color.red.opacity(0.3).ignoresSafeArea()
                }
                dragLineView
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(in: outerGeo))
            .onPreferenceChange(AnswerAnchorKey.self) { anchors in
                answerAnchors = anchors
                var newFrames: [String: CGRect] = [:]
                for (id, anchor) in anchors {
                    let rect = outerGeo[anchor]
                    newFrames[id] = rect
                }
                answerFramesGlobal = newFrames
            }
            .onAppear {
                speechManager.preload()
                if startImmediately {
                    gameStarted = true
                    speakQuestion()
                } else {
                    speakIntro()
                }
            }
        }
    }

    // MARK: - Top Bar
    private var topButtonBar: some View {
        HStack(spacing: 20) {
            Button(action: { onBackToHub() }) {
                Text("← Tilbage")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.1))
                    .cornerRadius(10)
            }

            Button(action: { speakQuestion() }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 26, weight: .bold))
                    .padding(10)
                    .background(Color.black.opacity(0.1))
                    .clipShape(Circle())
            }

            Button(action: { helpMode.toggle() }) {
                Image(systemName: helpMode ? "eye.fill" : "eye")
                    .font(.system(size: 26, weight: .bold))
                    .padding(10)
                    .background(Color.black.opacity(0.1))
                    .clipShape(Circle())
            }

            Spacer()
        }
    }

    // MARK: - Game Layout
    private func gameLayout(outerGeo: GeometryProxy) -> some View {
        if !isPhone {
            return AnyView(ipadGameLayout)
        }

        let size = outerGeo.size
        let isPortrait = size.height >= size.width
        let useVerticalLayout = isPortrait
        let isPhoneLandscape = !useVerticalLayout

        let contentMaxWidth: CGFloat = {
            if useVerticalLayout { return min(size.width * 0.96, 560) }
            return min(size.width * 0.94, 900)
        }()

        let imageSize = min(
            useVerticalLayout ? size.width * 0.56 : size.height * 0.52,
            useVerticalLayout ? size.height * 0.30 : size.width * 0.40,
            useVerticalLayout ? 300 : 250
        )

        let optionColumnWidth = useVerticalLayout
            ? min(contentMaxWidth, 500)
            : min(contentMaxWidth * 0.48, 340)

        let optionSpacing = useVerticalLayout
            ? max(12, min(32, size.height * 0.035))
            : max(8, min(16, size.height * 0.02))
        let columnSpacing = max(12, min(28, size.width * 0.02))
        let verticalSpacing = max(16, min(36, size.height * 0.03))

        return AnyView(Group {
            if useVerticalLayout {
                VStack(spacing: verticalSpacing) {
                    animalImage(size: imageSize)
                    answerColumn(width: optionColumnWidth, spacing: optionSpacing)
                }
            } else {
                HStack(alignment: .center, spacing: columnSpacing) {
                    animalImage(size: imageSize)
                        .frame(width: contentMaxWidth * 0.42)

                    answerColumn(width: optionColumnWidth, spacing: optionSpacing, compactLandscape: isPhoneLandscape)
                        .frame(width: optionColumnWidth, alignment: .center)
                }
            }
        }
        .frame(maxWidth: contentMaxWidth, maxHeight: .infinity, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center))
    }

    private var ipadGameLayout: some View {
        HStack(spacing: 80) {
            VStack {
                Image(currentQuestion.animal.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 40) {
                ForEach(currentQuestion.options) { option in
                    ipadAnswerBubble(option: option)
                        .anchorPreference(key: AnswerAnchorKey.self, value: .bounds) { anchor in
                            [option.id: anchor]
                        }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 80)
    }

    private func animalImage(size: CGFloat) -> some View {
        Image(currentQuestion.animal.imageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func answerColumn(width: CGFloat, spacing: CGFloat, compactLandscape: Bool = false) -> some View {
        VStack(spacing: spacing) {
            ForEach(currentQuestion.options) { option in
                answerBubble(option: option, targetWidth: width, compactLandscape: compactLandscape)
                    .anchorPreference(key: AnswerAnchorKey.self, value: .bounds) { anchor in
                        [option.id: anchor]
                    }
            }
        }
        .frame(maxWidth: width)
    }

    // MARK: - Answer Bubble
    private func answerBubble(option: FoodOption, targetWidth: CGFloat, compactLandscape: Bool) -> some View {
        let imageHeight = compactLandscape
            ? max(50, min(82, targetWidth * 0.24))
            : max(64, min(120, targetWidth * 0.42))

        return ZStack {
            Image(option.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, compactLandscape ? 8 : 14)
                .padding(.vertical, compactLandscape ? 4 : 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.2))
        .cornerRadius(compactLandscape ? 14 : 16)
        .overlay(
            RoundedRectangle(cornerRadius: compactLandscape ? 14 : 16)
                .stroke(Color.blue, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    private func ipadAnswerBubble(option: FoodOption) -> some View {
        ZStack {
            Image(option.imageName)
                .resizable()
                .scaledToFit()
                .frame(height: 90)
                .padding(.horizontal, 20)
        }
        .background(Color.blue.opacity(0.2))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }

    private func horizontalContentPadding(for outerGeo: GeometryProxy) -> CGFloat {
        let width = outerGeo.size.width
        if width < 430 { return 12 }
        if width < 700 { return 16 }
        if width < 1000 { return 24 }
        return 32
    }

    // MARK: - Drag Gesture
    private func dragGesture(in outerGeo: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let point = value.location
                if dragStart == nil {
                    dragStart = point
                }
                cursorPosition = point
                if let start = dragStart {
                    dragLine = DragLine(start: start, end: point)
                }
            }
            .onEnded { value in
                let point = value.location
                cursorPosition = point
                dropPoint = point
                handleDrop(at: point)
                dragLine = nil
                dragStart = nil
            }
    }

    // MARK: - Drag Line View
    private var dragLineView: some View {
        ZStack {
            if let line = dragLine {
                Path { path in
                    path.move(to: line.start)
                    path.addLine(to: line.end)
                }
                .stroke(Color.green, lineWidth: 6)
            }

            Circle()
                .fill(Color.blue.opacity(0.7))
                .frame(width: 18, height: 18)
                .position(cursorPosition)

            if let drop = dropPoint {
                Circle()
                    .fill(Color.green.opacity(0.7))
                    .frame(width: 24, height: 24)
                    .position(drop)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Handle Drop
    private func handleDrop(at point: CGPoint) {
        guard let correct = currentQuestion.correctOption else { return }

        if let frame = answerFramesGlobal[correct.id] {
            let hitFrame = frame.insetBy(dx: -hitPadding, dy: -hitPadding)
            if hitFrame.contains(point) {
                score += 1
                showSuccess = true
                showSuccessButton = true

                // Erstat TTS med modulær AI-sekvens
                speakCorrect()

                return
            }
        }

        var foundWrong = false
        for (_, frame) in answerFramesGlobal {
            let hitFrame = frame.insetBy(dx: -hitPadding, dy: -hitPadding)
            if hitFrame.contains(point) {
                foundWrong = true
                break
            }
        }

        showErrorFlash = true
        let delay: TimeInterval = foundWrong ? 0.4 : 0.25
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            showErrorFlash = false
            speakWrong()
        }
    }

    private func loadNextQuestion() {
        currentQuestion = QuestionGenerator.randomQuestion()
        dropPoint = nil
        dragLine = nil
        dragStart = nil
        speakQuestion()
    }

    // MARK: - Score
    private var scoreCounter: some View {
        HStack {
            Image(systemName: "star.fill")
                .foregroundColor(.yellow)
                Text("\(startImmediately ? session.allGameScore : score)")
                .font(.title.bold())
        }
        .padding(12)
        .background(Color.black.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Help
    private var helpOverlay: some View {
        VStack {
            Spacer()
            if let correct = currentQuestion.correctOption {
                Text(correct.title)
                    .font(.system(size: 60, weight: .heavy))
                    .foregroundColor(.green)
                    .padding()
                    .background(Color.white.opacity(0.8))
                    .cornerRadius(20)
            }
            Spacer()
        }
    }

    // MARK: - Success
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Rigtigt!")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                if let correct = currentQuestion.correctOption {
                    Text("\(currentQuestion.animal.displayName) spiser \(correct.title)")
                        .font(.title2)
                        .foregroundColor(.white)
                }

                if showSuccessButton {
                    Button(action: {
                        showSuccess = false
                        showSuccessButton = false
                        if startImmediately {
                            onExit()
                        } else {
                            loadNextQuestion()
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

    // MARK: - Start Screen
    private var startScreen: some View {
        GeometryReader { geo in
            let size = geo.size
            let isLandscape = size.width > size.height
            let compactPhoneLandscape = isPhone && isLandscape

            VStack(spacing: compactPhoneLandscape ? 12 : 24) {
                if compactPhoneLandscape {
                    Spacer(minLength: 8)
                } else {
                    Spacer(minLength: 80)
                }

                Text("🐵")
                    .font(.system(size: compactPhoneLandscape ? 80 : 120))

                Text("Dyrespillet")
                    .font((compactPhoneLandscape ? Font.system(size: 44, weight: .bold) : .largeTitle.bold()))
                    .foregroundColor(.black)

                Text("Velkommen til Dyrespillet.\nForbind dyret med den mad, det spiser.")
                    .multilineTextAlignment(.center)
                    .font(compactPhoneLandscape ? .title3 : .body)
                    .foregroundColor(.black)
                    .padding()
                    .frame(maxWidth: compactPhoneLandscape ? min(size.width * 0.78, 620) : nil)
                    .background(Color.black.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, compactPhoneLandscape ? 12 : 24)

                Button(action: {
                    gameStarted = true
                    speakQuestion()
                }) {
                    Text("Spil")
                        .font(.title2.bold())
                        .padding(.vertical, compactPhoneLandscape ? 10 : 12)
                        .padding(.horizontal, compactPhoneLandscape ? 44 : 40)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }

                Spacer(minLength: compactPhoneLandscape ? 8 : 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.horizontal, compactPhoneLandscape ? 12 : 0)
            .background(Color.white.ignoresSafeArea())
        }
    }

    // MARK: - Voice helpers (opdateret til modulær AI-sekvens)

    private func speakIntro() {
        AudioVoiceManager.shared.debugLogging = false
        let aiFiles: [String?] = ["animal_intro"]
        let segmentTexts: [String?] = ["Velkommen til dyrespillet"]
        AudioVoiceManager.shared.speakSequencePerSegment(aiFiles: aiFiles, segmentFallbackTexts: segmentTexts, completion: nil)
    }

    private func speakQuestion() {
        AudioVoiceManager.shared.debugLogging = false
        let animalAudio = currentQuestion.animal.imageName // fx "animal_lion"
        let aiFiles: [String?] = ["animal_forbind", animalAudio, "animal_til_maden"]
        let segmentTexts: [String?] = ["Forbind", currentQuestion.animal.displayName, "til den mad den spiser"]
        AudioVoiceManager.shared.speakSequencePerSegment(aiFiles: aiFiles, segmentFallbackTexts: segmentTexts, completion: nil)
    }

    private func speakCorrect() {
        guard let correct = currentQuestion.correctOption else { return }
        AudioVoiceManager.shared.debugLogging = false
        let animalAudio = currentQuestion.animal.imageName
        let foodAudio = correct.imageName
        let aiFiles: [String?] = ["animal_rigtigt", animalAudio, "animal_spiser", foodAudio]
        let segmentTexts: [String?] = ["Rigtigt!", currentQuestion.animal.displayName, "spiser", correct.title]
        AudioVoiceManager.shared.speakSequencePerSegment(aiFiles: aiFiles, segmentFallbackTexts: segmentTexts, completion: nil)
    }

    private func speakWrong() {
        AudioVoiceManager.shared.debugLogging = false
        // Kun den generiske fejlfil
        let aiFiles: [String?] = ["animal_forkert"]
        let segmentTexts: [String?] = ["Det var ikke rigtigt"]
        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: segmentTexts,
            completion: nil
        )
    }



    // Helper: normaliser id til filnavn (fjerner diakritika, laver lowercase og erstatter ikke-alfanumeriske tegn med underscore)
    private func sanitizedFileName(from id: String) -> String {
        // Fjern diakritika
        var s = id.folding(options: .diacriticInsensitive, locale: .current)
        s = s.lowercased()
        // Erstat mellemrum og bindestreger med underscore
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.replacingOccurrences(of: "-", with: "_")
        // Hold kun alfanumeriske og underscore
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        s = String(s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        // Trim multiple underscores
        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        // Trim leading/trailing underscores
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return s
    }
}

// MARK: - Preview

struct AnimalGameView_Previews: PreviewProvider {
    static var previews: some View {
        AnimalGameView(
            difficulty: .easy,
            startImmediately: true,
            onExit: {},
            onBackToHub: {}
        )
    }
}
