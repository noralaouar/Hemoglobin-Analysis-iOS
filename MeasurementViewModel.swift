import SwiftUI
import AVFoundation
import simd

@MainActor
final class MeasurementViewModel: ObservableObject {

    // MARK: - Published UI state
    @Published var deltaOxy: Double = 0
    @Published var deltaDeoxy: Double = 0
    @Published var fps: Double = 0
    @Published var liveImage: UIImage?
    @Published var oxyHbImage: UIImage?
    @Published var deoxyHbImage: UIImage?
    /// ROI (0…1) in normalized preview coordinates
    @Published var roiRect: CGRect = CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)

    // MARK: - Reference
    let referenceManager = ReferenceManager()

    // MARK: - Pseudoinverse vectors (your values)
    private let Eplus_oxy   = SIMD3<Double>(-12.8348,  11.0774,  36.6384)
    private let Eplus_deoxy = SIMD3<Double>( 18.1081,  -6.2544, -35.9121)

    // MARK: - Throttling
    private var lastUI: CFAbsoluteTime = 0
    private var lastHeat: CFAbsoluteTime = 0
    private let uiHz: Double = 10.0     // delta + UI
    private let heatHz: Double = 2.0    // heatmaps

    // MARK: - Baseline-Nullung (t=0 -> Δ = 0)
    private var baselineOxy: Double? = nil
    private var baselineDeoxy: Double? = nil
    private var baselineRefStamp: Date? = nil

    // Cache for recolor
    private var lastOxyVals: [Float]?
    private var lastDeoxyVals: [Float]?
    private var lastW: Int = 0
    private var lastH: Int = 0

    // Background analysis queue
    private let analysisQueue = DispatchQueue(label: "analysis.queue", qos: .userInitiated)

    private lazy var engine = AnalysisEngine(
        EplusOxy: Eplus_oxy,
        EplusDeoxy: Eplus_deoxy,
        scale: 0.05
    )

    // MARK: - Camera hook
    func attachCamera(_ camera: CameraController) {
        camera.onFrame = { [weak self] img in
            guard let self else { return }
            Task { @MainActor in
                self.liveImage = img
            }
        }
        camera.onFPSUpdate = { [weak self] v in
            guard let self else { return }
            Task { @MainActor in
                self.fps = v
            }
        }

        // IMPORTANT: CameraController delivers this on Main.
        camera.onRawBuffer = { [weak self] pb in
            guard let self else { return }
            Task { @MainActor in
                self.handleRawBuffer(pb)
            }
        }
    }

    private func handleRawBuffer(_ pb: CVPixelBuffer) {
        let now = CFAbsoluteTimeGetCurrent()

        let roi = clampedROI(roiRect)
        let currentRef = referenceManager.referenceRGB

        let needsRef = (currentRef == nil)
        let doDelta = needsRef || (now - lastUI >= (1.0 / uiHz))
        let doHeat  = needsRef || (now - lastHeat >= (1.0 / heatHz))

        if !doDelta && !doHeat {
            return
        }

        // Advance throttles at schedule time (so we don't spam work)
        if doDelta { lastUI = now }
        if doHeat  { lastHeat = now }

        // Snapshot colormap settings (avoid reading ObservableObject from BG thread)
        let scaleMgr = FarbskalenManager.shared
        let manualMin = scaleMgr.minValue
        let manualMax = scaleMgr.maxValue
        let oxyMap = scaleMgr.oxyColormap
        let deoxyMap = scaleMgr.deoxyColormap

        let targetW = 180
        let engine = self.engine  // <-- nur EINMAL!

        analysisQueue.async { [engine] in
            let out = engine.process(
                pb: pb,
                roiNorm: roi,
                currentRefRGB: currentRef,
                doDelta: doDelta,
                doHeat: doHeat,
                targetWidth: targetW,
                manualMin: manualMin,
                manualMax: manualMax,
                oxyMap: oxyMap,
                deoxyMap: deoxyMap
            )

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }

                // 1) Neue Referenz übernehmen + Baseline resetten
                if let newRef = out.newReferenceRGB {
                    self.referenceManager.referenceRGB = newRef
                    let stamp = Date()
                    self.referenceManager.lastUpdated = stamp

                    // Baseline reset bei neuer Referenz
                    self.baselineRefStamp = stamp
                    self.baselineOxy = nil
                    self.baselineDeoxy = nil
                } else {
                    // Falls Referenz irgendwo anders geändert wurde:
                    let currentStamp = self.referenceManager.lastUpdated
                    if self.baselineRefStamp != currentStamp {
                        self.baselineRefStamp = currentStamp
                        self.baselineOxy = nil
                        self.baselineDeoxy = nil
                    }
                }

                // 2) Deltas anzeigen (baseline-nulliert)
                if let (dO, dD) = out.deltas {
                    // Baseline beim ersten gültigen Wert nach Referenz setzen
                    if self.baselineOxy == nil {
                        self.baselineOxy = dO
                        self.baselineDeoxy = dD
                    }

                    self.deltaOxy = dO - (self.baselineOxy ?? 0)
                    self.deltaDeoxy = dD - (self.baselineDeoxy ?? 0)
                }

                // 3) Heatmaps
                if let heat = out.heat {
                    self.lastOxyVals = heat.oxyVals
                    self.lastDeoxyVals = heat.deoxyVals
                    self.lastW = heat.width
                    self.lastH = heat.height
                    self.oxyHbImage = heat.oxyImage
                    self.deoxyHbImage = heat.deoxyImage
                }
            }
        }
    }

    // MARK: - Recolor when Min/Max / Colormap changed
    func rebuildColormapsIfNeeded() {
        guard let o = lastOxyVals, let d = lastDeoxyVals, lastW > 0, lastH > 0 else { return }

        let scaleMgr = FarbskalenManager.shared
        let manualMin = scaleMgr.minValue
        let manualMax = scaleMgr.maxValue

        oxyHbImage = engine.renderFalseColor(
            vals: o,
            width: lastW,
            height: lastH,
            manualMin: manualMin,
            manualMax: manualMax,
            map: scaleMgr.oxyColormap
        )

        deoxyHbImage = engine.renderFalseColor(
            vals: d,
            width: lastW,
            height: lastH,
            manualMin: manualMin,
            manualMax: manualMax,
            map: scaleMgr.deoxyColormap
        )
    }

    // MARK: - ROI clamp (normalized)
    private func clampedROI(_ r: CGRect) -> CGRect {
        let x = max(0, min(1, r.origin.x))
        let y = max(0, min(1, r.origin.y))
        let w = max(0.01, min(1 - x, r.size.width))
        let h = max(0.01, min(1 - y, r.size.height))
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Background analysis engine (no MainActor)
fileprivate struct AnalysisEngine {

    struct Output {
        var newReferenceRGB: [Double]?
        var deltas: (Double, Double)?
        var heat: HeatOutput?
    }

    struct HeatOutput {
        let oxyVals: [Float]
        let deoxyVals: [Float]
        let width: Int
        let height: Int
        let oxyImage: UIImage?
        let deoxyImage: UIImage?
    }

    private let Eoxy: SIMD3<Double>
    private let Edeoxy: SIMD3<Double>

    init(EplusOxy: SIMD3<Double>, EplusDeoxy: SIMD3<Double>, scale: Double) {
        self.Eoxy = EplusOxy * scale
        self.Edeoxy = EplusDeoxy * scale
    }

    func process(
        pb: CVPixelBuffer,
        roiNorm: CGRect,
        currentRefRGB: [Double]?,
        doDelta: Bool,
        doHeat: Bool,
        targetWidth: Int,
        manualMin: Float?,
        manualMax: Float?,
        oxyMap: ColormapType,
        deoxyMap: ColormapType
    ) -> Output {

        var out = Output()

        // Reference
        var refRGB = currentRefRGB
        if refRGB == nil {
            if let ref = computeReferenceRGB(from: pb, roiNorm: roiNorm) {
                refRGB = [ref.0, ref.1, ref.2]
                out.newReferenceRGB = refRGB
            } else {
                return out
            }
        }
        guard let refRGB, refRGB.count >= 3 else { return out }
        let refV = SIMD3<Double>(refRGB[0], refRGB[1], refRGB[2])

        // Deltas (ROI mean)
        if doDelta {
            let (dO, dD) = computeDeltasROI(from: pb, roiNorm: roiNorm, refRGB255: refV)
            out.deltas = (dO, dD)
        }

        // Heatmaps (downsample + render)
        if doHeat {
            let (oxyVals, deoxyVals, w2, h2) = computeHeatmapsDownsampled(
                from: pb,
                refRGB255: refV,
                targetWidth: targetWidth
            )

            let oxyImg = renderFalseColor(vals: oxyVals, width: w2, height: h2, manualMin: manualMin, manualMax: manualMax, map: oxyMap)
            let deoxyImg = renderFalseColor(vals: deoxyVals, width: w2, height: h2, manualMin: manualMin, manualMax: manualMax, map: deoxyMap)

            out.heat = HeatOutput(
                oxyVals: oxyVals,
                deoxyVals: deoxyVals,
                width: w2,
                height: h2,
                oxyImage: oxyImg,
                deoxyImage: deoxyImg
            )
        }

        return out
    }

    // MARK: - Reference (ROI mean)
    /// Computes a reference from ROI. Internally averages in *linear* space, then converts back to sRGB 0..255.
    private func computeReferenceRGB(from pb: CVPixelBuffer, roiNorm: CGRect) -> (Double, Double, Double)? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)

        let x0 = max(0, min(w - 1, Int(Double(w) * roiNorm.minX)))
        let y0 = max(0, min(h - 1, Int(Double(h) * roiNorm.minY)))
        let x1 = max(1, min(w, Int(Double(w) * roiNorm.maxX)))
        let y1 = max(1, min(h, Int(Double(h) * roiNorm.maxY)))
        if x1 <= x0 || y1 <= y0 { return nil }

        var sumLin = SIMD3<Double>(repeating: 0)
        var c = 0.0

        for y in y0..<y1 {
            let row = base.advanced(by: y * stride)
            for x in x0..<x1 {
                let p = row.advanced(by: x * 4) // BGRA
                let b = Double(p.load(fromByteOffset: 0, as: UInt8.self)) / 255.0
                let g = Double(p.load(fromByteOffset: 1, as: UInt8.self)) / 255.0
                let r = Double(p.load(fromByteOffset: 2, as: UInt8.self)) / 255.0

                let lin = srgbToLinear(SIMD3(r, g, b))
                sumLin += lin
                c += 1
            }
        }
        guard c > 0 else { return nil }

        let meanLin = sumLin / c
        let meanSrgb = linearToSrgb(meanLin)

        let meanR = meanSrgb.x * 255.0
        let meanG = meanSrgb.y * 255.0
        let meanB = meanSrgb.z * 255.0

        // too dark? -> don't set reference
        let luma = 0.2126 * meanR + 0.7152 * meanG + 0.0722 * meanB
        guard luma >= 5 else { return nil }

        return (meanR, meanG, meanB)
    }

    // MARK: - ROI deltas (mean over ROI)
    private func computeDeltasROI(from pb: CVPixelBuffer, roiNorm: CGRect, refRGB255: SIMD3<Double>) -> (Double, Double) {

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return (0, 0) }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)

        let x0 = max(0, min(w - 1, Int(Double(w) * roiNorm.minX)))
        let y0 = max(0, min(h - 1, Int(Double(h) * roiNorm.minY)))
        let x1 = max(1, min(w, Int(Double(w) * roiNorm.maxX)))
        let y1 = max(1, min(h, Int(Double(h) * roiNorm.maxY)))
        if x1 <= x0 || y1 <= y0 { return (0, 0) }

        let I0lin = srgbToLinear(refRGB255 / 255.0)

        var sumO = 0.0
        var sumD = 0.0
        var c = 0.0

        let invLn10 = 1.0 / log(10.0)

        for y in y0..<y1 {
            let row = base.advanced(by: y * stride)
            for x in x0..<x1 {
                let p = row.advanced(by: x * 4) // BGRA
                let b = Double(p.load(fromByteOffset: 0, as: UInt8.self))
                let g = Double(p.load(fromByteOffset: 1, as: UInt8.self))
                let r = Double(p.load(fromByteOffset: 2, as: UInt8.self))

                let Ilin = srgbToLinear(SIMD3(r, g, b) / 255.0)
                let A = (simd.log(clampLow(I0lin)) - simd.log(clampLow(Ilin))) * invLn10

                sumO += simd_dot(Eoxy, A)
                sumD += simd_dot(Edeoxy, A)
                c += 1
            }
        }

        guard c > 0 else { return (0, 0) }
        return (sumO / c, sumD / c)
    }

    // MARK: - Downsample heatmaps for speed
    private func computeHeatmapsDownsampled(from pb: CVPixelBuffer, refRGB255: SIMD3<Double>, targetWidth: Int) -> ([Float], [Float], Int, Int) {

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else {
            return ([], [], 0, 0)
        }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let stride = CVPixelBufferGetBytesPerRow(pb)

        let step = max(1, w / max(1, targetWidth))
        let w2 = max(1, w / step)
        let h2 = max(1, h / step)

        var oxy = [Float](repeating: 0, count: w2 * h2)
        var deoxy = [Float](repeating: 0, count: w2 * h2)

        let I0lin = srgbToLinear(refRGB255 / 255.0)
        let invLn10 = 1.0 / log(10.0)

        var yy2 = 0
        var y = 0
        while y < h {
            let row = base.advanced(by: y * stride)
            var xx2 = 0
            var x = 0
            while x < w {
                let p = row.advanced(by: x * 4) // BGRA
                let b = Double(p.load(fromByteOffset: 0, as: UInt8.self))
                let g = Double(p.load(fromByteOffset: 1, as: UInt8.self))
                let r = Double(p.load(fromByteOffset: 2, as: UInt8.self))

                let Ilin = srgbToLinear(SIMD3(r, g, b) / 255.0)
                let A = (simd.log(clampLow(I0lin)) - simd.log(clampLow(Ilin))) * invLn10

                oxy[yy2 * w2 + xx2] = Float(simd_dot(Eoxy, A))
                deoxy[yy2 * w2 + xx2] = Float(simd_dot(Edeoxy, A))

                xx2 += 1
                x += step
            }
            yy2 += 1
            y += step
        }

        return (oxy, deoxy, w2, h2)
    }

    // MARK: - Render
    func renderFalseColor(vals: [Float], width: Int, height: Int, manualMin: Float?, manualMax: Float?, map: ColormapType) -> UIImage? {
        guard vals.count == width * height, width > 0, height > 0 else { return nil }

        var dataMin = Double.greatestFiniteMagnitude
        var dataMax = -Double.greatestFiniteMagnitude
        for v in vals {
            let d = Double(v)
            if d < dataMin { dataMin = d }
            if d > dataMax { dataMax = d }
        }

        let pad = 0.05
        let span = max(1e-12, dataMax - dataMin)
        var aMin = dataMin - pad * span
        var aMax = dataMax + pad * span

        if let uMin = manualMin, let uMax = manualMax, uMax > uMin {
            aMin = Double(uMin)
            aMax = Double(uMax)
        }
        let range = max(1e-12, aMax - aMin)

        let outBytes = width * height * 4
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: outBytes)

        for i in 0..<vals.count {
            let t = clamp01((Double(vals[i]) - aMin) / range)
            let (r, g, b) = colorFromColormap(t, map: map)
            let p = i * 4
            buf[p + 0] = b
            buf[p + 1] = g
            buf[p + 2] = r
            buf[p + 3] = 255
        }

        return makeImageFromBGRA(bytes: buf, width: width, height: height)
    }

    private func colorFromColormap(_ t: Double, map: ColormapType) -> (UInt8, UInt8, UInt8) {
        switch map {
        case .hot:
            return hotColormap(t)
        case .blue:
            return blueColormap(t)
        }
    }
}

// MARK: - Helpers
fileprivate func srgbToLinear(_ v: SIMD3<Double>) -> SIMD3<Double> {
    @inline(__always) func f(_ x: Double) -> Double {
        let x = max(0.0, min(1.0, x))
        return x <= 0.04045 ? (x / 12.92) : pow((x + 0.055) / 1.055, 2.4)
    }
    return SIMD3(f(v.x), f(v.y), f(v.z))
}

fileprivate func linearToSrgb(_ v: SIMD3<Double>) -> SIMD3<Double> {
    @inline(__always) func f(_ x: Double) -> Double {
        let x = max(0.0, min(1.0, x))
        return x <= 0.0031308 ? (x * 12.92) : (1.055 * pow(x, 1.0 / 2.4) - 0.055)
    }
    return SIMD3(f(v.x), f(v.y), f(v.z))
}

fileprivate func clampLow(_ v: SIMD3<Double>, eps: Double = 1e-6) -> SIMD3<Double> {
    SIMD3(max(v.x, eps), max(v.y, eps), max(v.z, eps))
}

@inline(__always) fileprivate func clamp01(_ v: Double) -> Double {
    v < 0 ? 0 : (v > 1 ? 1 : v)
}

fileprivate func hotColormap(_ t: Double) -> (UInt8, UInt8, UInt8) {
    let t = clamp01(t)
    var r = 0.0, g = 0.0, b = 0.0
    if t < 0.4 {
        r = t / 0.4
    } else if t < 0.75 {
        r = 1
        g = (t - 0.4) / 0.35
    } else {
        r = 1
        g = 1
        b = (t - 0.75) / 0.25
    }
    return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
}

fileprivate func blueColormap(_ t: Double) -> (UInt8, UInt8, UInt8) {
    let t = clamp01(t)
    var r = 0.0, g = 0.0, b = 0.0
    if t < 0.45 {
        b = t / 0.45 * 0.5
    } else if t < 0.8 {
        g = (t - 0.45) / 0.35
        b = 0.5 + (t - 0.45) / 0.35 * 0.5
    } else {
        r = (t - 0.8) / 0.2
        g = 1
        b = 1
    }
    return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
}

fileprivate func makeImageFromBGRA(bytes: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> UIImage? {
    let bytesPerRow = width * 4
    let dataSize = bytesPerRow * height

    let provider = CGDataProvider(dataInfo: nil, data: bytes, size: dataSize) { _, data, _ in
        data.deallocate()
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
        CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
    )

    guard let provider,
          let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
          ) else {
        bytes.deallocate()
        return nil
    }

    return UIImage(cgImage: cg)
}
