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

    func add(points: Int) {
        guard points != 0 else { return }
        allGameScore += points
    }

    func increment() {
        add(points: 1)
    }
}

