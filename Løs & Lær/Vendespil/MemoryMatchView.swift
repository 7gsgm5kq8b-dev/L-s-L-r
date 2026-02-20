import SwiftUI
import Combine

// MARK: - Model
struct Card: Identifiable, Equatable {
    let id = UUID()
    let animalName: String
    var isFaceUp: Bool = false
    var isMatched: Bool = false
}

// MARK: - ViewModel
final class MemoryMatchViewModel: ObservableObject {
    @Published private(set) var cards: [Card] = []
    @Published var moves: Int = 0
    @Published var matchesFound: Int = 0
    @Published var disableInput: Bool = false

    private var firstSelectedIndex: Int? = nil
    private let flipBackDelay: TimeInterval = 0.7

    init(animalNames: [String]) {
        setupCards(with: animalNames)
    }

    func setupCards(with animalNames: [String]) {
        var deck: [Card] = []
        for name in animalNames {
            deck.append(Card(animalName: name))
            deck.append(Card(animalName: name))
        }
        deck.shuffle()

        self.cards = deck
        self.moves = 0
        self.matchesFound = 0
        self.firstSelectedIndex = nil
        self.disableInput = false
    }

    func chooseCard(at index: Int) {
        guard !disableInput else { return }
        guard cards.indices.contains(index) else { return }
        guard !cards[index].isFaceUp && !cards[index].isMatched else { return }

        cards[index].isFaceUp = true

        if let first = firstSelectedIndex {
            moves += 1
            disableInput = true

            if cards[first].animalName == cards[index].animalName {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    self.cards[first].isMatched = true
                    self.cards[index].isMatched = true
                    self.matchesFound += 1
                    self.firstSelectedIndex = nil
                    self.disableInput = false
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + flipBackDelay) {
                    self.cards[first].isFaceUp = false
                    self.cards[index].isFaceUp = false
                    self.firstSelectedIndex = nil
                    self.disableInput = false
                }
            }
        } else {
            firstSelectedIndex = index
        }
    }

    var isGameComplete: Bool {
        cards.allSatisfy { $0.isMatched }
    }
}

// MARK: - MemoryMatchView (med generisk tale)
struct MemoryMatchView: View {
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    @StateObject private var vm: MemoryMatchViewModel
    @StateObject private var speechManager = SpeechManager()

    @State private var showSuccess: Bool = false
    @State private var successMessage: String = ""

    // Speech control
    @State private var lastSpokenCardID: UUID? = nil
    @State private var speakingLock: Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let tileSpacing: CGFloat = 12

    // MARK: - Mapping: imageName -> audioFile (fra din vedhæftede mapping)
    // Hvis du senere ændrer filnavne, opdater denne dictionary.
    private let imageToAudioMap: [String: String] = [
        "animal_antelope": "animal_antilope",
        "animal_armadillo": "animal_armadillo",
        "animal_axolotl": "animal_axolotl",
        "animal_bat": "animal_flagermus",
        "animal_beaver": "animal_bæver",
        "animal_buffalo": "animal_buffalo",
        "animal_butterfly": "animal_butterfly",
        "animal_cat": "animal_cat",
        "animal_chameleon": "animal_chameleon",
        "animal_cheetah": "animal_cheetah",
        "animal_chimpanzee": "animal_chimpanse",
        "animal_cow": "animal_cow",
        "animal_crab": "animal_crab",
        "animal_dog": "animal_dog",
        "animal_dolphin": "animal_dolphin",
        "animal_elephant": "animal_elefant",
        "animal_flamingo": "animal_flamingo",
        "animal_flying_fish": "animal_flying_fish",
        "animal_giraffe": "animal_giraf",
        "animal_gorilla": "animal_gorilla",
        "animal_hedgehog": "animal_hedgehog",
        "animal_hippo": "animal_hippo",
        "animal_hummingbird": "animal_hummingbird",
        "animal_hyena": "animal_hyæne",
        "animal_jellyfish": "animal_jellyfish",
        "animal_kangaroo": "animal_kangaroo",
        "animal_koala": "animal_koala",
        "animal_lemur": "animal_lemur",
        "animal_lion": "animal_løve",
        "animal_mandrill": "animal_mandrill",
        "animal_meerkat": "animal_meerkat",
        "animal_mole": "animal_mole",
        "animal_mongoose": "animal_mongoose",
        "animal_monkey": "animal_monkey",
        "animal_moose": "animal_moose",
        "animal_octopus": "animal_octopus",
        "animal_okapi": "animal_okapi",
        "animal_orca": "animal_orca",
        "animal_ostrich": "animal_ostrich",
        "animal_otter": "animal_otter",
        "animal_owl": "animal_owl",
        "animal_panda": "animal_panda",
        "animal_pangolin": "animal_pangolin",
        "animal_parrot": "animal_parrot",
        "animal_penguin": "animal_penguin",
        "animal_polar_bear": "animal_polar_bear",
        "animal_puffin": "animal_puffin",
        "animal_quokka": "animal_quokka",
        "animal_rabbit": "animal_rabbit",
        "animal_raccoon": "animal_vaskebjørn",
        "animal_reindeer": "animal_reindeer",
        "animal_rhino": "animal_rhino",
        "animal_seal": "animal_seal",
        "animal_sheep": "animal_sheep",
        "animal_sloth": "animal_dovendyr",
        "animal_slow_loris": "animal_slow_loris",
        "animal_snow_leopard": "animal_snow_leopard",
        "animal_squirrel": "animal_squirrel",
        "animal_swordfish": "animal_swordfish",
        "animal_tiger": "animal_tiger",
        "animal_toucan": "animal_toucan",
        "animal_turtle": "animal_turtle",
        "animal_viscacha": "animal_viscacha",
        "animal_vulture": "animal_vulture",
        "animal_walrus": "animal_walrus",
        "animal_wild_boar": "animal_vildsvin",
        "animal_wolverine": "animal_wolverine",
        "animal_zebra": "animal_zebra"
    ]

    // MARK: - Init
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

        // Vælg 8 unikke dyr tilfældigt fra AnimalDatabase og brug deres imageName
        let allAnimalImageNames = AnimalDatabase.all.map { $0.imageName }
        let pairCount = 8 // 4x4 grid => 8 par
        let chosenAnimals = Array(allAnimalImageNames.shuffled().prefix(pairCount))

        // Initialiser view model med de valgte dyr (kun én gang)
        _vm = StateObject(wrappedValue: MemoryMatchViewModel(animalNames: chosenAnimals))

    }

    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            // Auto-scale: beregn kortstørrelse ud fra både bredde og højde og safe area
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            let horizontalPadding: CGFloat = 24 // samlet horisontal padding omkring grid
            // konservativ approx. plads til topbar + titler og footer; juster hvis din top/footer er større
            let approxTopArea: CGFloat = 120
            let approxFooterArea: CGFloat = 64

            let verticalReserved = safeTop + approxTopArea + approxFooterArea + safeBottom

            let availableWidth = geo.size.width - horizontalPadding
            let availableHeight = max(0, geo.size.height - verticalReserved)

            let cardWidth = (availableWidth - tileSpacing * 3) / 4
            let cardHeight = (availableHeight - tileSpacing * 3) / 4

            let cardSize = max(48, min(cardWidth, cardHeight)) // sikrer minimum touch‑størrelse


            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 8) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 18)

                    Text("Vendespil")
                        .font(.largeTitle.bold())
                        .padding(.top, 6)

                    Text("Find parene")
                        .foregroundColor(.gray)
                        .padding(.bottom, 8)

                    LazyVGrid(columns: columns, spacing: tileSpacing) {
                        ForEach(vm.cards.indices, id: \.self) { idx in
                            cardView(for: vm.cards[idx], index: idx, size: cardSize)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Spacer(minLength: 8)

                    footerBar
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                }

                if showSuccess {
                    successOverlay
                }
            }
            .onAppear {
                speechManager.preload()
                // Preload TTS and optionally prepare audio resources if you have a preload API
            }
            .onChange(of: vm.matchesFound) { _ in
                if vm.isGameComplete {
                    successMessage = "Flot! Du fandt alle parene!"
                    AudioVoiceManager.shared.speakWithFallback(
                        aiFile: "win_match",
                        fallback: { speechManager.speak(successMessage) }
                    )
                    showSuccess = true
                }
            }
        }
    }

    // MARK: - Top Bar (inkl. Nyt spil)
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: { onBackToHub() }) {
                Text("← Tilbage")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.06))
                    .cornerRadius(10)
            }

            Button(action: {
                let animals = vm.cards.map { $0.animalName }.uniquePreservingOrder()
                vm.setupCards(with: animals)
            }) {
                Text("Nyt spil")
                    .font(.headline.bold())
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }

            Spacer()

            Button(action: { speechManager.speak("Vendespil. Find parene.") }) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 22, weight: .bold))
                    .padding(10)
                    .background(Color.black.opacity(0.06))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Card View
    private func cardView(for card: Card, index: Int, size: CGFloat) -> some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.18)) {
                vm.chooseCard(at: index)
            }
            // Speak the animal generically after flipping
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                // Ensure we reference the up-to-date card from vm
                guard vm.cards.indices.contains(index) else { return }
                let updatedCard = vm.cards[index]
                speakAnimalIfNeeded(for: updatedCard)
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 214/255, green: 238/255, blue: 255/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

                if card.isFaceUp || card.isMatched {
                    Image(card.animalName)
                        .resizable()
                        .scaledToFit()
                        .padding(size * 0.12)
                        .accessibilityLabel(localizedAnimalName(for: card.animalName))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white)
                        .padding(size * 0.12)
                        .overlay(
                            Image(systemName: "pawprint.fill")
                                .font(.system(size: size * 0.32))
                                .foregroundColor(Color.blue.opacity(0.6))
                        )
                }

                if card.isMatched {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green, lineWidth: 3)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .disabled(vm.disableInput || card.isMatched)
    }

    // MARK: - Speak helpers (View-side)
    private func speakAnimalIfNeeded(for card: Card) {
        // Avoid repeating same card rapidly or overlapping speech
        guard lastSpokenCardID != card.id, !speakingLock else { return }
        lastSpokenCardID = card.id
        speakingLock = true

        // Find mapped ai file
        let aiFile = imageToAudioMap[card.animalName]
        let fallbackText = localizedAnimalName(for: card.animalName)

        if let ai = aiFile {
            AudioVoiceManager.shared.speakWithFallback(aiFile: ai) {
                // fallback closure uses TTS
                DispatchQueue.main.async {
                    self.speechManager.speak(fallbackText)
                }
            }
        } else {
            // No recorded file; use TTS
            speechManager.speak(fallbackText)
        }

        // Release lock after short delay to avoid overlap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            self.speakingLock = false
        }
    }

    // Localized display name for accessibility and fallback TTS
    private func localizedAnimalName(for animalName: String) -> String {
        // Try to find displayName from AnimalDatabase if available
        if let animal = AnimalDatabase.all.first(where: { $0.imageName == animalName }) {
            return animal.displayName
        }
        // Fallback: strip prefix and capitalize
        let base = animalName.replacingOccurrences(of: "animal_", with: "")
        return base.replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: - Footer Bar (Træk / Par)
    private var footerBar: some View {
        HStack {
            Text("Træk: \(vm.moves)")
                .font(.headline)

            Spacer()

            Text("Stik: \(vm.matchesFound)")
                .font(.headline)
        }
    }

    // MARK: - Success Overlay
    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 18) {
                Text(successMessage)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Button(action: {
                    showSuccess = false
                    let animals = vm.cards.map { $0.animalName }.uniquePreservingOrder()
                    vm.setupCards(with: animals)
                }) {
                    Text("Spil igen")
                        .font(.headline.bold())
                        .padding(.vertical, 10)
                        .padding(.horizontal, 32)
                        .background(Color.white)
                        .foregroundColor(.green)
                        .cornerRadius(14)
                        .shadow(radius: 4)
                }
            }
            .padding()
        }
    }
}

// MARK: - Helpers
private extension Array where Element == String {
    func uniquePreservingOrder() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for s in self {
            if !seen.contains(s) {
                seen.insert(s)
                out.append(s)
            }
        }
        return out
    }
}

// MARK: - Preview
struct MemoryMatchView_Previews: PreviewProvider {
    static var previews: some View {
        MemoryMatchView(
            difficulty: .easy,
            startImmediately: false,
            onExit: {},
            onBackToHub: {}
        )
    }
}
