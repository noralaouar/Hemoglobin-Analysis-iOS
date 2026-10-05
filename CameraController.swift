import AVFoundation
import UIKit

final class CameraController: NSObject, ObservableObject {

    // Callbacks
    var onFrame: ((UIImage) -> Void)?
    var onFPSUpdate: ((Double) -> Void)?
    var onRawBuffer: ((CVPixelBuffer) -> Void)?

    // Session
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()

    // Queues
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let captureQueue = DispatchQueue(label: "video.capture.queue", qos: .userInitiated)

    // Device/Input speichern (WICHTIG für Torch!)
    private var videoDevice: AVCaptureDevice?
    private var videoDeviceInput: AVCaptureDeviceInput?

    // FPS
    private var lastFrameTime: CFAbsoluteTime = 0

    private let ciContext = CIContext(options: nil)

    // Track whether we already added observers (avoid duplicates)
    private var didAddObservers = false

    // MARK: - Configure (nur einmal sauber)
    func configure() {
        sessionQueue.async {
            // schon konfiguriert?
            if self.videoDeviceInput != nil { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .high

            let device =
                AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video)

            guard let camera = device else {
                self.session.commitConfiguration()
                return
            }

            do {
                let input = try AVCaptureDeviceInput(device: camera)

                guard self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    return
                }

                self.session.addInput(input)
                self.videoDevice = camera
                self.videoDeviceInput = input

            } catch {
                print("Camera input error:", error)
                self.session.commitConfiguration()
                return
            }

            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

            guard self.session.canAddOutput(self.videoOutput) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addOutput(self.videoOutput)

            if let conn = self.videoOutput.connection(with: .video),
               conn.isVideoOrientationSupported  {
                conn.videoOrientation = .portrait
            }

            self.session.commitConfiguration()
            self.addRuntimeObserversIfNeeded()
        }
    }

    /// Configure + start in one serialized `sessionQueue` block.
    /// This avoids starting the session before inputs/outputs are attached.
    func configureAndStart() {
        sessionQueue.async {
            if self.videoDeviceInput == nil {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high

                let device =
                    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                    ?? AVCaptureDevice.default(for: .video)

                guard let camera = device else {
                    self.session.commitConfiguration()
                    return
                }

                do {
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        return
                    }
                    self.session.addInput(input)
                    self.videoDevice = camera
                    self.videoDeviceInput = input
                } catch {
                    print("Camera input error:", error)
                    self.session.commitConfiguration()
                    return
                }

                self.videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                self.videoOutput.alwaysDiscardsLateVideoFrames = true
                self.videoOutput.setSampleBufferDelegate(self, queue: self.captureQueue)

                guard self.session.canAddOutput(self.videoOutput) else {
                    self.session.commitConfiguration()
                    return
                }
                self.session.addOutput(self.videoOutput)

                if let conn = self.videoOutput.connection(with: .video),
                   conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }

                self.session.commitConfiguration()
                self.addRuntimeObserversIfNeeded()
            }

            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    // MARK: - Start/Stop
    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func ensureRunning() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    // MARK: - Torch
    func setTorch(on: Bool) {
        sessionQueue.async {
            guard let device = self.videoDevice, device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                if on {
                    try device.setTorchModeOn(level: 1.0)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                print("Torch error:", error)
            }
        }
    }

    // MARK: - Runtime observers
    private func addRuntimeObserversIfNeeded() {
        guard !didAddObservers else { return }
        didAddObservers = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRuntimeError(_:)),
            name: .AVCaptureSessionRuntimeError,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruptionEnded(_:)),
            name: .AVCaptureSessionInterruptionEnded,
            object: session
        )
    }

    @objc private func handleRuntimeError(_ note: Notification) {
        if let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError {
            print("AVCapture runtime error:", err)
        }
        ensureRunning()
    }

    @objc private func handleInterruptionEnded(_ note: Notification) {
        ensureRunning()
    }
}

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {

        // Orientation is set once in `configure()` / `configureAndStart()`.

        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // FPS
        let now = CFAbsoluteTimeGetCurrent()
        if lastFrameTime != 0 {
            let dt = now - lastFrameTime
            if dt > 0 {
                let fps = 1.0 / dt
                DispatchQueue.main.async { [weak self] in self?.onFPSUpdate?(fps) }
            }
        }
        lastFrameTime = now

        // Raw buffer -> VM (always deliver on Main; VM typically publishes @Published)
        DispatchQueue.main.async { [weak self] in
            self?.onRawBuffer?(pb)
        }

        // Preview
        let ciImage = CIImage(cvPixelBuffer: pb)
        if let cg = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            let ui = UIImage(cgImage: cg)
            DispatchQueue.main.async { [weak self] in self?.onFrame?(ui) }
        }
    }
}



