//
//  Falschfarbendarstellung.swift
//  neu
//
//  Created by its on 01.05.25.
//

import Foundation
import UIKit
import CoreImage

func processFrame(image: UIImage) -> (UIImage?, UIImage?) {
    guard let ciImage = CIImage(image: image) else { return (nil, nil) }
    let context = CIContext()
    var oxyUIImage: UIImage? = nil
    var deoxyUIImage: UIImage? = nil

    // oxyHb: Rot betonen & Hot-Colormap anwenden
    if let oxyFilter = CIFilter(name: "CIColorMatrix") {
        oxyFilter.setValue(ciImage, forKey: kCIInputImageKey)
        oxyFilter.setValue(CIVector(x: 2.0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        oxyFilter.setValue(CIVector(x: 0, y: 0.5, z: 0, w: 0), forKey: "inputGVector")
        oxyFilter.setValue(CIVector(x: 0, y: 0, z: 0.5, w: 0), forKey: "inputBVector")
        oxyFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        if let oxyCIImage = oxyFilter.outputImage,
           let hotOxyCIImage = applyHotColormap(to: oxyCIImage),
           let oxyCGImage = context.createCGImage(hotOxyCIImage, from: hotOxyCIImage.extent) {
            oxyUIImage = UIImage(cgImage: oxyCGImage)
        }
    }

    // deoxyHb: Blau betonen & Blue-Colormap anwenden
    if let deoxyFilter = CIFilter(name: "CIColorMatrix") {
        deoxyFilter.setValue(ciImage, forKey: kCIInputImageKey)
        deoxyFilter.setValue(CIVector(x: 0.5, y: 0, z: 0, w: 0), forKey: "inputRVector")
        deoxyFilter.setValue(CIVector(x: 0, y: 0.5, z: 0, w: 0), forKey: "inputGVector")
        deoxyFilter.setValue(CIVector(x: 0, y: 0, z: 2.0, w: 0), forKey: "inputBVector")
        deoxyFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        if let deoxyCIImage = deoxyFilter.outputImage,
           let hotDeoxyCIImage = applyhotColormap(to: deoxyCIImage),
           let deoxyCGImage = context.createCGImage(hotDeoxyCIImage, from: hotDeoxyCIImage.extent) {
            deoxyUIImage = UIImage(cgImage: deoxyCGImage)
        }
    }

    return (oxyUIImage, deoxyUIImage)
}

func applyHotColormap(to ciImage: CIImage) -> CIImage? {
    let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    guard let colormap = hotColormapCIImage() else { return nil }
    let colorMapFilter = CIFilter(name: "CIColorMap")
    colorMapFilter?.setValue(grayscale, forKey: kCIInputImageKey)
    colorMapFilter?.setValue(colormap, forKey: "inputGradientImage")
    return colorMapFilter?.outputImage
}

func applyhotColormap(to ciImage: CIImage) -> CIImage? {
    let grayscale = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    guard let colormap = hotColormapCIImage() else { return nil }
    let colorMapFilter = CIFilter(name: "CIColorMap")
    colorMapFilter?.setValue(grayscale, forKey: kCIInputImageKey)
    colorMapFilter?.setValue(colormap, forKey: "inputGradientImage")
    return colorMapFilter?.outputImage
}

func hotColormapCIImage() -> CIImage? {
    return colormapImage(using: { t in
        switch t {
        case 0.0..<0.33:
            return (t / 0.33, 0, 0)
        case 0.33..<0.66:
            return (1, (t - 0.33) / 0.33, 0)
        default:
            return (1, 1, (t - 0.66) / 0.34)
        }
    })
}

func blueColormapCIImage() -> CIImage? {
    return colormapImage(using: { t in
        if t < 0.5 {
            let factor = t / 0.5
            return (0, 0, factor)
        } else {
            let factor = (t - 0.5) / 0.5
            return (factor, factor, 1)
        }
    })
}

private func colormapImage(using colorFunction: (Double) -> (Double, Double, Double)) -> CIImage? {
    let width = 256, height = 1
    var pixelData = [UInt8](repeating: 0, count: width * 4)

    for x in 0..<width {
        let t = Double(x) / Double(width - 1)
        let (r, g, b) = colorFunction(t)
        let idx = x * 4

        pixelData[idx + 0] = UInt8(max(0, min(255, Int(r * 255))))
        pixelData[idx + 1] = UInt8(max(0, min(255, Int(g * 255))))
        pixelData[idx + 2] = UInt8(max(0, min(255, Int(b * 255))))
        pixelData[idx + 3] = 255
    }

    guard let cfData = CFDataCreate(nil, pixelData, pixelData.count),
          let provider = CGDataProvider(data: cfData),
          let cgImage = CGImage(
              width: width,
              height: height,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: true,
              intent: .defaultIntent
          ) else {
        return nil
    }

    return CIImage(cgImage: cgImage)
}


struct Falschfarbendarstellung {

    static func makeImage(
        vals: [Float],
        width: Int,
        height: Int,
        colormap: ColormapType
    ) -> UIImage? {
        guard vals.count == width * height, width > 0, height > 0 else { return nil }

        let dataMin = vals.min() ?? 0
        let dataMax = vals.max() ?? 1

        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        let fs = FarbskalenManager.shared

        for i in 0..<vals.count {
            let v01 = fs.normalize(value: vals[i], dataMin: dataMin, dataMax: dataMax)
            let (r, g, b) = Colormap.rgb255(forNormalized: CGFloat(v01), using: colormap)

            let p = i * 4
            rgba[p + 0] = r
            rgba[p + 1] = g
            rgba[p + 2] = b
            rgba[p + 3] = 255
        }

        guard
            let cfData = CFDataCreate(nil, rgba, rgba.count),
            let provider = CGDataProvider(data: cfData),
            let cgImage = CGImage(
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
}
