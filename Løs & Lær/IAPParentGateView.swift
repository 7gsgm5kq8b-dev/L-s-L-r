import SwiftUI

// Comment IAP 03-04-2026
struct IAPParentGateView: View {
    @Environment(\.dismiss) private var dismiss

    let onSuccess: () -> Void

    @State private var firstNumber = Int.random(in: 10...99)
    @State private var secondNumber = Int.random(in: 10...99)
    @State private var answerText = ""
    @State private var errorText = ""

    private var expectedAnswer: Int {
        firstNumber + secondNumber
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Forældre-adgang")
                    .font(.title2.bold())

                Text("Løs regnestykket for at fortsætte")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Hvad er \(firstNumber) + \(secondNumber)?")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                TextField("Svar", text: $answerText)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.red)
                }

                HStack(spacing: 12) {
                    Button("Ny opgave") {
                        regenerateTask()
                    }
                    .buttonStyle(.bordered)

                    Button("Fortsæt") {
                        validateAnswer()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Luk") { dismiss() }
                }
            }
        }
    }

    private func regenerateTask() {
        firstNumber = Int.random(in: 10...99)
        secondNumber = Int.random(in: 10...99)
        answerText = ""
        errorText = ""
    }

    private func validateAnswer() {
        guard let answer = Int(answerText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorText = "Skriv et tal."
            return
        }

        if answer == expectedAnswer {
            errorText = ""
            dismiss()
            onSuccess()
        } else {
            errorText = "Forkert svar. Prøv igen."
        }
    }
}
