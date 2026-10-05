//
//  PixelweiseAnalyse.swift
//  neu
//
//  Created by its on 10.05.25.

import UIKit

struct PixelweiseAnalyse {
    /// Berechnet globale Δ-Werte (ΔOxy, ΔDeoxy) aus Bild und RGB-Referenz.
    /// - from: UIImage (z.B. aktuelles Live-Frame)
    /// - roi: normierter ROI (x,y,width,height in 0..1), wie in OrtsaufgeloesteAnalyse
    /// - referenz: [R_lin, G_lin, B_lin] (linearisiert, 0..1) aus ReferenceManager
    static func berechneDeltaC(
        from image: UIImage,
        roi: CGRect?,
        referenz: [Double]
    ) -> (deltaOxy: Double, deltaDeoxy: Double) {
        // Grundchecks
        guard
            let cgImage = image.cgImage,
            let data    = cgImage.dataProvider?.data,
            let ptr     = CFDataGetBytePtr(data),
            referenz.count == 3
        else {
            return (0, 0)
        }

        let w = cgImage.width
        let h = cgImage.height

        // ROI: wie in OrtsaufgeloesteAnalyse → normierte Koordinaten (0..1)
        let roiRect = roi ?? CGRect(x: 0, y: 0, width: 1, height: 1)

        let startX = Int(max(0, roiRect.minX * CGFloat(w)))
        let startY = Int(max(0, roiRect.minY * CGFloat(h)))
        let roiW   = Int(min(CGFloat(w) - CGFloat(startX), roiRect.width  * CGFloat(w)))
        let roiH   = Int(min(CGFloat(h) - CGFloat(startY), roiRect.height * CGFloat(h)))

        if roiW <= 0 || roiH <= 0 { return (0, 0) }

        // Pseudoinverse Extinktionsmatrix (wie in OrtsaufgeloesteAnalyse)
        let Eplus: [[Double]] = [
            [-12.8348, 11.0774,  36.6384],   // oxyHb
            [ 18.1081, -6.2544, -35.9121]    // deoxyHb
        ]

        var sumOxy:   Double = 0
        var sumDeoxy: Double = 0
        var count:    Double = 0
        let eps = 1e-6

        // Pixelweise Analyse → pro Pixel ΔOxy/ΔDeoxy, dann Mittelwert
        for y in 0..<roiH {
            for x in 0..<roiW {
                let px = x + startX
                let py = y + startY
                let idx = (py * w + px) * 4

                let b_srgb = Double(ptr[idx + 0]) / 255.0
                let g_srgb = Double(ptr[idx + 1]) / 255.0
                let r_srgb = Double(ptr[idx + 2]) / 255.0

                // sRGB → linear
                let rl = srgbToLinear(r_srgb)
                let gl = srgbToLinear(g_srgb)
                let bl = srgbToLinear(b_srgb)

                // Nur auswerten, wenn Werte > 0
                if rl <= 0 || gl <= 0 || bl <= 0 { continue }

                // Attenuation relativ zur Referenz (linear!)
                let aR = log10(max(referenz[0], eps) / max(rl, eps))
                let aG = log10(max(referenz[1], eps) / max(gl, eps))
                let aB = log10(max(referenz[2], eps) / max(bl, eps))

                // ΔC = E⁺ * ΔA
                let dOxy   = Eplus[0][0] * aR + Eplus[0][1] * aG + Eplus[0][2] * aB
                let dDeoxy = Eplus[1][0] * aR + Eplus[1][1] * aG + Eplus[1][2] * aB

                sumOxy   += dOxy
                sumDeoxy += dDeoxy
                count    += 1.0
            }
        }

        guard count > 0 else { return (0, 0) }

        let meanOxy   = sumOxy / count
        let meanDeoxy = sumDeoxy / count

        return (meanOxy, meanDeoxy)
    }

    // MARK: - Hilfsfunktionen

    /// gleiche Funktion wie in OrtsaufgeloesteAnalyse & ReferenceManager
    private static func srgbToLinear(_ v: Double) -> Double {
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}

