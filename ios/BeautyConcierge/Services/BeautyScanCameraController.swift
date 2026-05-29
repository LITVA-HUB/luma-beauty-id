import AVFoundation
import ImageIO
import SwiftUI
import UIKit
import Vision

final class BeautyScanCameraController: NSObject, ObservableObject {
    @Published private(set) var faceState: BeautyScanFaceState = .searching
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var isCapturing = false
    @Published private(set) var isCameraReady = false
    @Published var cameraError: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "luma.beautyScan.session")
    private let videoQueue = DispatchQueue(label: "luma.beautyScan.vision")
    private let frameStateQueue = DispatchQueue(label: "luma.beautyScan.frameState")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var photoDelegate: PhotoCaptureDelegate?
    private var isConfigured = false
    private var isProcessingFrame = false
    private var smoothedFaceRect: CGRect?
    private var lastUsableFaceState: BeautyScanFaceState?
    private var lastFaceDetectionTime: CFTimeInterval?

    private enum ScanTuning {
        static let overlayHoldDuration: CFTimeInterval = 0.9
        static let recentFaceCaptureGrace: CFTimeInterval = 1.6
        static let smoothingAlpha: CGFloat = 0.28
        static let jumpSmoothingAlpha: CGFloat = 0.18
        static let minimumUsableFaceWidth: CGFloat = 0.16
        static let maximumUsableFaceWidth: CGFloat = 0.82
        static let minimumVisibleRatio: CGFloat = 0.62
    }

    func start() {
        sessionQueue.async {
            self.configureIfNeeded()
            guard self.isConfigured else { return }
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoQueue)
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.videoOutput.setSampleBufferDelegate(nil, queue: nil)
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func resetCapture() {
        DispatchQueue.main.async {
            self.capturedImage = nil
            self.isCapturing = false
            self.faceState = .searching
            self.smoothedFaceRect = nil
            self.lastUsableFaceState = nil
            self.lastFaceDetectionTime = nil
        }
    }

    func capturePhoto() {
        sessionQueue.async {
            guard self.isConfigured, !self.isCapturing else { return }
            DispatchQueue.main.async { self.isCapturing = true }

            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }

            if let connection = self.photoOutput.connection(with: .video) {
                self.configurePortrait(connection)
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            let delegate = PhotoCaptureDelegate { [weak self] image in
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.capturedImage = image
                    if image == nil {
                        self?.cameraError = "Не удалось сохранить фото. Попробуйте ещё раз."
                    } else {
                        Haptics.success()
                    }
                    self?.photoDelegate = nil
                }
            }
            self.photoDelegate = delegate
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard
            let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            publishError("Камера сейчас недоступна. Можно продолжить без фото.")
            return
        }
        session.addInput(input)

        guard session.canAddOutput(photoOutput), session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            publishError("Не удалось подготовить камеру. Можно выбрать фото из галереи.")
            return
        }

        session.addOutput(photoOutput)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            configurePortrait(connection)
        }

        session.commitConfiguration()
        isConfigured = true
        DispatchQueue.main.async {
            self.isCameraReady = true
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async {
            self.cameraError = message
            self.isCameraReady = false
        }
    }

    private func configurePortrait(_ connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func publishFaceState(_ state: BeautyScanFaceState) {
        DispatchQueue.main.async {
            self.faceState = state
        }
    }

    private func beginProcessingFrame() -> Bool {
        frameStateQueue.sync {
            guard !isProcessingFrame else { return false }
            isProcessingFrame = true
            return true
        }
    }

    private func endProcessingFrame() {
        frameStateQueue.sync {
            isProcessingFrame = false
        }
    }

    private func makeFaceState(from observation: VNFaceObservation) -> BeautyScanFaceState {
        let box = observation.boundingBox
        let rawRect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let rect = smoothFaceRect(rawRect)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let yaw = CGFloat(observation.yaw?.doubleValue ?? 0)
        let roll = CGFloat(observation.roll?.doubleValue ?? 0)

        let horizontalOffset = center.x - 0.5
        let verticalOffset = center.y - 0.52
        let size = rect.width
        let poseOffset = max(abs(yaw), abs(roll))
        let visibleRatio = rawRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)).areaRatio(relativeTo: rawRect)

        if size < ScanTuning.minimumUsableFaceWidth || size > ScanTuning.maximumUsableFaceWidth || visibleRatio < ScanTuning.minimumVisibleRatio {
            return BeautyScanFaceState(
                faceRect: rect,
                confidence: observation.confidence,
                guidance: "Расположите лицо в овале",
                detail: "Когда лицо будет в овале, можно сделать фото.",
                level: .searching,
                quality: 0.18
            )
        }

        var guidance = "Лицо почти в кадре"
        var detail = "Можно зафиксировать, подсказка только помогает улучшить снимок."
        var level: BeautyScanFaceState.GuidanceLevel = .adjust

        if size < 0.23 {
            guidance = "Можно зафиксировать, но лучше чуть ближе"
            detail = "Так текстуры будут видны точнее."
        } else if size > 0.72 {
            guidance = "Можно зафиксировать, но лучше чуть дальше"
            detail = "Оставьте немного воздуха вокруг лица."
        } else if abs(horizontalOffset) > 0.22 || abs(verticalOffset) > 0.24 {
            guidance = "Лицо почти в кадре"
            detail = "Можно снять сейчас или мягко выровнять кадр."
        } else if abs(yaw) > 0.46 || abs(roll) > 0.42 {
            guidance = "Можно зафиксировать, ракурс почти подходит"
            detail = "Если удобно, повернитесь немного к камере."
        } else if observation.confidence < 0.55 {
            guidance = "Держите лицо в кадре"
            detail = "Трекинг чуть нестабилен, но фото можно сделать."
        } else {
            guidance = "Отлично, можно фиксировать"
            detail = "Контекст подходит для косметического подбора."
            level = .aligned
        }

        let centerScore = max(0, 1 - (abs(horizontalOffset) + abs(verticalOffset)) * 2.8)
        let sizeScore = max(0, 1 - abs(size - 0.44) * 2.4)
        let poseScore = max(0, 1 - poseOffset * 2.4)
        let quality = min(1, max(0, (centerScore * 0.42) + (sizeScore * 0.34) + (poseScore * 0.24)))

        return BeautyScanFaceState(
            faceRect: rect,
            confidence: observation.confidence,
            guidance: guidance,
            detail: detail,
            level: level,
            quality: level == .aligned ? max(quality, 0.86) : quality
        )
    }

    private func smoothFaceRect(_ rect: CGRect) -> CGRect {
        guard let previous = smoothedFaceRect else {
            smoothedFaceRect = rect
            return rect
        }

        let centerDelta = hypot(previous.midX - rect.midX, previous.midY - rect.midY)
        let sizeDelta = abs(previous.width - rect.width) + abs(previous.height - rect.height)
        let alpha = centerDelta + sizeDelta > 0.28 ? ScanTuning.jumpSmoothingAlpha : ScanTuning.smoothingAlpha
        let smoothed = previous.lerp(to: rect, alpha: alpha)
        smoothedFaceRect = smoothed
        return smoothed
    }

    private func handleFaceDetected(_ observation: VNFaceObservation) {
        let state = makeFaceState(from: observation)
        if state.level != .searching {
            lastUsableFaceState = state
            lastFaceDetectionTime = CACurrentMediaTime()
        }
        publishFaceState(state)
    }

    private func handleFaceMissing() {
        let now = CACurrentMediaTime()
        guard
            let lastFaceDetectionTime,
            let lastUsableFaceState,
            now - lastFaceDetectionTime <= ScanTuning.recentFaceCaptureGrace
        else {
            smoothedFaceRect = nil
            publishFaceState(.searching)
            return
        }

        let shouldHoldOverlay = now - lastFaceDetectionTime <= ScanTuning.overlayHoldDuration
        publishFaceState(
            BeautyScanFaceState(
                faceRect: shouldHoldOverlay ? lastUsableFaceState.faceRect : nil,
                confidence: max(0.1, lastUsableFaceState.confidence * 0.5),
                guidance: "Держите лицо в кадре",
                detail: "Можно зафиксировать, если лицо видно на снимке.",
                level: .adjust,
                quality: max(0.42, lastUsableFaceState.quality * 0.72),
                isRecentlyLost: true
            )
        )
    }
}

extension BeautyScanCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard beginProcessingFrame() else { return }

        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            defer { self?.endProcessingFrame() }
            guard
                let observations = request.results as? [VNFaceObservation],
                let face = observations.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height })
            else {
                self?.handleFaceMissing()
                return
            }
            self?.handleFaceDetected(face)
        }

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .leftMirrored, options: [:])
        do {
            try handler.perform([request])
        } catch {
            endProcessingFrame()
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        completion(image)
    }
}

private extension CGRect {
    func lerp(to rect: CGRect, alpha: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (rect.origin.x - origin.x) * alpha,
            y: origin.y + (rect.origin.y - origin.y) * alpha,
            width: width + (rect.width - width) * alpha,
            height: height + (rect.height - height) * alpha
        )
    }

    func areaRatio(relativeTo rect: CGRect) -> CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        let baseArea = max(rect.width * rect.height, 0.0001)
        return max(0, width * height) / baseArea
    }
}

struct BeautyCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        configurePreviewConnection(view.videoPreviewLayer.connection)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
        configurePreviewConnection(uiView.videoPreviewLayer.connection)
    }

    private func configurePreviewConnection(_ connection: AVCaptureConnection?) {
        guard let connection else { return }
        if #available(iOS 17.0, *) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}
