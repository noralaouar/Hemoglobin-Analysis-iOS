import UIKit
import Foundation
import CoreVideo

@MainActor
final class ReferenceManager: ObservableObject {
    @Published var referenceRGB: [Double]? = nil   // sRGB 0..255 (wie bisher)
    @Published var lastUpdated: Date? = nil

    private func srgbToLinear(_ c: Double) -> Double {
        // c in 0..1
        if c <= 0.04045 { return c / 12.92 }
        return pow((c + 0.055) / 1.055, 2.4)
    }

    private func linearToSrgb(_ c: Double) -> Double {
        // c in 0..1
        if c <= 0.0031308 { return 12.92 * c }
        return 1.055 * pow(c, 1.0 / 2.4) - 0.055
    }

    func updateReference(from image: UIImage, roi: CGRect? = nil) {
        guard
            let cgImage = image.cgImage,
            let dataProvider = cgImage.dataProvider,
            let cfData = dataProvider.data,
            let rawData = CFDataGetBytePtr(cfData)
        else { return }

        let w = cgImage.width
        let h = cgImage.height

        let rectNorm = roi ?? CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)

        // Clamp ROI in [0,1]
        let rx = max(0.0, min(1.0, rectNorm.origin.x))
        let ry = max(0.0, min(1.0, rectNorm.origin.y))
        let rw = max(0.0, min(1.0 - rx, rectNorm.size.width))
        let rh = max(0.0, min(1.0 - ry, rectNorm.size.height))

        let startX = max(0, min(w - 1, Int(rx * Double(w))))
        let startY = max(0, min(h - 1, Int(ry * Double(h))))
        let roiW = max(1, min(w - startX, Int(rw * Double(w))))
        let roiH = max(1, min(h - startY, Int(rh * Double(h))))

        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        var count = 0.0

        for y in 0..<roiH {
            let py = startY + y
            let rowBase = py * w * 4
            for x in 0..<roiW {
                let px = startX + x
                let idx = rowBase + px * 4

                // BGRA
                let b_srgb = Double(rawData[idx + 0]) / 255.0
                let g_srgb = Double(rawData[idx + 1]) / 255.0
                let r_srgb = Double(rawData[idx + 2]) / 255.0

                // linear mitteln
                sumR += srgbToLinear(r_srgb)
                sumG += srgbToLinear(g_srgb)
                sumB += srgbToLinear(b_srgb)
                count += 1.0
            }
        }

        guard count > 0 else { return }

        let meanR_lin = sumR / count
        let meanG_lin = sumG / count
        let meanB_lin = sumB / count

        // zurück nach sRGB 0..255 speichern (wie bisher)
        let meanR = linearToSrgb(meanR_lin) * 255.0
        let meanG = linearToSrgb(meanG_lin) * 255.0
        let meanB = linearToSrgb(meanB_lin) * 255.0

        self.referenceRGB = [meanR, meanG, meanB]
        self.lastUpdated = Date()
    }
}
