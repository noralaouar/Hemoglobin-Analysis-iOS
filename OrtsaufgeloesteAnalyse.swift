//
//  OrtsaufgeloesteAnalyse.swift
//  neu
//
//  Created by its on 10.05.25.
//
import UIKit
import Accelerate
import CoreGraphics


/// Lokaler Helper: baut ein False-Color-UIImage aus Float-Werten.
/// - Nutzt automatisch: Daten-Min/Max + optionale manuelle Grenzen aus FarbskalenManager.
/// - Verwendet deine Colormap-Implementierung (Colormap.rgb255).
private func makeFalseColorImage(
    values: [Float],
    width: Int,
    height: Int,
    colormap: ColormapType
) -> UIImage? {
    guard values.count == width * height, width > 0, height > 0 else { return nil }

    // Daten-Grenzen bestimmen
    let dataMin = values.min() ?? 0
    let dataMax = values.max() ?? 1

    // RGBA-Puffer
    var rgba = [UInt8](repeating: 255, count: width * height * 4)

    // Normalisierung mit evtl. manuellen Grenzen
    let fs = FarbskalenManager.shared

    for i in 0..<values.count {
        // 0…1
        let v01 = fs.normalize(value: values[i], dataMin: dataMin, dataMax: dataMax)
        // RGB (UInt8) gemäß aktueller Colormap
        let (r, g, b) = Colormap.rgb255(forNormalized: CGFloat(v01), using: colormap)

        let p = i * 4
        rgba[p + 0] = r
        rgba[p + 1] = g
        rgba[p + 2] = b
        rgba[p + 3] = 255
    }

    // UIImage erzeugen (RGBA8, premultipliedLast)
    guard
        let cfData   = CFDataCreate(nil, rgba, rgba.count),
        let provider = CGDataProvider(data: cfData),
        let cgImage  = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    else { return nil }

    return UIImage(cgImage: cgImage)
}


struct OrtsaufgeloesteAnalyse {
    static func berechneDeltaCBilder(from image: UIImage,
                                     roi: CGRect,
                                     referenz: [Double]) -> (oxyHbImage: UIImage?, deoxyHbImage: UIImage?) {

        guard let cgImage = image.cgImage else { return (nil, nil) }

        let w = cgImage.width
        let h = cgImage.height
        let bytesPerRow = w * 4
        var rawData = [UInt8](repeating: 0, count: Int(h * bytesPerRow))
        guard let colorSpace = cgImage.colorSpace,
              let context = CGContext(data: &rawData,
                                      width: w,
                                      height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return (nil, nil) }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // --- ROI definieren (ganzer Frame falls nil) ---
        let startX = Int(max(0, roi.minX * CGFloat(w)))
        let startY = Int(max(0, roi.minY * CGFloat(h)))
        let roiW   = Int(min(CGFloat(w) - CGFloat(startX), roi.width  * CGFloat(w)))
        let roiH   = Int(min(CGFloat(h) - CGFloat(startY), roi.height * CGFloat(h)))

        if roiW <= 0 || roiH <= 0 { return (nil, nil) }

        // --- Pseudoinverse Extinktionsmatrix (nach Prahl/Steimers) ---
        let Eplus: [[Double]] = [
            [-12.8348, 11.0774,  36.6384],   // oxyHb
            [ 18.1081, -6.2544, -35.9121]    // deoxyHb
        ]

        // --- Arrays vorbereiten ---
        var oxy = [Float](repeating: 0, count: roiW * roiH)
        var deoxy = [Float](repeating: 0, count: roiW * roiH)
        let eps = 1e-6

        // --- Pixelweise Analyse ---
        for y in 0..<roiH {
            for x in 0..<roiW {
                let i = (y + startY) * w + (x + startX)
                let idx = i * 4
                let b = Double(rawData[idx + 0]) / 255.0
                let g = Double(rawData[idx + 1]) / 255.0
                let r = Double(rawData[idx + 2]) / 255.0

                // linearisieren (sRGB → linear)
                let rl = srgbToLinear(r)
                let gl = srgbToLinear(g)
                let bl = srgbToLinear(b)

                // logarithmierte Attenuation
                let aR = log10(max(referenz[0], eps) / max(rl, eps))
                let aG = log10(max(referenz[1], eps) / max(gl, eps))
                let aB = log(max(referenz[2], eps) / max(bl, eps))

                // ΔC = E⁺ * ΔA
                let dOxy   = Eplus[0][0] * aR + Eplus[0][1] * aG + Eplus[0][2] * aB
                let dDeoxy = Eplus[1][0] * aR + Eplus[1][1] * aG + Eplus[1][2] * aB

                oxy[y * roiW + x]   = Float(dOxy)
                deoxy[y * roiW + x] = Float(dDeoxy)
            }
        }

        // --- Farbskalen-Grenzen ---
        var minV = CGFloat(FarbskalenManager.shared.minValue ?? -15.0)
        var maxV = CGFloat(FarbskalenManager.shared.maxValue ??  15.0)
        if !(maxV > minV) { minV = -15.0; maxV = 15.0 }

        // --- Falschfarbendarstellung (neue zentrale Funktion) ---
        let fs = FarbskalenManager.shared

        let oxyImg = makeFalseColorImage(
            values: oxy,
            width: roiW,
            height: roiH,
            colormap: fs.oxyColormap
        )

        let deoxyImg = makeFalseColorImage(
            values: deoxy,
            width: roiW,
            height: roiH,
            colormap: fs.deoxyColormap
        )

        return (oxyImg, deoxyImg)
    }

    // MARK: - Hilfsfunktionen

    private static func srgbToLinear(_ v: Double) -> Double {
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
