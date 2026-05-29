import SwiftUI
import CoreGraphics

struct BeautyScanFaceState: Equatable {
    enum GuidanceLevel: Equatable {
        case searching
        case adjust
        case aligned
    }

    let faceRect: CGRect?
    let confidence: Float
    let guidance: String
    let detail: String
    let level: GuidanceLevel
    let quality: CGFloat
    let isRecentlyLost: Bool

    init(
        faceRect: CGRect?,
        confidence: Float,
        guidance: String,
        detail: String,
        level: GuidanceLevel,
        quality: CGFloat,
        isRecentlyLost: Bool = false
    ) {
        self.faceRect = faceRect
        self.confidence = confidence
        self.guidance = guidance
        self.detail = detail
        self.level = level
        self.quality = quality
        self.isRecentlyLost = isRecentlyLost
    }

    var isAligned: Bool { level == .aligned }

    static let searching = BeautyScanFaceState(
        faceRect: nil,
        confidence: 0,
        guidance: "Расположите лицо в овале",
        detail: "Мягкий свет, взгляд прямо. Это косметический контекст, не диагностика.",
        level: .searching,
        quality: 0
    )
}

enum BeautyScanCameraStage: Equatable {
    case searching
    case guiding
    case aligned
    case capturing
    case captured
}

@MainActor
final class BeautyScanViewModel: ObservableObject {
    @Published private(set) var stage: BeautyScanCameraStage = .searching
    @Published private(set) var guidanceTitle = BeautyScanFaceState.searching.guidance
    @Published private(set) var guidanceDetail = BeautyScanFaceState.searching.detail
    @Published private(set) var quality: CGFloat = 0

    var canCapture: Bool { stage == .guiding || stage == .aligned }

    func update(faceState: BeautyScanFaceState) {
        guard stage != .capturing, stage != .captured else { return }
        guidanceTitle = faceState.guidance
        guidanceDetail = faceState.detail
        quality = faceState.quality

        switch faceState.level {
        case .searching:
            stage = .searching
        case .adjust:
            stage = .guiding
        case .aligned:
            stage = .aligned
        }
    }

    func startCapture() {
        stage = .capturing
        guidanceTitle = "Фиксирую контекст"
        guidanceDetail = "Сохраняю фото для косметического подбора. Без медицинских выводов."
    }

    func didCapture() {
        stage = .captured
        guidanceTitle = "Контекст зафиксирован"
        guidanceDetail = "Проверьте снимок и используйте его для подбора."
        // Keep the last measured face quality instead of reporting a perfect score.
    }

    func reset() {
        stage = .searching
        guidanceTitle = BeautyScanFaceState.searching.guidance
        guidanceDetail = BeautyScanFaceState.searching.detail
        quality = 0
    }
}
