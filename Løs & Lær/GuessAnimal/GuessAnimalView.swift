// GuessAnimalView.swift
// "Gæt et dyr" - mere interaktiv samtale-UI med hurtig dansk talegenkendelse.
// Husk Info.plist: NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription.

import SwiftUI
import AVFoundation
import Speech
import Combine

// MARK: - Data

struct GuessAnimal: Identifiable {
    let id = UUID()
    let displayName: String
    let imageName: String
    let audioFile: String
    let clues: [String]
    let synonyms: [String]
}

private let pocAnimals: [GuessAnimal] = [
    GuessAnimal(
        displayName: "Ko",
        imageName: "animal_cow",
        audioFile: "animal_cow",
        clues: ["Den har fire ben.", "Den har et yver.", "Den siger muuu."],
        synonyms: ["ko", "koen", "kvaeg"]
    ),
    GuessAnimal(
        displayName: "Hund",
        imageName: "animal_dog",
        audioFile: "animal_dog",
        clues: ["Den kan være menneskets bedste ven.", "Den logrer med halen.", "Den siger vov vov."],
        synonyms: ["hund", "hunden", "vovhund"]
    ),
    GuessAnimal(
        displayName: "Kat",
        imageName: "animal_cat",
        audioFile: "animal_cat",
        clues: ["Den kan spinde.", "Den fanger mus.", "Den siger miav."],
        synonyms: ["kat", "katten"]
    ),
    GuessAnimal(
        displayName: "Papegøje",
        imageName: "animal_parrot",
        audioFile: "animal_parrot",
        clues: ["Den kan flyve.", "Den kan efterligne ord.", "Den har farverige fjer."],
        synonyms: ["papegoje", "papegoeje", "papegøje", "papegøjen"]
    ),
    GuessAnimal(
        displayName: "Elefant",
        imageName: "animal_elephant",
        audioFile: "animal_elephant",
        clues: ["Den har en lang snabel.", "Den er meget stor.", "Den laver en trumpet-lyd."],
        synonyms: ["elefant", "elefanten"]
    ),
    GuessAnimal(
        displayName: "Løve",
        imageName: "animal_lion",
        audioFile: "animal_lion",
        clues: ["Den kaldes junglens konge.", "Han har en manke.", "Den brøler."],
        synonyms: ["loeve", "løve", "løven", "loeven"]
    ),
    GuessAnimal(
        displayName: "Delfin",
        imageName: "animal_dolphin",
        audioFile: "animal_dolphin",
        clues: ["Den lever i vand.", "Den kan lave spring.", "Den klikker og piber."],
        synonyms: ["delfin", "delfinen"]
    ),
    GuessAnimal(
        displayName: "Får",
        imageName: "animal_sheep",
        audioFile: "animal_sheep",
        clues: ["Den har uld.", "Den går på marker.", "Den siger mææææ."],
        synonyms: ["faar", "får", "faaret", "fåret"]
    ),
    GuessAnimal(
        displayName: "Kænguru",
        imageName: "animal_kangaroo",
        audioFile: "animal_kangaroo",
        clues: ["Den hopper langt.", "Den har en pung.", "Den bor i Australien."],
        synonyms: ["kaenguru", "kænguru", "kænguruen", "kaenguruen"]
    ),
    GuessAnimal(
        displayName: "Pingvin",
        imageName: "animal_penguin",
        audioFile: "animal_penguin",
        clues: ["Den kan ikke flyve, men svømmer godt.", "Den går på to ben og vralter.", "Den bor i kolde egne."],
        synonyms: ["pingvin", "pingvinen"]
    )
]

private struct GuessMessage: Identifiable {
    enum Role {
        case host
        case player
        case system
    }

    let id = UUID()
    let role: Role
    let text: String
}

// MARK: - Text helpers

private func normalizedDanish(_ value: String) -> String {
    let folded = value
        .lowercased()
        .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "da-DK"))

    let cleaned = folded.map { char -> Character in
        if char.isLetter || char.isNumber || char.isWhitespace {
            return char
        }
        return " "
    }

    return String(cleaned)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func uniqueOrdered(_ values: [String]) -> [String] {
    var set = Set<String>()
    var result: [String] = []
    for value in values {
        let item = normalizedDanish(value)
        guard !item.isEmpty else { continue }
        if set.insert(item).inserted {
            result.append(item)
        }
    }
    return result
}

private func candidateGuesses(from transcript: String) -> [String] {
    let cleaned = normalizedDanish(transcript)
    guard !cleaned.isEmpty else { return [] }

    let words = cleaned.split(separator: " ").map(String.init)
    var options = [cleaned]

    if let lastWord = words.last {
        options.append(lastWord)
    }
    if words.count >= 2 {
        options.append(words.suffix(2).joined(separator: " "))
    }

    return uniqueOrdered(options)
}

private func levenshtein(_ aStr: String, _ bStr: String) -> Int {
    let a = Array(aStr)
    let b = Array(bStr)
    let n = a.count
    let m = b.count

    if n == 0 { return m }
    if m == 0 { return n }

    var matrix = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    for i in 0...n { matrix[i][0] = i }
    for j in 0...m { matrix[0][j] = j }

    for i in 1...n {
        for j in 1...m {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            matrix[i][j] = min(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost
            )
        }
    }
    return matrix[n][m]
}

private func bestMatchedSynonym(candidates: [String], synonyms: [String]) -> String? {
    let normalizedSynonyms = uniqueOrdered(synonyms)
    guard !normalizedSynonyms.isEmpty else { return nil }

    for candidate in candidates {
        let normalizedCandidate = normalizedDanish(candidate)
        guard !normalizedCandidate.isEmpty else { continue }

        let words = normalizedCandidate.split(separator: " ").map(String.init)
        var checks = [normalizedCandidate]
        checks.append(contentsOf: words)
        if words.count >= 2 {
            checks.append(words.suffix(2).joined(separator: " "))
        }

        for check in uniqueOrdered(checks) {
            for synonym in normalizedSynonyms {
                if check == synonym || check.contains(synonym) || synonym.contains(check) {
                    return synonym
                }

                let maxDistance = synonym.count <= 4 ? 1 : 2
                if levenshtein(check, synonym) <= maxDistance {
                    return synonym
                }
            }
        }
    }

    return nil
}

final class DanishSpeechRecognizer: ObservableObject {
    @Published var isAuthorized = false
    @Published var isListening = false
    @Published var liveTranscription = ""
    @Published var candidates: [String] = []
    @Published var lastErrorMessage: String = ""

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "da-DK"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var stopWorkItem: DispatchWorkItem?
    private var onWindowFinished: ((String, [String]) -> Void)?
    private var hasWindowFinished = false

    init() {
        requestAuthorization()
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.isAuthorized = (status == .authorized)
            }
        }

        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func startListening(window: TimeInterval, contextualWords: [String], completion: @escaping (String, [String]) -> Void) {
        stopListening()

        guard isAuthorized else {
            lastErrorMessage = "Talegenkendelse er ikke tilladt endnu."
            return
        }

        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            lastErrorMessage = "Mikrofonen er ikke tilladt."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            lastErrorMessage = "Talegenkendelse er ikke tilgængelig lige nu."
            return
        }

        lastErrorMessage = ""
        liveTranscription = ""
        candidates = []
        hasWindowFinished = false
        onWindowFinished = completion

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastErrorMessage = "Kunne ikke starte mikrofonen."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = uniqueOrdered(contextualWords)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastErrorMessage = "Mikrofonen kunne ikke startes."
            cleanupAudioPipeline()
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let segmentWords = result.bestTranscription.segments.map(\.substring)
                let refreshed = uniqueOrdered(self.candidates + candidateGuesses(from: text) + segmentWords)

                DispatchQueue.main.async {
                    self.liveTranscription = text
                    self.candidates = Array(refreshed.prefix(6))
                }

                if result.isFinal {
                    self.finishWindow()
                    return
                }
            }

            if error != nil {
                self.finishWindow()
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.finishWindow()
        }
        stopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + window, execute: workItem)
    }

    func stopListening() {
        hasWindowFinished = true
        stopWorkItem?.cancel()
        stopWorkItem = nil
        onWindowFinished = nil
        if isListening || audioEngine.isRunning || task != nil || request != nil {
            cleanupAudioPipeline()
        }
    }

    private func finishWindow() {
        guard !hasWindowFinished else { return }
        hasWindowFinished = true

        stopWorkItem?.cancel()
        stopWorkItem = nil

        let text = liveTranscription
        let currentCandidates = candidates
        let callback = onWindowFinished
        onWindowFinished = nil

        cleanupAudioPipeline()

        DispatchQueue.main.async {
            callback?(text, currentCandidates)
        }
    }

    private func cleanupAudioPipeline() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil

        if Thread.isMainThread {
            isListening = false
        } else {
            DispatchQueue.main.async {
                self.isListening = false
            }
        }
    }
}

// MARK: - Main View

struct GuessAnimalView: View {
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void

    @State private var animals = pocAnimals.shuffled()
    @State private var currentIndex = 0
    @State private var clueIndex = 0
    @State private var attemptsForCurrentClue = 0
    @State private var score = 0
    @State private var messages: [GuessMessage] = []

    @State private var showMultipleChoice = false
    @State private var showPermissionAlert = false
    @State private var showResultOverlay = false
    @State private var resultTitle = ""
    @State private var resultSubtitle = ""
    @State private var lastRoundWasSuccess = false

    @State private var listeningProgress: Double = 0
    @State private var secondsLeft = 0
    @State private var countdownTimer: Timer?
    @State private var listeningStartedAt: Date?
    @State private var listeningDuration: TimeInterval = 0
    @State private var latestHeardText = ""
    @State private var latestSuggestionChips: [String] = []
    @State private var hasStarted = false

    @State private var player: AVAudioPlayer?

    @StateObject private var recognizer = DanishSpeechRecognizer()

    private var currentAnimal: GuessAnimal {
        animals[currentIndex]
    }

    private var listeningWindow: TimeInterval {
        4.0
    }

    private var visibleChips: [String] {
        if recognizer.isListening {
            return recognizer.candidates
        }
        return latestSuggestionChips
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.93, blue: 0.84), Color(red: 0.82, green: 0.94, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                topBar
                heroCard
                conversationCard
                listeningCard
                controls
                scoreBadge
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showMultipleChoice) {
            MultipleChoiceView(animals: animals, correctIndex: currentIndex) { selected in
                showMultipleChoice = false
                evaluateImageGuess(selectedIndex: selected)
            }
        }
        .alert(isPresented: $showPermissionAlert) {
            Alert(
                title: Text("Mikrofon mangler"),
                message: Text("Giv adgang til mikrofon og talegenkendelse i Indstillinger for at spille med stemme."),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(resultOverlay)
        .onAppear {
            if !hasStarted {
                hasStarted = true
                startRound(showIntro: true)
            }
        }
        .onDisappear {
            teardown()
        }
        .onChange(of: recognizer.isListening) { _, isListening in
            if isListening {
                startListeningFeedback(duration: listeningWindow)
            } else {
                stopListeningFeedback()
            }
        }
    }

    // MARK: - UI

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                teardown()
                onBackToHub()
            }) {
                Image(systemName: "chevron.left")
                    .font(.headline.bold())
                    .foregroundColor(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Circle())
            }

            Spacer()

            Text("Gæt et dyr")
                .font(.headline.weight(.semibold))

            Spacer()

            Button(action: repeatCurrentClue) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.72))
                    .clipShape(Circle())
            }
        }
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.8))

            VStack(spacing: 10) {
                if showResultOverlay {
                    Image(currentAnimal.imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 135)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .font(.system(size: 58, weight: .light))
                        .foregroundColor(.black.opacity(0.55))
                }

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index <= clueIndex ? Color.orange : Color.gray.opacity(0.3))
                            .frame(height: 7)
                    }
                }
                .padding(.horizontal, 32)
            }
            .padding(.vertical, 14)
        }
        .frame(height: 210)
    }

    private var conversationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Samtale")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.black.opacity(0.7))

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { message in
                            messageRow(message)
                        }
                        Color.clear.frame(height: 2).id("conversation-bottom")
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: messages.count) { _ in
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .background(Color.white.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func messageRow(_ message: GuessMessage) -> some View {
        HStack {
            if message.role == .player {
                Spacer(minLength: 28)
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundColor(message.role == .system ? .black.opacity(0.76) : .primary)
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .background(bubbleColor(for: message.role))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            if message.role != .player {
                Spacer(minLength: 28)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func bubbleColor(for role: GuessMessage.Role) -> Color {
        switch role {
        case .host: return Color(red: 0.78, green: 0.94, blue: 0.89)
        case .player: return Color(red: 0.99, green: 0.90, blue: 0.72)
        case .system: return Color.white
        }
    }

    private var listeningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(recognizer.isListening ? Color.red : Color.gray.opacity(0.35))
                    .frame(width: 11, height: 11)
                Text(recognizer.isListening ? "Lytter nu (\(secondsLeft)s)" : "Klar til næste gæt")
                    .font(.subheadline.weight(.medium))
            }

            ProgressView(value: listeningProgress, total: 1.0)
                .tint(.red)

            if !recognizer.liveTranscription.isEmpty {
                Text("Jeg hører: \(recognizer.liveTranscription)")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.72))
            } else if !latestHeardText.isEmpty {
                Text("Sidste gæt: \(latestHeardText)")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.72))
            }

            if !visibleChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(visibleChips.prefix(5), id: \.self) { chip in
                            Text(chip)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: {
                manualListenTap()
            }) {
                Label(recognizer.isListening ? "Lytter..." : "Tal nu", systemImage: "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(recognizer.isListening ? Color.red.opacity(0.28) : Color.green.opacity(0.24))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(showResultOverlay || recognizer.isListening)

            Button(action: {
                showMultipleChoice = true
            }) {
                Label("Vis billeder", systemImage: "photo.on.rectangle.angled")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.16))
                    .foregroundColor(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(showResultOverlay)
        }
    }

    private var scoreBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "rosette")
            Text("Score: \(score)")
                .font(.subheadline.bold())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.9))
        .clipShape(Capsule())
    }

    private var resultOverlay: some View {
        Group {
            if showResultOverlay {
                ZStack {
                    Color.black.opacity(0.34).ignoresSafeArea()

                    VStack(spacing: 12) {
                        Text(resultTitle)
                            .font(.title2.bold())
                            .foregroundColor(.white)

                        Text(resultSubtitle)
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 10) {
                            Button("Hør lyd") {
                                if lastRoundWasSuccess {
                                    speakSuccessSequence()
                                } else {
                                    playAnimalSound(named: currentAnimal.audioFile)
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                            Button(startImmediately ? "Afslut" : "Næste dyr") {
                                showResultOverlay = false
                                if startImmediately {
                                    teardown()
                                    onExit()
                                } else {
                                    nextRound()
                                }
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    // MARK: - Game flow

    private func startRound(showIntro: Bool = false) {
        recognizer.stopListening()
        stopListeningFeedback()

        clueIndex = 0
        attemptsForCurrentClue = 0
        lastRoundWasSuccess = false
        latestHeardText = ""
        latestSuggestionChips = []
        showResultOverlay = false

        if showIntro {
            appendMessage(role: .system, text: "Jeg giver en ledetråd, og mikrofonen åbner i \(Int(listeningWindow)) sekunder. Sig dyret højt.")
        }

        runClueStep()
    }

    private func runClueStep() {
        guard !showResultOverlay else { return }
        let clue = currentAnimal.clues[clueIndex]
        appendMessage(role: .host, text: "Ledetråd \(clueIndex + 1): \(clue)")

        speakClue(at: clueIndex) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                openListeningWindow()
            }
        }
    }

    private func openListeningWindow() {
        guard !showResultOverlay else { return }
        guard !recognizer.isListening else { return }

        guard recognizer.isAuthorized else {
            showPermissionAlert = true
            appendMessage(role: .system, text: "Mikrofon er ikke tilladt endnu. Du kan stadig vælge via billeder.")
            return
        }

        appendMessage(role: .system, text: "Sig dit gæt nu.")

        let context = currentAnimal.synonyms + [currentAnimal.displayName]
        recognizer.startListening(window: listeningWindow, contextualWords: context) { transcript, candidates in
            handleRecognitionResult(transcript: transcript, candidates: candidates)
        }
    }

    private func handleRecognitionResult(transcript: String, candidates: [String]) {
        latestHeardText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        latestSuggestionChips = Array(uniqueOrdered(candidates).prefix(5))

        let candidatePool = uniqueOrdered([transcript] + candidates + recognizer.candidates)
        let matched = bestMatchedSynonym(candidates: candidatePool, synonyms: currentAnimal.synonyms)

        if !latestHeardText.isEmpty {
            appendMessage(role: .player, text: latestHeardText)
        } else if let first = latestSuggestionChips.first {
            appendMessage(role: .player, text: first)
        } else {
            appendMessage(role: .player, text: "...")
        }

        if matched != nil {
            finishRound(success: true)
            return
        }

        let spokeSomething = !latestHeardText.isEmpty || !latestSuggestionChips.isEmpty
        if !spokeSomething {
            attemptsForCurrentClue += 1
            if attemptsForCurrentClue < 2 {
                appendMessage(role: .system, text: "Jeg hørte ikke noget. Prøv igen med samme ledetråd.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    openListeningWindow()
                }
                return
            }
        }

        attemptsForCurrentClue = 0
        if clueIndex < 2 {
            clueIndex += 1
            appendMessage(role: .host, text: "Ikke helt. Her kommer næste ledetråd.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                runClueStep()
            }
        } else {
            finishRound(success: false)
        }
    }

    private func evaluateImageGuess(selectedIndex: Int) {
        recognizer.stopListening()
        stopListeningFeedback()

        if selectedIndex == currentIndex {
            finishRound(success: true)
        } else {
            finishRound(success: false)
        }
    }

    private func finishRound(success: Bool) {
        recognizer.stopListening()
        stopListeningFeedback()

        if success {
            lastRoundWasSuccess = true
            let points = pointsForCurrentClue()
            score += points
            resultTitle = "Rigtigt! +\(points) point"
            resultSubtitle = "Det var \(currentAnimal.displayName.lowercased())."
            appendMessage(role: .host, text: "Flot. Det var \(currentAnimal.displayName.lowercased()).")
            speakSuccessSequence()
        } else {
            lastRoundWasSuccess = false
            resultTitle = "Godt forsøgt"
            resultSubtitle = "Det rigtige svar var \(currentAnimal.displayName.lowercased())."
            appendMessage(role: .host, text: "Det rigtige svar var \(currentAnimal.displayName.lowercased()).")
            playAnimalSound(named: currentAnimal.audioFile)
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showResultOverlay = true
        }
    }

    private func nextRound() {
        if currentIndex + 1 < animals.count {
            currentIndex += 1
        } else {
            animals.shuffle()
            currentIndex = 0
        }
        startRound()
    }

    private func repeatCurrentClue() {
        guard !showResultOverlay else { return }
        recognizer.stopListening()
        stopListeningFeedback()
        appendMessage(role: .system, text: "Vi gentager ledetråden.")
        runClueStep()
    }

    private func manualListenTap() {
        guard !showResultOverlay else { return }
        if !recognizer.isAuthorized {
            showPermissionAlert = true
            return
        }
        recognizer.stopListening()
        stopListeningFeedback()
        openListeningWindow()
    }

    private func pointsForCurrentClue() -> Int {
        switch clueIndex {
        case 0: return 3
        case 1: return 2
        default: return 1
        }
    }

    // MARK: - Listening visuals

    private func startListeningFeedback(duration: TimeInterval) {
        countdownTimer?.invalidate()
        listeningStartedAt = Date()
        listeningDuration = duration
        listeningProgress = 0
        secondsLeft = Int(duration.rounded(.up))

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { timer in
            guard let start = listeningStartedAt else {
                timer.invalidate()
                return
            }

            let elapsed = Date().timeIntervalSince(start)
            let safeDuration = max(listeningDuration, 0.01)
            let remaining = max(0, safeDuration - elapsed)

            listeningProgress = min(max(elapsed / safeDuration, 0), 1)
            secondsLeft = Int(ceil(remaining))

            if remaining <= 0 {
                listeningProgress = 1
                secondsLeft = 0
                timer.invalidate()
            }
        }
        RunLoop.main.add(countdownTimer!, forMode: .common)
    }

    private func stopListeningFeedback() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        listeningStartedAt = nil
        listeningDuration = 0
        listeningProgress = 0
        secondsLeft = 0
    }

    // MARK: - Utilities

    private func appendMessage(role: GuessMessage.Role, text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            messages.append(GuessMessage(role: role, text: text))
        }
    }

    private func clueAudioFileName(for animal: GuessAnimal, clueIndex: Int) -> String {
        "\(animal.imageName)_clue\(clueIndex + 1)"
    }

    private func speakClue(at clueIndex: Int, completion: (() -> Void)? = nil) {
        let clueText = currentAnimal.clues[clueIndex]
        let clueFile = clueAudioFileName(for: currentAnimal, clueIndex: clueIndex)

        AudioVoiceManager.shared.debugLogging = false
        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: [clueFile],
            segmentFallbackTexts: [clueText],
            completion: completion
        )
    }

    private func speakSuccessSequence() {
        AudioVoiceManager.shared.debugLogging = false
        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: ["Generic_Flot", currentAnimal.audioFile],
            segmentFallbackTexts: ["Flot", currentAnimal.displayName],
            completion: nil
        )
    }

    private func playAnimalSound(named fileName: String) {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "mp3") else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("Audio play error:", error)
        }
    }

    private func teardown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        recognizer.stopListening()
        player?.stop()
    }
}

// MARK: - Multiple choice

struct MultipleChoiceView: View {
    let animals: [GuessAnimal]
    let correctIndex: Int
    let onChoose: (Int) -> Void

    @Environment(\.presentationMode) private var presentationMode
    private let options: [Int]

    init(animals: [GuessAnimal], correctIndex: Int, onChoose: @escaping (Int) -> Void) {
        self.animals = animals
        self.correctIndex = correctIndex
        self.onChoose = onChoose

        var generated = [correctIndex]
        var pool = animals.indices.filter { $0 != correctIndex }.shuffled()
        while generated.count < min(4, animals.count), let next = pool.first {
            generated.append(next)
            pool.removeFirst()
        }
        self.options = generated.shuffled()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                Text("Vælg billedet")
                    .font(.title3.bold())

                ForEach(options, id: \.self) { index in
                    Button(action: {
                        onChoose(index)
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack(spacing: 12) {
                            Image(animals[index].imageName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 72, height: 72)
                                .background(Color.gray.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))

                            Text(animals[index].displayName)
                                .font(.headline)
                                .foregroundColor(.primary)

                            Spacer()
                        }
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Luk") {
                        presentationMode.wrappedValue.dismiss()
                    }
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
