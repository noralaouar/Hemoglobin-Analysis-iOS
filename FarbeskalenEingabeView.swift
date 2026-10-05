//
//  FarbeskalenEingabeView.swift
//  neu
//
//  Created by its on 20.06.25.
//
import SwiftUI

struct FarbskalenEingabeView: View {
    @ObservedObject private var scale = FarbskalenManager.shared

    @State private var minText: String = ""
    @State private var maxText: String = ""
    @State private var status: String = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Wertebereich (leer = Auto)")) {
                    HStack {
                        Text("Min")
                        TextField("leer = Auto", text: $minText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }
                    HStack {
                        Text("Max")
                        TextField("leer = Auto", text: $maxText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }

                    if let a = parsed(minText), let b = parsed(maxText), a >= b {
                        Text("⚠️ Min muss kleiner als Max sein.")
                            .foregroundColor(.red)
                            .font(.footnote)
                    }

                    Button("Auf Auto zurücksetzen") {
                        scale.resetToAuto()
                        minText = ""
                        maxText = ""
                        status = "Auf Auto gesetzt"
                    }
                    .foregroundColor(.orange)
                }

                Section(header: Text("Colormap Auswahl")) {
                    Picker("oxyHb", selection: $scale.oxyColormap) {
                        ForEach(ColormapType.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    Picker("deoxyHb", selection: $scale.deoxyColormap) {
                        ForEach(ColormapType.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Farbskala & Colormap")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { applyAndClose() }
                        .disabled(invalidRange())
                }
            }
            .onAppear(perform: loadInitial)
        }
    }

    private func loadInitial() {
        minText = scale.minValue.map { String($0) } ?? "-"
        maxText = scale.maxValue.map { String($0) } ?? ""
        status = ""
    }

    private func invalidRange() -> Bool {
        if let a = parsed(minText), let b = parsed(maxText) { return a >= b }
        return false
    }

    private func applyAndClose() {
        // Leer => Auto
        if minText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scale.minValue = nil
        } else if let v = parsed(minText) {
            scale.minValue = v
        } else { status = "Ungültiger Min-Wert"; return }

        if maxText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scale.maxValue = nil
        } else if let v = parsed(maxText) {
            scale.maxValue = v
        } else { status = "Ungültiger Max-Wert"; return }

        if invalidRange() { status = "Min < Max erforderlich"; return }

        status = "Farbskala aktualisiert"
        dismiss()
    }

    /// akzeptiert „1,23“ und „1.23“
    private func parsed(_ s: String) -> Float? {
        guard !s.isEmpty else { return nil }
        return Float(s.replacingOccurrences(of: ",", with: "."))
    }
}
