//
//  ParentInfoView.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 30/01/2026.
//

import SwiftUI
struct ParentInfoView: View {

    @Binding var showParentInfo: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                HStack {
                    Spacer()
                    Button(action: { showParentInfo = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.gray)
                    }
                }

                Text("Information til forældre")
                    .font(.largeTitle.bold())
                    .padding(.bottom, 10)

                Group {
                    Text("🛶 Labyrint ABC")
                        .font(.title3.bold())
                    Text("Træner bogstavgenkendelse, lydlig opmærksomhed og finmotorik.")

                    Text("🧮 Labyrint Matematik")
                        .font(.title3.bold())
                    Text("Træner simple regnestykker og talforståelse.")

                    Text("✏️ Labyrint Stave")
                        .font(.title3.bold())
                    Text("Træner ordgenkendelse, stavning og bogstavrækkefølge.")

                    Text("⏰ Hvad er klokken")
                        .font(.title3.bold())
                    Text("Træner analog tidsforståelse og aflæsning af urskiven.")

                    Text("🐒 Hvad spiser dyrene")
                        .font(.title3.bold())
                    Text("Træner kategorisering, logik og viden om dyr.")

                    Text("⭕ Kryds og Bolle")
                        .font(.title3.bold())
                    Text("Træner strategi, mønstergenkendelse og tur‑tagning.")

                    Text("🎲 Mix spillene")
                        .font(.title3.bold())
                    Text("Lader barnet spille alle spil(pånær kryds og bolle) i tilfældig rækkefølge.")
                }
                .padding(.bottom, 4)

                Spacer()
            }
            .padding(24)
        }
        .background(Color.white.ignoresSafeArea())
    }
}
