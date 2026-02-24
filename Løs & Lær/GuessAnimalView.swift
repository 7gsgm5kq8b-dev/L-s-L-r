// GuessAnimalView.swift
// POC: "Gæt et dyr" med 10 dyr, 3 ledetråde, on-device speech recognition
// Paste denne fil direkte i dit Xcode projekt.
// Husk Info.plist: NSMicrophoneUsageDescription, NSSpeechRecognitionUsageDescription

import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - Data model
struct GuessAnimal: Identifiable {
    let id = UUID()
    let imageName: String
    let audioFile: String
    let clues: [String] // 3 clues
    let synonyms: [String] // whitelist for matching (lowercased)
}

// MARK: - POC dataset (10 dyr)
private let pocAnimals: [GuessAnimal] = [
    GuessAnimal(imageName: "animal_cow", audioFile: "animal_cow",
                clues: ["Den har fire ben.", "Den har et yver.", "Den siger muuu."],
                synonyms: ["ko","koen","kvæg"]),
    GuessAnimal(imageName: "animal_dog", audioFile: "animal_dog",
                clues: ["Den kan være menneskets bedste ven.", "Den logrer med halen.", "Den siger vov vov."],
                synonyms: ["hund","hunden"]),
    GuessAnimal(imageName: "animal_cat", audioFile: "animal_cat",
                clues: ["Den kan spinde.", "Den fanger mus.", "Den siger miav."],
                synonyms: ["kat","katten"]),
    GuessAnimal(imageName: "animal_parrot", audioFile: "animal_parrot",
                clues: ["Den kan flyve.", "Den kan efterligne ord.", "Den har farverige fjer."],
                synonyms: ["papegøje","papegøjen"]),
    GuessAnimal(imageName: "animal_elephant", audioFile: "animal_elephant",
                clues: ["Den har en lang snabel.", "Den er meget stor.", "Den laver en trumpet-lyd."],
                synonyms: ["elefant","elefanten"]),
    GuessAnimal(imageName: "animal_lion", audioFile: "animal_lion",
                clues: ["Den kaldes junglens konge.", "Han har en manke (han).", "Den brøler."],
                synonyms: ["løve","løven"]),
    GuessAnimal(imageName: "animal_dolphin", audioFile: "animal_dolphin",
                clues: ["Den lever i vand.", "Den kan lave spring.", "Den klikker og piber."],
                synonyms: ["delfin","delfinen"]),
    GuessAnimal(imageName: "animal_sheep", audioFile: "animal_sheep",
                clues: ["Den har uld.", "Den går på marker.", "Den siger bææ."],
                synonyms: ["får","fåret","fårene"]),
    GuessAnimal(imageName: "animal_kangaroo", audioFile: "animal_kangaroo",
                clues: ["Den hopper langt.", "Den har en pung.", "Den bor i Australien."],
                synonyms: ["kænguru","kænguruen"]),
    GuessAnimal(imageName: "animal_penguin", audioFile: "animal_penguin",
                clues: ["Den kan ikke flyve, men svømmer godt.", "Den går på to ben og vralter.", "Den bor i kolde egne."],
                synonyms: ["pingvin","pingvinen"])
]

// MARK: - Simple Speech Recognizer wrapper (on-device)
final class SimpleSpeechRecognizer: ObservableObject {
    @Published var lastTranscription: String = ""
    @Published var isAuthorized: Bool = false
    @Published var isListening: Bool = false

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "da-DK"))

    // Debug publisher to inspect recognition results in runtime
    let debugTranscription = PassthroughSubject<String, Never>()

    init() {
        DispatchQueue.main.async { [weak self] in
            self?.requestAuthorization()
        }
    }

    func requestAuthorization() { 
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                self.isAuthorized = (status == .authorized)
            }
        }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in /* handled when starting */ }
    }

    func startListening(maxDuration: TimeInterval = 4.0) {
        guard isAuthorized else { return }
        if audioEngine.isRunning { stopListening(); return }

        // Ensure AVAudioSession configured and active BEFORE querying node format
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("AVAudioSession config error:", error)
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = false

        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)

        // Debug: log format info
        print("DEBUG: recordingFormat sampleRate=\(recordingFormat.sampleRate) channels=\(recordingFormat.channelCount)")

        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, when in
            self.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("AudioEngine start error:", error)
            stopListening()
            return
        }

        isListening = true
        task = recognizer?.recognitionTask(with: request!) { result, error in
            if let r = result {
                let text = r.bestTranscription.formattedString.lowercased()
                DispatchQueue.main.async {
                    self.lastTranscription = text
                    self.debugTranscription.send(text) // publish for debug observers
                }
            }
            if let err = error {
                print("Recognition error:", err)
                self.stopListening()
            }
        }

        // Stop automatically after maxDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + maxDuration) {
            self.stopListening()
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
            request?.endAudio()
        }
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }
}

// MARK: - Helper: simple fuzzy/substring match
fileprivate func matchesTranscription(_ transcription: String, synonyms: [String]) -> Bool {
    let cleaned = transcription
        .lowercased()
        .folding(options: .diacriticInsensitive, locale: .current)

    // remove common stopwords
    let stopwords = ["en","et","det","jeg","tror","er","måske","det er","jeg tror"]
    var candidate = cleaned
    for s in stopwords { candidate = candidate.replacingOccurrences(of: s, with: " ") }
    candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

    // direct substring or exact match
    for syn in synonyms {
        let s = syn.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        if candidate.contains(s) || s.contains(candidate) { return true }
        // small edit distance fallback (very small)
        if levenshtein(candidate, s) <= 2 { return true }
    }
    return false
}

// Levenshtein (small implementation)
fileprivate func levenshtein(_ aStr: String, _ bStr: String) -> Int {
    let a = Array(aStr)
    let b = Array(bStr)
    let n = a.count, m = b.count
    if n == 0 { return m }
    if m == 0 { return n }
    var matrix = Array(repeating: Array(repeating: 0, count: m+1), count: n+1)
    for i in 0...n { matrix[i][0] = i }
    for j in 0...m { matrix[0][j] = j }
    for i in 1...n {
        for j in 1...m {
            matrix[i][j] = min(
                matrix[i-1][j] + 1,
                matrix[i][j-1] + 1,
                matrix[i-1][j-1] + (a[i-1] == b[j-1] ? 0 : 1)
            )
        }
    }
    return matrix[n][m]
}

// MARK: - Main View
struct GuessAnimalView: View {
    // These parameters match AppRoot's call signature
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    // POC state
    @State private var animals = pocAnimals.shuffled()
    @State private var currentIndex: Int = 0
    @State private var revealedClueIndex: Int = 0
    @State private var score: Int = 0
    @State private var showPermissionModal: Bool = false
    @State private var showMultipleChoice: Bool = false
    @State private var showResultOverlay: Bool = false
    @State private var resultMessage: String = ""
    @State private var playAudioPlayer: AVAudioPlayer? = nil

    @StateObject private var recognizer = SimpleSpeechRecognizer()
    @State private var speechSynth = AVSpeechSynthesizer()
    @State private var debugCancellable: AnyCancellable?

    private var currentAnimal: GuessAnimal { animals[currentIndex] }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Top bar with sampled buttons like other games
            HStack(spacing: 12) {
                Button(action: {
                    // Back to hub
                    onBackToHub()
                }) {
                    Image(systemName: "chevron.left")
                        .padding(8)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: {
                        // Speaker: speak current revealed clue (or first if none)
                        speakCurrentClue()
                    }) {
                        Image(systemName: "speaker.wave.2.fill")
                            .padding(8)
                    }

                    Button(action: {
                        // Ny ledetråd: reveal next clue
                        revealNextClue()
                    }) {
                        Image(systemName: "lightbulb.fill")
                            .padding(8)
                    }

                    Button(action: {
                        // Spring
                        skipRound()
                    }) {
                        Image(systemName: "forward.fill")
                            .padding(8)
                    }

                    Button(action: {
                        // Næste dyr (force next)
                        nextRound()
                    }) {
                        Image(systemName: "arrow.right.circle.fill")
                            .padding(8)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Main content
            VStack(spacing: 18) {
                HStack {
                    Text("Gæt et dyr")
                        .font(.largeTitle.bold())
                    Spacer()
                }
                .padding(.horizontal)

                Spacer()

                // Billede (skjult indtil runden slutter)
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .frame(height: 260)
                    if showResultOverlay {
                        // vis billede når runden er afsluttet
                        Image(currentAnimal.imageName)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 220)
                            .padding()
                    } else {
                        // neutral placeholder
                        Image(systemName: "questionmark.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal)

                // Ledetråde
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3) { i in
                        HStack {
                            Text("\(i+1).")
                                .bold()
                            Text(i <= revealedClueIndex ? currentAnimal.clues[i] : "—")
                                .foregroundColor(i <= revealedClueIndex ? .primary : .secondary)
                        }
                    }
                }
                .padding(.horizontal)

                // Mikrofon forklaring + knap
                VStack(spacing: 8) {
                    Text("Spillet bruger mikrofonen til at høre dit svar — kun til denne runde. Du kan altid vælge svar ved at trykke på et billede i stedet.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    HStack(spacing: 20) {
                        Button(action: {
                            // start listening
                            if !recognizer.isAuthorized {
                                showPermissionModal = true
                            } else {
                                recognizer.startListening()
                                // observe transcription after short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                    evaluateTranscription()
                                }
                                // also evaluate after max listen time
                                DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
                                    evaluateTranscription()
                                }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(recognizer.isListening ? Color.red : Color.green)
                                    .frame(width: 78, height: 78)
                                Image(systemName: "mic.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28, weight: .bold))
                            }
                        }

                        Button(action: {
                            // fallback: show multiple choice
                            showMultipleChoice = true
                        }) {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                Text("Vis billeder")
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.top, 8)

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .onAppear {
                // subscribe to debug publisher to log transcriptions (helpful for breakpoints)
                debugCancellable = recognizer.debugTranscription.sink { text in
                    print("DEBUG TRANSCRIPTION:", text)
                }
            }
            .onDisappear {
                debugCancellable?.cancel()
            }

            Divider()

            // Footer with centered score
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "rosette.fill")
                        .foregroundColor(.yellow)
                    Text("Score: \(score)")
                        .bold()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 20)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                Spacer()
            }
            .padding()
        }
        .sheet(isPresented: $showMultipleChoice) {
            MultipleChoiceView(animals: animals, correctIndex: currentIndex) { chosen in
                showMultipleChoice = false
                handleGuess(chosenIndex: chosen)
            }
        }
        .alert(isPresented: $showPermissionModal) {
            Alert(title: Text("Mikrofon"), message: Text("Giv tilladelse i Indstillinger for at bruge mikrofonen."), dismissButton: .default(Text("OK")))
        }
        .onChange(of: recognizer.lastTranscription) { _ in
            // optional: immediate evaluation
            evaluateTranscription()
        }
        .onDisappear {
            recognizer.stopListening()
            playAudioPlayer?.stop()
        }
        .overlay(
            // result overlay when round ends
            Group {
                if showResultOverlay {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: 16) {
                        Text(resultMessage)
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                        HStack(spacing: 18) {
                            Button(action: {
                                // play animal sound
                                playAnimalSound(named: currentAnimal.audioFile)
                            }) {
                                Text("Hør lyden igen")
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.white)
                                    .cornerRadius(10)
                            }

                            Button(action: {
                                // next round
                                showResultOverlay = false
                                // If running inside AllGames flow, call onExit when appropriate.
                                if startImmediately {
                                    onExit()
                                } else {
                                    nextRound()
                                }
                            }) {
                                Text("Næste")
                                    .bold()
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.white)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                }
            }
        )
    }

    // MARK: - Actions & logic
    private func revealNextClue() {
        if revealedClueIndex < 2 {
            revealedClueIndex += 1
            // speak the newly revealed clue
            speakCurrentClue()
        } else {
            // already last clue — optionally play animal sound
            playAnimalSound(named: currentAnimal.audioFile)
        }
    }

    private func speakCurrentClue() {
        let idx = min(revealedClueIndex, 2)
        let text = currentAnimal.clues[idx]
        let utter = AVSpeechUtterance(string: text)
        utter.voice = AVSpeechSynthesisVoice(language: "da-DK")
        utter.rate = 0.48
        speechSynth.stopSpeaking(at: .immediate)
        speechSynth.speak(utter)
    }

    private func evaluateTranscription() {
        let t = recognizer.lastTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // match against current animal synonyms
        if matchesTranscription(t, synonyms: currentAnimal.synonyms) {
            // determine points based on revealed clue index
            let points = pointsForCurrentClue()
            score += points
            resultMessage = "Rigtigt! +\(points) point"
            showResultOverlay = true
            playAnimalSound(named: currentAnimal.audioFile)
            return
        } else {
            // not matched: reveal next clue or show multiple choice if last clue
            if revealedClueIndex < 2 {
                revealedClueIndex += 1
                // clear transcription for next attempt
                recognizer.lastTranscription = ""
            } else {
                // final: reveal answer
                resultMessage = "Det var \(displayName(for: currentAnimal))."
                showResultOverlay = true
                playAnimalSound(named: currentAnimal.audioFile)
            }
        }
    }

    private func handleGuess(chosenIndex: Int) {
        if chosenIndex == currentIndex {
            let points = pointsForCurrentClue()
            score += points
            resultMessage = "Rigtigt! +\(points) point"
        } else {
            resultMessage = "Forkert — det var \(displayName(for: currentAnimal))."
        }
        showResultOverlay = true
        playAnimalSound(named: currentAnimal.audioFile)
    }

    private func pointsForCurrentClue() -> Int {
        switch revealedClueIndex {
        case 0: return 3
        case 1: return 2
        default: return 1
        }
    }

    private func nextRound() {
        // reset state and advance
        revealedClueIndex = 0
        showResultOverlay = false
        recognizer.lastTranscription = ""
        if currentIndex + 1 < animals.count {
            currentIndex += 1
        } else {
            // reshuffle and restart
            animals.shuffle()
            currentIndex = 0
        }
    }

    private func skipRound() {
        // reveal answer and move on
        resultMessage = "Det var \(displayName(for: currentAnimal))."
        showResultOverlay = true
        playAnimalSound(named: currentAnimal.audioFile)
    }

    private func displayName(for animal: GuessAnimal) -> String {
        // derive readable name from imageName (animal_xxx -> Xxx)
        let base = animal.imageName.replacingOccurrences(of: "animal_", with: "")
        return base.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func playAnimalSound(named fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            // fallback: TTS could be used here
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            playAudioPlayer = try AVAudioPlayer(contentsOf: url)
            playAudioPlayer?.prepareToPlay()
            playAudioPlayer?.play()
        } catch {
            print("Audio play error:", error)
        }
    }
}

// MARK: - Multiple choice fallback view
struct MultipleChoiceView: View {
    let animals: [GuessAnimal]
    let correctIndex: Int
    let onChoose: (Int) -> Void

    @Environment(\.presentationMode) var presentationMode

    // build 3 options: correct + 2 random others
    private var options: [Int] {
        var idxs = Set<Int>()
        idxs.insert(correctIndex)
        while idxs.count < 3 {
            idxs.insert(Int.random(in: 0..<animals.count))
        }
        return Array(idxs).shuffled()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                Text("Vælg billedet")
                    .font(.title2.bold())
                ForEach(options, id: \.self) { idx in
                    Button(action: {
                        onChoose(idx)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Image(animals[idx].imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 80, height: 80)
                                .cornerRadius(8)
                            Text(animals[idx].imageName.replacingOccurrences(of: "animal_", with: "").capitalized)
                                .foregroundColor(.black)
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                }
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Luk") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview
struct GuessAnimalView_Previews: PreviewProvider {
    static var previews: some View {
        GuessAnimalView(
            difficulty: .easy,
            startImmediately: false,
            onExit: {},
            onBackToHub: {}
        )
    }
}
