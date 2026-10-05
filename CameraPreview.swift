//
//  CameraPreview.swift
//  neu
//
//  Created by its on 02.05.25.
//

import Foundation
import UIKit
import AVFoundation

class CameraPreview: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.isUserInteractionEnabled = false
    }
}
