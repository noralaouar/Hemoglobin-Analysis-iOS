//
//  FarbskalenManager.swift
//  neu
//
//  Created by its on 20.06.25.
//


import Foundation

/// Zentraler Manager für Min/Max und Colormap-Auswahl
final class FarbskalenManager: ObservableObject {
    static let shared = FarbskalenManager()

    // Manuelle Grenzwerte; nil ⇒ automatische Daten-Min/Max benutzen
    @Published var minValue: Float? { didSet { saveMinMax() } }
    @Published var maxValue: Float? { didSet { saveMinMax() } }

    // Colormap je Kanal
    @Published var oxyColormap: ColormapType { didSet { saveMaps() } }
    @Published var deoxyColormap: ColormapType { didSet { saveMaps() } }

    private init() {
        // Min/Max laden
        if let n = UserDefaults.standard.object(forKey: "Farbskalen.min") as? NSNumber {
            minValue = n.floatValue
        } else { minValue = nil }

        if let n = UserDefaults.standard.object(forKey: "Farbskalen.max") as? NSNumber {
            maxValue = n.floatValue
        } else { maxValue = nil }

        // Colormaps laden (mit Defaults)
        if let raw = UserDefaults.standard.string(forKey: "Farbskalen.oxyMap"),
           let m = ColormapType(rawValue: raw) {
            oxyColormap = m
        } else { oxyColormap = .hot }

        if let raw = UserDefaults.standard.string(forKey: "Farbskalen.deoxyMap"),
           let m = ColormapType(rawValue: raw) {
            deoxyColormap = m
        } else { deoxyColormap = .blue }
    }

    private func saveMinMax() {
        if let v = minValue {
            UserDefaults.standard.set(NSNumber(value: v), forKey: "Farbskalen.min")
        } else {
            UserDefaults.standard.removeObject(forKey: "Farbskalen.min")
        }
        if let v = maxValue {
            UserDefaults.standard.set(NSNumber(value: v), forKey: "Farbskalen.max")
        } else {
            UserDefaults.standard.removeObject(forKey: "Farbskalen.max")
        }
    }

    private func saveMaps() {
        UserDefaults.standard.set(oxyColormap.rawValue,   forKey: "Farbskalen.oxyMap")
        UserDefaults.standard.set(deoxyColormap.rawValue, forKey: "Farbskalen.deoxyMap")
    }

    // Auf Auto zurücksetzen (nimmt wieder Daten-Min/Max)
    func resetToAuto() {
        minValue = nil
        maxValue  = nil
    }

    /// Normiert einen Wert mit manuellen oder Daten-Grenzen auf 0…1 (geclamped)
    func normalize(value: Float, dataMin: Float, dataMax: Float) -> Float {
        let lo = minValue ?? dataMin
        let hi = maxValue ?? dataMax
        let low  = Swift.min(lo, hi)
        let high = Swift.max(lo, hi)
        let span = max(high - low, 1e-12)
        let v = (value - low) / span
        if v.isNaN || !v.isFinite { return 0 }
        return max(0, min(1, v))
    }
}
