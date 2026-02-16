// AudioVoiceManager.swift
import Foundation
import AVFoundation

final class AudioVoiceManager: NSObject {
    static let shared = AudioVoiceManager()
    private override init() {
        super.init()
        // Sørg for playback kategori
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // Debug flag
    var debugLogging: Bool = true

    // MARK: - Backwards compatible single-file helper (robust)
    // Bevarer reference til aktive spillere så de ikke frigives midt i afspilning.
    private var activePlayers: [AVAudioPlayer] = []
    private var playerCompletions: [Int: () -> Void] = [:]

    func speakWithFallback(aiFile: String?, fallback: @escaping () -> Void) {
        guard let aiFile = aiFile, !aiFile.isEmpty,
              let url = Bundle.main.url(forResource: aiFile, withExtension: "mp3") else {
            if debugLogging { print("[AudioVoiceManager] speakWithFallback: missing file -> fallback") }
            fallback()
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            retainAndPlay(player: player, completion: nil)
        } catch {
            if debugLogging { print("[AudioVoiceManager] speakWithFallback: failed to create player -> fallback: \(error)") }
            fallback()
        }
    }

    // MARK: - Per-segment sequence API (robust, retains controller)
    // aiFiles og segmentFallbackTexts skal have samme længde
    func speakSequencePerSegment(aiFiles: [String?], segmentFallbackTexts: [String?], completion: (() -> Void)? = nil) {
        guard aiFiles.count == segmentFallbackTexts.count else {
            if debugLogging { print("[AudioVoiceManager] ERROR: aiFiles.count != segmentFallbackTexts.count") }
            completion?()
            return
        }
        let controller = SequenceController(aiFiles: aiFiles, segmentTexts: segmentFallbackTexts, debug: debugLogging, completion: completion)
        activeControllers.append(controller)
        controller.start { [weak self, weak controller] in
            if let c = controller, let idx = self?.activeControllers.firstIndex(where: { $0 === c }) {
                self?.activeControllers.remove(at: idx)
            }
        }
    }

    // Retain aktive controllers så de ikke deallokeres midt i afspilning
    private var activeControllers: [SequenceController] = []

    // MARK: - Intern helper: retain & play for speakWithFallback
    private func retainAndPlay(player: AVAudioPlayer, completion: (() -> Void)?) {
        activePlayers.append(player)
        if let cb = completion {
            playerCompletions[player.hashValue] = {
                cb()
                if let idx = self.activePlayers.firstIndex(of: player) {
                    self.activePlayers.remove(at: idx)
                }
                self.playerCompletions[player.hashValue] = nil
            }
        } else {
            playerCompletions[player.hashValue] = {
                if let idx = self.activePlayers.firstIndex(of: player) {
                    self.activePlayers.remove(at: idx)
                }
                self.playerCompletions[player.hashValue] = nil
            }
        }
        player.prepareToPlay()
        player.play()
    }

    // MARK: - SequenceController (intern)
    private class SequenceController: NSObject, AVAudioPlayerDelegate {
        private let aiFiles: [String?]
        private let segmentTexts: [String?]
        private let debug: Bool
        private var index = 0
        private var player: AVAudioPlayer?
        private var completion: (() -> Void)?
        private var finishedCallback: (() -> Void)?

        init(aiFiles: [String?], segmentTexts: [String?], debug: Bool, completion: (() -> Void)?) {
            self.aiFiles = aiFiles
            self.segmentTexts = segmentTexts
            self.debug = debug
            self.completion = completion
            super.init()
        }

        func start(finished: @escaping () -> Void) {
            self.finishedCallback = finished
            playNext()
        }

        private func playNext() {
            if index >= aiFiles.count {
                completion?()
                finishedCallback?()
                return
            }

            let currentName = aiFiles[index]
            let currentText = segmentTexts[index]
            index += 1

            if let name = currentName, !name.isEmpty, let url = Bundle.main.url(forResource: name, withExtension: "mp3") {
                do {
                    player = try AVAudioPlayer(contentsOf: url)
                    player?.delegate = self
                    player?.prepareToPlay()
                    if debug { print("[AudioVoiceManager] playing file: \(url.lastPathComponent) (segment \(index))") }
                    player?.play()
                } catch {
                    if debug { print("[AudioVoiceManager] failed to play \(name).mp3 — using TTS for segment: \(error)") }
                    runTTSThenContinue(text: currentText)
                }
            } else {
                if debug { print("[AudioVoiceManager] missing file: \(currentName ?? "nil") — using TTS for segment") }
                runTTSThenContinue(text: currentText)
            }
        }

        private func runTTSThenContinue(text: String?) {
            guard let text = text, !text.isEmpty else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.playNext() }
                return
            }
            if debug { print("[AudioVoiceManager] TTS segment: \"\(text)\"") }
            let tts = SpeechManager()
            tts.speak(text) { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.playNext() }
            }
        }

        // AVAudioPlayerDelegate
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            self.player = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.playNext() }
        }
    }
}

// MARK: - AVAudioPlayerDelegate for speakWithFallback players
extension AudioVoiceManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let cb = playerCompletions[player.hashValue] {
            cb()
        } else {
            if let idx = activePlayers.firstIndex(of: player) {
                activePlayers.remove(at: idx)
            }
        }
    }
}
