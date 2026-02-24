//  HomeView.swift

import SwiftUI

struct HomeView: View {
    
    @Binding var selectedGame: GameSelection
    @Binding var difficulty: Difficulty
    let onNotReady: (GameSelection) -> Void

    @State private var showParentInfo = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {

        VStack(spacing: 20) {

            Spacer().frame(height: 40)

            Text("Vælg et spil")
                .font(.largeTitle.bold())
                .foregroundColor(.black)

            LazyVGrid(columns: columns, spacing: 16) {

                IconTileButton(iconName: "icon_labyrinth_abc") {
                    selectedGame = .labyrinthLetters
                }

                IconTileButton(iconName: "icon_labyrinth_math") {
                    selectedGame = .labyrinthMath
                }

                IconTileButton(iconName: "icon_labyrinth_word") {
                    selectedGame = .labyrinthWords
                }

                IconTileButton(iconName: "icon_clock") {
                    selectedGame = .clock
                }

                IconTileButton(iconName: "icon_animals") {
                    selectedGame = .animals
                }

                IconTileButton(iconName: "icon_tictactoe") {
                    selectedGame = .ticTacToe
                }

                IconTileButton(iconName: "icon_MemoryMatchView_animal") {
                    selectedGame = .memoryMatch
                }

                // ⭐ Mix alle spil – nu perfekt centreret
                IconTileButton(iconName: "icon_all_games") {
                    if enabledGames.count > 1 {
                        selectedGame = .allGames
                    } else {
                        onNotReady(.allGames)
                    }
                }
                
                IconTileButton(iconName: "icon_guess_animal") {
                    selectedGame = .guessAnimal
                }

                
            }
            .padding(.horizontal, 20)

            DifficultyPicker(difficulty: $difficulty)
                .padding(.top, 10)

            Spacer()
        }

        // INFO-KNAP – ligger i overlay, så den ikke påvirker layoutet
        .overlay(alignment: .topTrailing) {
            Button(action: { showParentInfo = true }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.gray)
                    .padding()
            }
            .offset(x: -20, y: 20)   // ← Ryk ned og ind
        }

        .fullScreenCover(isPresented: $showParentInfo) {
            ParentInfoView(showParentInfo: $showParentInfo)
        }
    }
}

struct IconTileButton: View {
    let iconName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .padding(8)
        }
    }
}

struct DifficultyPicker: View {
    @Binding var difficulty: Difficulty

    var body: some View {
        VStack(spacing: 8) {
            Text("Sværhedsgrad")
                .font(.headline)
                .foregroundColor(.black)

            Picker("Sværhedsgrad", selection: $difficulty) {
                Text("Let").tag(Difficulty.easy)
                Text("Svær").tag(Difficulty.hard)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }
}
