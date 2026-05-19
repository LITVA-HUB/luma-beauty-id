import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UIKit

struct PhotoScanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    @State private var selectedSource = "questionnaire"
    @State private var showingCamera = false
    @State private var showingPrivacySheet = false
    @State private var consentAccepted = false
    @State private var permissionMessage: String?
    @State private var uploadTask: Task<Void, Never>?

    private var hasSelectedPhoto: Bool { selectedImageData != nil }

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    BeautyScanEntryHero()
                    BeautyScanConsentCard(consentAccepted: $consentAccepted, onPrivacy: { showingPrivacySheet = true })

                    if let permissionMessage {
                        BeautyScanNotice(message: permissionMessage)
                    }

                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        BeautyScanPreviewCard(image: uiImage) {
                            self.selectedImageData = nil
                            self.selectedSource = "questionnaire"
                        }
                    }

                    if appState.isBusy || !appState.scanStatuses.isEmpty {
                        BeautyScanProgressCard(statuses: appState.scanStatuses, canCancel: uploadTask != nil && appState.isBusy) {
                            uploadTask?.cancel()
                            uploadTask = nil
                        }
                    }

                    if let result = appState.scanResult {
                        BeautyScanResultCard(result: result)
                    }

                    BeautyScanActionPanel(
                        selectedItem: $selectedItem,
                        consentAccepted: consentAccepted,
                        hasSelectedPhoto: hasSelectedPhoto,
                        isBusy: appState.isBusy,
                        onCamera: requestCamera,
                        onSample: useDevelopmentSamplePhoto,
                        onContinue: runScan
                    )
                }
                .padding(BeautySpacing.md)
                .padding(.bottom, BeautySpacing.xl)
            }
        }
        .navigationTitle("Beauty Scan")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { uploadTask?.cancel() }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .limited {
                    permissionMessage = "Доступ к фото ограничен. Luma использует только выбранный снимок."
                }
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    selectedSource = "library"
                    permissionMessage = nil
                    Haptics.tap()
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            BeautyScanCameraView { image in
                selectedImageData = image.jpegDataForUpload()
                selectedSource = "camera"
                showingCamera = false
                permissionMessage = nil
            } onSkip: {
                showingCamera = false
                selectedImageData = nil
                selectedSource = "questionnaire"
                runScan()
            } onCancel: {
                showingCamera = false
            }
        }
        .sheet(isPresented: $showingPrivacySheet) {
            BeautyScanPrivacySheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func runScan() {
        let data = selectedImageData
        guard data == nil || consentAccepted else {
            permissionMessage = "Включите согласие для фото или продолжите без снимка."
            Haptics.warning()
            return
        }
        uploadTask = Task {
            await appState.performScan(imageData: data, source: data == nil ? "questionnaire" : selectedSource)
            uploadTask = nil
        }
    }

    private func requestCamera() {
        guard consentAccepted else {
            permissionMessage = "Для камеры нужно согласие. Без фото можно продолжить сразу."
            Haptics.warning()
            return
        }

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
                        permissionMessage = "Доступ к камере отклонён. Можно выбрать фото из галереи или продолжить без него."
                    }
                }
            }
        case .denied, .restricted:
            permissionMessage = "Камера выключена для Luma. Выберите фото из галереи или продолжите без него."
        @unknown default:
            permissionMessage = "Камера сейчас недоступна. Можно продолжить без фото."
        }
    }

    #if DEBUG
    private func useDevelopmentSamplePhoto() {
        if let image = UIImage(named: "scan_test_photo") {
            selectedImageData = image.jpegDataForUpload()
            selectedSource = "simulator_sample"
            consentAccepted = true
            permissionMessage = "Пример фото выбран. Можно запустить косметический контекст."
            return
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.98, green: 0.94, blue: 0.90, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
            UIColor(red: 0.88, green: 0.95, blue: 0.38, alpha: 0.24).setFill()
            cg.fillEllipse(in: CGRect(x: 120, y: 120, width: 240, height: 240))
            UIColor(red: 0.27, green: 0.18, blue: 0.15, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 260, y: 115, width: 380, height: 510))
            UIColor(red: 0.87, green: 0.65, blue: 0.52, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 315, y: 225, width: 270, height: 380))
            cg.fill(CGRect(x: 410, y: 575, width: 80, height: 160))
            UIColor(red: 0.85, green: 0.93, blue: 0.28, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 170, y: 700, width: 560, height: 390))
            UIColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 382, y: 390, width: 24, height: 24))
            cg.fillEllipse(in: CGRect(x: 495, y: 390, width: 24, height: 24))
            UIColor(red: 0.63, green: 0.35, blue: 0.34, alpha: 1).setStroke()
            cg.setLineWidth(5)
            cg.addArc(center: CGPoint(x: 450, y: 492), radius: 48, startAngle: 0.2, endAngle: 2.8, clockwise: false)
            cg.strokePath()
        }
        selectedImageData = image.jpegDataForUpload()
        selectedSource = "simulator_sample"
        consentAccepted = true
        permissionMessage = "Пример фото выбран. Можно запустить косметический контекст."
    }
    #else
    private func useDevelopmentSamplePhoto() {}
    #endif
}

private struct BeautyScanEntryHero: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                Text("Beauty Scan")
                    .font(BeautyFont.display)
                    .foregroundStyle(BeautyColor.ink)
                Text("Фото помогает точнее подобрать текстуры, финиш и визуальный комфорт. Это косметический контекст, не медицинская диагностика.")
                    .font(BeautyFont.body)
                    .foregroundStyle(BeautyColor.taupe)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: BeautySpacing.sm) {
                BeautyScanHeroMetric(title: "Live", subtitle: "выравнивание", icon: "viewfinder")
                BeautyScanHeroMetric(title: "Private", subtitle: "по согласию", icon: "lock")
                BeautyScanHeroMetric(title: "Optional", subtitle: "можно без фото", icon: "sparkles")
            }
        }
        .padding(BeautySpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous)
                .fill(BeautyColor.card)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(BeautyColor.lime.opacity(colorScheme == .dark ? 0.18 : 0.24))
                        .frame(width: 160, height: 160)
                        .blur(radius: 34)
                        .offset(x: 46, y: -68)
                }
        }
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))
        .beautyShadow()
    }
}

private struct BeautyScanHeroMetric: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(BeautyColor.limeInk)
                .frame(width: 34, height: 34)
                .background(BeautyColor.lime.opacity(0.92), in: Circle())
            Text(title)
                .font(BeautyFont.caption.weight(.semibold))
                .foregroundStyle(BeautyColor.ink)
            Text(subtitle)
                .font(BeautyFont.caption2)
                .foregroundStyle(BeautyColor.taupe)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeautySpacing.sm)
        .background(BeautyColor.milk.opacity(0.70), in: RoundedRectangle(cornerRadius: BeautyRadius.md, style: .continuous))
    }
}

private struct BeautyScanConsentCard: View {
    @Binding var consentAccepted: Bool
    let onPrivacy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack(alignment: .top, spacing: BeautySpacing.sm) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(width: 40, height: 40)
                    .background(BeautyColor.lime.opacity(0.92), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text("Согласие на фото")
                        .font(BeautyFont.headline)
                        .foregroundStyle(BeautyColor.ink)
                    Text("Камера и галерея включаются только после вашего согласия. Без фото подбор тоже работает.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(BeautyColor.taupe)
                }
                Spacer()
                Toggle("", isOn: $consentAccepted)
                    .labelsHidden()
                    .tint(BeautyColor.lime)
            }

            Button(action: onPrivacy) {
                Label("Как Luma использует фото", systemImage: "info.circle")
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .beautyCard()
    }
}

private struct BeautyScanActionPanel: View {
    @Binding var selectedItem: PhotosPickerItem?
    let consentAccepted: Bool
    let hasSelectedPhoto: Bool
    let isBusy: Bool
    let onCamera: () -> Void
    let onSample: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: BeautySpacing.md) {
            HStack(spacing: BeautySpacing.sm) {
                Button(action: onCamera) {
                    BeautyScanSourceButton(title: "Камера", subtitle: "live scan", icon: "camera.viewfinder", isEnabled: consentAccepted)
                }
                .buttonStyle(.plain)
                .disabled(!consentAccepted)

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    BeautyScanSourceButton(title: "Галерея", subtitle: "выбрать фото", icon: "photo", isEnabled: consentAccepted)
                }
                .buttonStyle(.plain)
                .disabled(!consentAccepted)
            }

            #if DEBUG
            Button(action: onSample) {
                Label("Пример фото", systemImage: "person.crop.circle.badge.checkmark")
                    .font(BeautyFont.callout.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(BeautyColor.ink)
                    .background(BeautyColor.milk, in: Capsule())
                    .overlay(Capsule().stroke(BeautyColor.line.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Использовать пример фото")
            #endif

            PrimaryButton(title: hasSelectedPhoto ? "Использовать фото для подбора" : "Продолжить без фото", systemImage: hasSelectedPhoto ? "sparkles" : "arrow.right", isLoading: isBusy, action: onContinue)

            if !consentAccepted {
                Text("Для камеры и галереи нужно согласие. Без фото можно продолжить сразу.")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .beautyCard()
    }
}

private struct BeautyScanSourceButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isEnabled ? BeautyColor.limeInk : BeautyColor.warmGray)
                .frame(width: 44, height: 44)
                .background(isEnabled ? BeautyColor.lime : BeautyColor.line.opacity(0.25), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
                Text(subtitle)
                    .font(BeautyFont.caption2)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BeautySpacing.md)
        .background(BeautyColor.milk.opacity(isEnabled ? 1 : 0.55), in: RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(isEnabled ? BeautyColor.line.opacity(0.60) : BeautyColor.line.opacity(0.28), lineWidth: 1))
        .opacity(isEnabled ? 1 : 0.64)
    }
}

private struct BeautyScanPreviewCard: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                Text("Фото выбрано")
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                Spacer()
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(BeautyColor.ink)
                        .frame(width: 32, height: 32)
                        .background(BeautyColor.milk, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Удалить фото")
            }

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous).stroke(BeautyColor.line.opacity(0.45), lineWidth: 1))

            Text("Используем снимок только как косметический контекст для подбора.")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.taupe)
        }
        .beautyCard()
    }
}

private struct BeautyScanNotice: View {
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

private struct BeautyScanProgressCard: View {
    let statuses: [ScanStatus]
    let canCancel: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            HStack {
                ProgressView()
                    .tint(BeautyColor.lime)
                Text("Уточняю косметический контекст")
                    .font(BeautyFont.headline)
                    .foregroundStyle(BeautyColor.ink)
                Spacer()
                if canCancel {
                    Button("Отмена", action: onCancel)
                        .font(BeautyFont.caption.weight(.semibold))
                        .foregroundStyle(BeautyColor.taupe)
                }
            }
            ForEach(statuses.suffix(3)) { status in
                Label(status.label, systemImage: status.isDone ? "checkmark.circle.fill" : "circle")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
        }
        .beautyCard()
    }
}

private struct BeautyScanResultCard: View {
    let result: ScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.sm) {
            Label("Контекст обновлён", systemImage: "checkmark.seal.fill")
                .font(BeautyFont.headline)
                .foregroundStyle(BeautyColor.ink)
            Text(result.summary)
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
                .fixedSize(horizontal: false, vertical: true)
        }
        .beautyCard()
    }
}

private struct BeautyScanPrivacySheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                VStack(alignment: .leading, spacing: BeautySpacing.sm) {
                    Text("Приватность фото")
                        .font(BeautyFont.title2)
                    Text("Фото используется только после вашего согласия и только для косметического подбора. Luma не делает диагнозы и не обещает лечение.")
                        .font(BeautyFont.body)
                        .foregroundStyle(BeautyColor.taupe)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: BeautySpacing.md) {
                    Label("Можно продолжить без фото", systemImage: "arrow.right.circle")
                    Label("Снимок нужен для текстуры, финиша и визуального комфорта", systemImage: "sparkles")
                    Label("Экспорт и удаление данных доступны в настройках", systemImage: "lock")
                }
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.ink)

                Spacer()
            }
            .padding(BeautySpacing.lg)
            .background(PremiumBackground())
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
