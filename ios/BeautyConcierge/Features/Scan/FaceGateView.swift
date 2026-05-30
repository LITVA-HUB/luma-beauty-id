import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UIKit

/// Mandatory onboarding step between registration and the Beauty ID questionnaire.
/// The user cannot continue until a face photo is captured (or chosen). There is no skip.
struct FaceGateView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showingCamera = false
    @State private var selectedItem: PhotosPickerItem?
    @State private var permissionMessage: String?
    @State private var uploadTask: Task<Void, Never>?

    private var isProcessing: Bool {
        appState.isBusy || !appState.scanStatuses.isEmpty
    }

    var body: some View {
        ZStack {
            PremiumBackground()
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: BeautySpacing.lg) {
                        hero(height: heroHeight(for: proxy.size.height))
                        intro
                        if let permissionMessage {
                            BeautyGateNotice(message: permissionMessage)
                        }
                        if isProcessing {
                            BeautyGateProgressCard(statuses: appState.scanStatuses)
                        }
                        actions
                        privacyNote
                    }
                    .padding(BeautySpacing.md)
                    .padding(.bottom, BeautySpacing.xl)
                    .frame(minHeight: proxy.size.height - proxy.safeAreaInsets.top, alignment: .top)
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    permissionMessage = nil
                    Haptics.tap()
                    runScan(with: data, source: "onboarding_library")
                }
            }
        }
        .onDisappear { uploadTask?.cancel() }
        .fullScreenCover(isPresented: $showingCamera) {
            BeautyScanCameraView(onImage: { image in
                showingCamera = false
                if let data = image.jpegDataForUpload() {
                    runScan(with: data, source: "onboarding_camera")
                }
            }, allowSkip: false, onCancel: {
                showingCamera = false
            })
        }
    }

    // MARK: Layout

    private func heroHeight(for available: CGFloat) -> CGFloat {
        min(max(available * 0.26, 180), 280)
    }

    private func hero(height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous)
                .fill(BeautyColor.card)
            Ellipse()
                .stroke(BeautyColor.lime, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: height * 0.42, height: height * 0.56)
            Image(systemName: "face.smiling")
                .font(BeautyFont.sized(height * 0.2, .light))
                .foregroundStyle(BeautyColor.taupe)
            Circle()
                .fill(BeautyColor.lime.opacity(0.22))
                .frame(width: 150, height: 150)
                .blur(radius: 40)
                .offset(x: 90, y: -height * 0.32)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
        .beautyShadow()
        .accessibilityHidden(true)
    }

    private var intro: some View {
        VStack(spacing: BeautySpacing.sm) {
            Text("Добавьте фото для профиля")
                .font(BeautyFont.title)
                .foregroundStyle(BeautyColor.ink)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
            Text("Один снимок лица помогает точнее подобрать текстуры, тон и финиш. Это нужно один раз перед анкетой и не является диагностикой.")
                .font(BeautyFont.body)
                .foregroundStyle(BeautyColor.taupe)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: BeautySpacing.sm) {
            PrimaryButton(title: "Сделать фото", systemImage: "camera.fill", isLoading: isProcessing, action: requestCamera)

            PhotosPicker(selection: $selectedItem, matching: .images) {
                Label("Выбрать из галереи", systemImage: "photo.on.rectangle")
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BeautyColor.milk, in: Capsule())
                    .overlay(Capsule().stroke(BeautyColor.line.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            #if DEBUG
            Button(action: useDevelopmentSamplePhoto) {
                Label("Пример фото", systemImage: "person.crop.circle.badge.checkmark")
                    .font(BeautyFont.caption.weight(.semibold))
                    .foregroundStyle(BeautyColor.taupe)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Использовать пример фото")
            #endif
        }
    }

    private var privacyNote: some View {
        Label("Фото используется только для косметического подбора. Экспорт и удаление — в настройках.", systemImage: "lock")
            .font(BeautyFont.caption)
            .foregroundStyle(BeautyColor.taupe)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    private func runScan(with data: Data, source: String) {
        uploadTask?.cancel()
        uploadTask = Task {
            await appState.performScan(imageData: data, source: source)
            uploadTask = nil
        }
    }

    private func requestCamera() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showingCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        showingCamera = true
                    } else {
                        permissionMessage = "Доступ к камере отклонён. Включите камеру в настройках или выберите фото из галереи."
                    }
                }
            }
        case .denied, .restricted:
            permissionMessage = "Камера выключена для Золотого Яблока. Откройте «Настройки» и включите камеру — или выберите фото из галереи."
        @unknown default:
            permissionMessage = "Камера сейчас недоступна. Выберите фото из галереи."
        }
    }

    #if DEBUG
    private func useDevelopmentSamplePhoto() {
        let data: Data?
        if let named = UIImage(named: "scan_test_photo") {
            data = named.jpegDataForUpload()
        } else {
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
            let image = renderer.image { context in
                let cg = context.cgContext
                UIColor(red: 0.98, green: 0.94, blue: 0.90, alpha: 1).setFill()
                cg.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
                UIColor(red: 0.87, green: 0.65, blue: 0.52, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 315, y: 225, width: 270, height: 380))
                UIColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1).setFill()
                cg.fillEllipse(in: CGRect(x: 382, y: 390, width: 24, height: 24))
                cg.fillEllipse(in: CGRect(x: 495, y: 390, width: 24, height: 24))
            }
            data = image.jpegDataForUpload()
        }
        if let data {
            runScan(with: data, source: "onboarding_sample")
        }
    }
    #endif
}

private struct BeautyGateNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(BeautyFont.callout)
            .foregroundStyle(BeautyColor.ink)
            .padding(BeautySpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BeautyColor.blush.opacity(0.28), in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(0.35), lineWidth: 1))
    }
}

private struct BeautyGateProgressCard: View {
    let statuses: [ScanStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            HStack(spacing: BeautySpacing.sm) {
                ProgressView()
                    .tint(BeautyColor.lime)
                Text("Готовлю профиль")
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
            }
            ForEach(statuses.suffix(3)) { status in
                Label(status.label, systemImage: status.isDone ? "checkmark.circle.fill" : "circle")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .beautyCard()
    }
}
