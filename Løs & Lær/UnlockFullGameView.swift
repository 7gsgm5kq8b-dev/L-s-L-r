import SwiftUI

// Comment IAP 03-04-2026
struct UnlockFullGameView: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var trialManager: TrialManager

    @State private var showParentGate = false
    @State private var isProcessingPurchase = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.98, green: 0.93, blue: 0.84), Color(red: 0.82, green: 0.94, blue: 0.92)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Lås hele spillet op")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Du har spillet gratisversionen. Lås hele spillet op for 19 kr.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.black.opacity(0.72))
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("✔ Alle spil uden begrænsning")
                    Text("✔ Ingen reklamer")
                }
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Button(action: {
                    showParentGate = true
                }) {
                    Text(isProcessingPurchase ? "Behandler køb..." : "🔓 Lås op – 19 kr")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isProcessingPurchase)

                Button("Gendan køb") {
                    Task { await restorePurchases() }
                }
                .buttonStyle(.bordered)
                .disabled(isProcessingPurchase)

                if let error = trialManager.lastStoreError, !error.isEmpty {
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Ikke nu") {
                    isPresented = false
                }
                .padding(.top, 4)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 14, y: 6)
            .padding(20)
        }
        .task {
            await trialManager.refreshStoreState()
        }
        .sheet(isPresented: $showParentGate) {
            IAPParentGateView {
                Task { await purchaseUnlock() }
            }
        }
    }

    private func purchaseUnlock() async {
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        let didUnlock = await trialManager.purchaseFullGame()
        if didUnlock {
            isPresented = false
        }
    }

    private func restorePurchases() async {
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        let restored = await trialManager.restorePurchases()
        if restored {
            isPresented = false
        }
    }
}
