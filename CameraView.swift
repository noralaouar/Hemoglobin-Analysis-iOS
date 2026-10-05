//
//  CameraView.swift
//  neu
//
//  Created by its on 01.05.25.
//
import SwiftUI
import AVFoundation
import UIKit

struct CameraView: UIViewRepresentable {
    // Livebilder
    @Binding var liveImage:    UIImage?
    @Binding var oxyHbImage:   UIImage?
    @Binding var deoxyHbImage: UIImage?

    // Optional: numerische Werte
    @Binding var deltaOxy:   Double
    @Binding var deltaDeoxy: Double

    // ROI (0…1, nil = ganzes Bild) & FPS
    @Binding var roiRect: CGRect?
    @Binding var fps: Double

    var referenceManager: ReferenceManager

    // MARK: - Coordinator
    final class Coordinator {
        let controller = CameraController()
        let preview = PreviewView()

        // Analyse
        let analysisQ = DispatchQueue(label: "analysis.queue", qos: .userInitiated)
        var isAnalyzing = false

        // Letzte gültige Ergebnisse → verschwinden nie
        var lastOxy:   UIImage?
        var lastDeoxy: UIImage?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - UIView
    func makeUIView(context: Context) -> UIView {
        let coord = context.coordinator

        // Frame-Callback
        coord.controller.onFrame = { image in
            // 1) Referenz einmalig aufnehmen (kein Analyse-Lag beim ersten Bild)
            if self.referenceManager.referenceRGB == nil {
                let rect = self.roiRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
                self.referenceManager.updateReference(from: image, roi: rect)
                return
            }

            guard let ref = self.referenceManager.referenceRGB else { return }

            // 2) Analyse nicht stapeln → „Frame-Drift“ vermeiden
            if coord.isAnalyzing { return }
            coord.isAnalyzing = true

            // Snapshot von ROI & Bild
            let rect = self.roiRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)

            // 3) Analyse im Hintergrund
            coord.analysisQ.async {
                let result = OrtsaufgeloesteAnalyse.berechneDeltaCBilder(
                    from: image,
                    roi: rect,
                    referenz: ref
                )

                DispatchQueue.main.async {
                    // Livebild immer mit den Analysebildern zusammen setzen
                    self.liveImage = image

                    if let oxy = result.oxyHbImage, let deoxy = result.deoxyHbImage {
                        self.oxyHbImage = oxy
                        self.deoxyHbImage = deoxy
                        coord.lastOxy = oxy
                        coord.lastDeoxy = deoxy
                    } else {
                        // Keine neuen Ergebnisse → letzte gültige zeigen
                        if let lo = coord.lastOxy { self.oxyHbImage = lo }
                        if let ld = coord.lastDeoxy { self.deoxyHbImage = ld }
                    }
                    coord.isAnalyzing = false
                }
            }
        }

        // FPS
        coord.controller.onFPSUpdate = { value in
            DispatchQueue.main.async { self.fps = value }
        }

        // Session
        coord.controller.configure()
        coord.preview.videoPreviewLayer.session = coord.controller.session
        coord.preview.videoPreviewLayer.videoGravity = .resizeAspectFill
        coord.controller.start()

        return coord.preview
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controller.stop()
    }
}

// Vorschau-Layer (zeigt das echte Kamerabild)
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
