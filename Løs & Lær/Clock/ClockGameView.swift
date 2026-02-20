//
//  ClockGameView.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 25/01/2026.
//

import SwiftUI
import AVFoundation
import Combine


// MARK: - Models

struct ClockOption: Identifiable, Hashable {
    let id = UUID().uuidString
    let hour: Int    // 1..12
    let minute: Int  // 0..59

    // Digital label (fx "04:35")
    var digitalLabel: String {
        String(format: "%02d:%02d", hour % 12 == 0 ? 12 : hour % 12, minute)
    }
}

// MARK: - Question Generator

struct ClockQuestion {
    let target: ClockOption
    let options: [ClockOption]
}

struct ClockQuestionGenerator {
    // De minutværdier vi vil bruge (i minutter efter timen eller i-form)
    // 5,10,15,20,25,30,35,40,45,50,55
    static let minutePool: [Int] = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]

    static func randomQuestion() -> ClockQuestion {
        // vælg en time 1..12
        let hour = Int.random(in: 1...12)
        // vælg et minut fra pool
        let minute = minutePool.randomElement()!

        let target = ClockOption(hour: hour, minute: minute)

        // lav to distraktorer: vælg to andre minutter fra pool, sikre unikke
        var distractors: [ClockOption] = []
        var pool = minutePool.filter { $0 != minute }.shuffled()

        while distractors.count < 2 && !pool.isEmpty {
            let m = pool.removeFirst()
            // distraktor kan være samme hour eller (for minutes > 30) hour-1/ +1 logic is handled in spoken form only
            distractors.append(ClockOption(hour: hour, minute: m))
        }

        // Hvis pool ikke gav nok (meget usandsynligt), lav små variationer
        while distractors.count < 2 {
            let m = minute + (distractors.count + 1) * 5
            distractors.append(ClockOption(hour: hour, minute: ((m % 60) + 60) % 60))
        }

        // Bland mulighederne
        var options = [target] + distractors
        options.shuffle()

        return ClockQuestion(target: target, options: options)
    }
}

// MARK: - Speech helpers (dansk tidstekst)

private func spokenTimeText(hour: Int, minute: Int) -> String {
    // Returner dansk mundtlig form, fx "kvart over tre", "fem i halv fem", "halv fem"
    let h = ((hour - 1) % 12) + 1 // ensure 1..12
    func nextHour() -> Int { return (h % 12) + 1 }

    switch minute {
    case 0:
        return "klokken \(h)"
    case 5:
        return "fem over \(h)"
    case 10:
        return "ti over \(h)"
    case 15:
        return "kvart over \(h)"
    case 20:
        return "tyve over \(h)"
    case 25:
        return "femogtyve over \(h)"
    case 30:
        // dansk: "halv (næste time)"
        return "halv \(nextHour())"
    case 35:
        return "fem over halv \(nextHour())"
    case 40:
        return "tyve i \(nextHour())"
    case 45:
        return "kvart i \(nextHour())"
    case 50:
        return "ti i \(nextHour())"
    case 55:
        return "fem i \(nextHour())"
    default:
        // fallback: digital readout
        return String(format: "%02d:%02d", h, minute)
    }
}

// MARK: - Clock drawing view

struct AnalogClockView: View {
    let hour: Int
    let minute: Int
    let size: CGFloat
    
    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = w * 0.48

            ZStack {
                // Face
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
                    .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 2)

                // Numbers 1..12
                ForEach(1...12, id: \.self) { n in
                    let angleDeg = Double(n) / 12.0 * 360.0 - 90.0
                    let angle = degreesToRadians(angleDeg)
                    let labelRadius = radius * 0.78
                    let x = center.x + cos(angle) * labelRadius
                    let y = center.y + sin(angle) * labelRadius

                    Text("\(n)")
                        .font(.system(size: max(10, w * 0.08), weight: .semibold))
                        .foregroundColor(.black)
                        .position(x: x, y: y)
                }

                // hour ticks
                ForEach(0..<12) { tick in
                    Rectangle()
                        .fill(Color.gray)
                        .frame(width: 2, height: w * 0.04)
                        .offset(y: -w * 0.44)
                        .rotationEffect(.degrees(Double(tick) / 12.0 * 360))
                }

                // Minute hand (Path)
                Path { path in
                    let angle = degreesToRadians(minuteAngle(minute: minute))
                    let end = CGPoint(
                        x: center.x + cos(angle) * radius * 0.9,
                        y: center.y + sin(angle) * radius * 0.9
                    )
                    path.move(to: center)
                    path.addLine(to: end)
                }
                .stroke(Color.black, style: StrokeStyle(lineWidth: max(2, w * 0.03), lineCap: .round))
                .zIndex(1)

                // Hour hand (Path, shorter)
                Path { path in
                    let angle = degreesToRadians(hourAngle(hour: hour, minute: minute))
                    let end = CGPoint(
                        x: center.x + cos(angle) * radius * 0.6,
                        y: center.y + sin(angle) * radius * 0.6
                    )
                    path.move(to: center)
                    path.addLine(to: end)
                }
                .stroke(Color.black, style: StrokeStyle(lineWidth: max(3, w * 0.045), lineCap: .round))
                .zIndex(2)

                // center pin
                Circle()
                    .fill(Color.black)
                    .frame(width: w * 0.06, height: w * 0.06)
                    .zIndex(3)
            }
            .frame(width: w, height: w)
            .position(x: center.x, y: center.y)
        }
        .frame(width: size, height: size)
    }

    // Helper: convert degrees to radians
    private func degreesToRadians(_ deg: Double) -> Double {
        return deg * .pi / 180.0
    }

    private func minuteAngle(minute: Int) -> Double {
        return Double(minute) / 60.0 * 360.0 - 90.0
    }

    private func hourAngle(hour: Int, minute: Int) -> Double {
        let h = Double(hour % 12)
        return (h + Double(minute) / 60.0) / 12.0 * 360.0 - 90.0
    }
}




// MARK: - ClockGameView (baseret på AnimalGameView)

struct ClockGameView: View {
    @EnvironmentObject var session: GameSessionManager
    
    let difficulty: Difficulty
    let startImmediately: Bool
    let onExit: () -> Void
    let onBackToHub: () -> Void
    @State private var lastAnswerCorrect: Bool = false

    

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

    // State
    @State private var gameStarted: Bool = false
    @State private var currentQuestion: ClockQuestion = ClockQuestionGenerator.randomQuestion()
    @State private var showSuccess: Bool = false
    @State private var showSuccessButton: Bool = false
    @State private var successMessage: String = ""
    @State private var score: Int = 0
    @State private var debugMode: Bool = false
    @State private var showErrorFlash: Bool = false

    @StateObject private var speechManager = SpeechManager()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()

                if gameStarted {
                    VStack {
                        topBar
                            .padding(.top, 20)
                            .padding(.horizontal, 16)

                        Spacer()

                        // Instruction text
                        Text("Find uret hvor klokken er")
                            .font(.title2.bold())
                            .foregroundColor(.black)

                        Text(spokenTimeText(hour: currentQuestion.target.hour, minute: currentQuestion.target.minute))
                            .font(.title3)
                            .foregroundColor(.black.opacity(0.8))
                            .padding(.bottom, 8)

                        // Options
                        HStack(spacing: 24) {
                            ForEach(currentQuestion.options) { option in
                                VStack(spacing: 8) {
                                    Button(action: {
                                        optionTapped(option)
                                    }) {
                                        AnalogClockView(hour: option.hour, minute: option.minute, size: 120)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 12)
                                                    .stroke(Color.clear, lineWidth: 3)
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    Text(option.digitalLabel)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(.black)
                                }
                            }
                        }
                        .padding(.top, 18)

                        Spacer()

                        scoreCounter
                            .padding(.bottom, 20)
                    }
                } else {
                    startScreen
                }

                if showSuccess {
                    successOverlay
                }

                if showErrorFlash {
                    Color.red.opacity(0.3).ignoresSafeArea()
                }
            }
            .onAppear {
                speechManager.preload()
                if startImmediately {
                    gameStarted = true
                    currentQuestion = ClockQuestionGenerator.randomQuestion()
                    speakQuestion()
                } else {
                    speakIntro()
                }
            }
        }
    }

    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 12) {
            // Venstre side: Tilbage, Gentag (speaker), Spil igen
            HStack(spacing: 12) {
                Button(action: { onBackToHub() }) {
                    Text("← Tilbage")
                        .font(.headline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.06))
                        .cornerRadius(10)
                }

                // Gentag som speaker‑ikon
                Button(action: { speakQuestion() }) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(10)
                        .background(Color.black.opacity(0.03))
                        .cornerRadius(10)
                }

                Button(action: { loadNextQuestion() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Spil igen")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.03))
                    .cornerRadius(10)
                }
            }

            Spacer() // holder knapperne i venstre side
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Start screen
    private var startScreen: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 80)

            Text("⏰")
                .font(.system(size: 120))

            Text("Hvad er klokken?")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            Text("Lyt og vælg det ur, der viser den rigtige tid.")
                .multilineTextAlignment(.center)
                .foregroundColor(.black)
                .padding()
                .background(Color.black.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 24)

            Button(action: {
                gameStarted = true
                currentQuestion = ClockQuestionGenerator.randomQuestion()
                speakQuestion()
            }) {
                Text("Spil")
                    .font(.title2.bold())
                    .padding(.vertical, 12)
                    .padding(.horizontal, 40)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: - Score counter
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

    // MARK: - Actions

    private func optionTapped(_ option: ClockOption) {
        if option == currentQuestion.target {
            // korrekt svar — opdater UI straks
            score += 1
            successMessage = "Rigtigt!"
            showSuccess = true
            lastAnswerCorrect = true
            showSuccessButton = true

            // Byg feedback + tidstokens (genbrug segmentsForQuestion)
            let (allAiFiles, allSegmentTexts) = segmentsForQuestion(option)

            let aiFilesForTime: [String?]
            let textsForTime: [String?]

            if allAiFiles.count > 1 {
                aiFilesForTime = Array(allAiFiles.dropFirst())
                textsForTime = Array(allSegmentTexts.dropFirst())
            } else {
                aiFilesForTime = []
                textsForTime = []
            }

            var aiFiles: [String?] = []
            var segmentTexts: [String?] = []

            aiFiles.append("clock_correct")
            segmentTexts.append("Rigtigt")

            aiFiles.append(contentsOf: aiFilesForTime)
            segmentTexts.append(contentsOf: textsForTime)

            AudioVoiceManager.shared.debugLogging = false

            AudioVoiceManager.shared.speakSequencePerSegment(
                aiFiles: aiFiles,
                segmentFallbackTexts: segmentTexts,
                completion: nil
            )


        } else {
            // forkert svar — ingen pop-up, kun flash + lyd
            // Vis rød flash
            showErrorFlash = true

            // Afspil kort forkert‑lyd (AI) med TTS fallback
            AudioVoiceManager.shared.debugLogging = false
            AudioVoiceManager.shared.speakWithFallback(aiFile: "clock_wrong") {
                // fallback TTS (hvis speakWithFallback ikke selv håndterer TTS)
                speechManager.speak("Det var ikke rigtigt. Prøv igen.") { }
            }

            // Skjul flash efter kort delay (samme delay som Animal)
            let delay: TimeInterval = 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.showErrorFlash = false
            }

            // Sørg for at vi ikke viser success overlay eller "Næste"
            lastAnswerCorrect = false
            showSuccess = false
            showSuccessButton = false
        }
    }







    private func loadNextQuestion() {
        currentQuestion = ClockQuestionGenerator.randomQuestion()
        showSuccess = false
        showSuccessButton = false
        successMessage = ""
        speakQuestion()
    }

    // MARK: - Speech

    private func speakIntro() {
        // Midlertidig debug‑log for at se hvad der afspilles
        AudioVoiceManager.shared.debugLogging = false

        // Forsøg at afspille AI‑filen "clock_intro" (mp3/m4a/wav via urlForResource)
        AudioVoiceManager.shared.speakWithFallback(aiFile: "clock_intro") {
            // Fallback: brug TTS hvis fil mangler eller afspilning fejler
            speechManager.speak("Velkommen til Hvad er klokken. Tryk spil for at starte.")
        }
    }
    
    // Bygger aiFiles + segmentTexts for et ClockQuestion target
    private func segmentsForQuestion(_ target: ClockOption) -> (aiFiles: [String?], segmentTexts: [String?]) {
        let h = ((target.hour - 1) % 12) + 1
        func nextHour() -> Int { return (h % 12) + 1 }

        var aiFiles: [String?] = []
        var segmentTexts: [String?] = []

        // 1) Always start with the generic prompt
        aiFiles.append("clock_find")
        segmentTexts.append("Find uret hvor klokken er")

        let minute = target.minute

        switch minute {
        case 0:
            // Whole hour: only hour token (e.g., "tolv")
            aiFiles.append("hour_\(h)")
            segmentTexts.append(spokenTimeText(hour: target.hour, minute: 0)) // fallback: "klokken X"
        case 30:
            // "halv" + next hour
            aiFiles.append("conn_halv")
            segmentTexts.append("halv")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0)) // fallback: "halv X"
        case 5,10,15,20,25:
            // e.g. "fem over fire"
            aiFiles.append("num_\(String(format: "%02d", minute))")
            segmentTexts.append(spokenTimeText(hour: target.hour, minute: minute)) // fallback short
            aiFiles.append("conn_over")
            segmentTexts.append("over")
            aiFiles.append("hour_\(h)")
            segmentTexts.append(spokenTimeText(hour: target.hour, minute: 0))
        case 35:
            // "fem over halv nextHour" -> num_05, conn_over, conn_halv, hour_next
            aiFiles.append("num_05")
            segmentTexts.append("fem")
            aiFiles.append("conn_over")
            segmentTexts.append("over")
            aiFiles.append("conn_halv")
            segmentTexts.append("halv")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0))
        case 40:
            // "tyve i nextHour" -> num_20, conn_i, hour_next
            aiFiles.append("num_20")
            segmentTexts.append("tyve")
            aiFiles.append("conn_i")
            segmentTexts.append("i")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0))
        case 45:
            // "kvart i nextHour" -> num_15, conn_i, hour_next
            aiFiles.append("num_15")
            segmentTexts.append("kvart")
            aiFiles.append("conn_i")
            segmentTexts.append("i")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0))
        case 50:
            // "ti i nextHour"
            aiFiles.append("num_10")
            segmentTexts.append("ti")
            aiFiles.append("conn_i")
            segmentTexts.append("i")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0))
        case 55:
            // "fem i nextHour"
            aiFiles.append("num_05")
            segmentTexts.append("fem")
            aiFiles.append("conn_i")
            segmentTexts.append("i")
            let nh = nextHour()
            aiFiles.append("hour_\(nh)")
            segmentTexts.append(spokenTimeText(hour: nh, minute: 0))
        default:
            // Fallback: use full spokenTimeText as single TTS segment
            aiFiles.append(nil)
            segmentTexts.append(spokenTimeText(hour: target.hour, minute: target.minute))
        }

        return (aiFiles, segmentTexts)
    }


    private func speakQuestion() {
        // Debug: se hvad der forsøges afspillet
        AudioVoiceManager.shared.debugLogging = false

        let (aiFiles, segmentTexts) = segmentsForQuestion(currentQuestion.target)

        AudioVoiceManager.shared.speakSequencePerSegment(
            aiFiles: aiFiles,
            segmentFallbackTexts: segmentTexts,
            completion: nil
        )
    }


    // MARK: - Overlays

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()

            VStack(spacing: 18) {
                Text(successMessage)
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                // Hvis sidste svar var korrekt: vis "Næste"
                if lastAnswerCorrect && showSuccessButton {
                    Button(action: {
                        showSuccess = false
                        showSuccessButton = false
                        lastAnswerCorrect = false

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
                } else {
                    // Ved forkert svar: vis en Luk-knap så brugeren kan komme tilbage til samme spørgsmål
                    Button(action: {
                        // Luk overlay og behold samme spørgsmål
                        showSuccess = false
                        showSuccessButton = false
                        // lastAnswerCorrect forbliver false
                    }) {
                        Text("Luk")
                            .font(.headline.bold())
                            .padding(.vertical, 10)
                            .padding(.horizontal, 32)
                            .background(Color.white)
                            .foregroundColor(.red)
                            .cornerRadius(14)
                            .shadow(radius: 2)
                    }
                }
            }
            .padding()
        }
        // Valgfrit: tillad at tap udenfor også lukker overlay ved forkert svar
        .onTapGesture {
            if !lastAnswerCorrect {
                showSuccess = false
                showSuccessButton = false
            }
        }
    }

}

// MARK: - Preview

struct ClockGameView_Previews: PreviewProvider {
    static var previews: some View {
        ClockGameView(difficulty: .easy, startImmediately: true, onExit: {}, onBackToHub: {})
    }
}

