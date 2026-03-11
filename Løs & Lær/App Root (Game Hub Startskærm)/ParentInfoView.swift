//
//  ParentInfoView.swift
//  Løs & Lær
//
//  Created by Thomas Pedersen on 30/01/2026.
//

import SwiftUI

private struct ScrollIndicatorsVisibilityModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollIndicators(.visible)
        } else {
            content
        }
    }
}

struct ParentInfoView: View {
    @Binding var showParentInfo: Bool

    var body: some View {
        // Vis lodret scroll med indikatorer
        ScrollView(.vertical, showsIndicators: true) {
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🛶 Labyrint ABC")
                            .font(.title3.bold())
                        Text("Træner bogstavgenkendelse, lydlig opmærksomhed og finmotorik.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("🧮 Labyrint 2+3 = ?")
                            .font(.title3.bold())
                        Text("Træner simple regnestykker og talforståelse.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("✏️ Labyrint stav")
                            .font(.title3.bold())
                        Text("Træner ordgenkendelse, stavning og bogstavrækkefølge.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("⏰ Hvad er klokken")
                            .font(.title3.bold())
                        Text("Træner analog tidsforståelse og aflæsning af urskiven.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("🐒 Hvad spiser dyrene")
                            .font(.title3.bold())
                        Text("Træner kategorisering, logik og viden om dyr.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("⭕ Kryds og Bolle")
                            .font(.title3.bold())
                        Text("Træner strategi, mønstergenkendelse og tur‑tagning.")
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🐾 Vendespil Dyr")
                            .font(.title3.bold())
                        Text("Træner korttidshukommelse, visuel diskrimination, ordforråd og tur‑tagning.")
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("🐾 Gæt et dyr")
                            .font(.title3.bold())
                        Text("Lyt til ledetråde og gæt hvilket dyr der gemmer sig. Træner ordforråd, logik og dyrekendskab.")
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("🎲 Spil alle spil")
                            .font(.title3.bold())
                        Text("Lader barnet spille alle i tilfældig rækkefølge. En opgavebog på iPad")
                    }
                }
                .padding(.bottom, 4)

                Spacer()
            }
            .padding(24)
            // Sørg for at ScrollView fylder hele skærmen, så indikatoren vises korrekt
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(
            Color.white.ignoresSafeArea()
        )
        .modifier(ScrollIndicatorsVisibilityModifier())
    }
}

