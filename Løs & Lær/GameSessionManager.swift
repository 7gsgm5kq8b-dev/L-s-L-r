//
//  GameSessionManager.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 15/02/2026.
//
import SwiftUI
import AVFoundation
import Combine

class GameSessionManager: ObservableObject {
    @Published var allGameScore: Int = 0

    func resetAllGameScore() {
        allGameScore = 0
    }

    func increment() {
        allGameScore += 1
    }
}

