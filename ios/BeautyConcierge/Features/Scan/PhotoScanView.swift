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

    var body: some View {
        ZStack {
            PremiumBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BeautySpacing.lg) {
                    SectionHeader(title: "Beauty Scan", subtitle: "Необязательный косметический контекст. Можно пропустить фото и пройти только анкету.")
                    Image("scan_guide")
                        .resizable()
                        .scaledToFill()
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.xl, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            Text("Без диагностики. Только косметический подбор.")
                                .font(BeautyFont.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(BeautySpacing.md)
                        }
                        .accessibilityHidden(true)

                    privacyConsentCard

                    if let permissionMessage {
                        ErrorBanner(message: permissionMessage)
                            .accessibilityLabel(permissionMessage)
                    }

                    if let selectedImageData, let uiImage = UIImage(data: selectedImageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 220)
                            .clipShape(RoundedRectangle(cornerRadius: BeautyRadius.lg, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button("Удалить") {
                                    self.selectedImageData = nil
                                    self.selectedSource = "questionnaire"
                                }
                                .font(BeautyFont.caption)
                                .padding(8)
                                .background(BeautyColor.milk, in: Capsule())
                                .padding(BeautySpacing.sm)
                                .accessibilityLabel("Удалить выбранное фото")
                            }
                    }

                    if appState.isBusy || !appState.scanStatuses.isEmpty {
                        statusCard
                    }

                    if let result = appState.scanResult {
                        resultCard(result)
                    }

                    actionButtons
                }
                .padding(BeautySpacing.md)
            }
        }
        .navigationTitle("Скан")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { uploadTask?.cancel() }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
                if status == .limited {
                    permissionMessage = "Доступ к фото ограничен. Используется только выбранное изображение."
                }
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    selectedSource = "library"
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCapture(sourceType: .camera) { image in
                selectedImageData = image.jpegDataForUpload()
                selectedSource = "camera"
                showingCamera = false
            } onCancel: {
                showingCamera = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showingPrivacySheet) {
            PrivacyScanSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private var privacyConsentCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                Text("Перед загрузкой фото")
                    .font(BeautyFont.headline)
                Spacer()
                Button("Приватность") { showingPrivacySheet = true }
                    .font(BeautyFont.caption.weight(.semibold))
                    .foregroundStyle(BeautyColor.ink)
            }
            Text("Фото необязательно. Luma использует его только для косметического контекста: текстура, финиш и комфорт рутины. Это не медицинский скан.")
                .font(BeautyFont.callout)
                .foregroundStyle(BeautyColor.taupe)
            Toggle("Я согласна загрузить это фото для косметического подбора", isOn: $consentAccepted)
                .toggleStyle(SwitchToggleStyle(tint: BeautyColor.lime))
                .font(BeautyFont.callout)
                .accessibilityLabel("Согласие на необязательную загрузку фото")
        }
        .beautyCard()
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            HStack {
                Text("Статус")
                    .font(BeautyFont.headline)
                Spacer()
                if uploadTask != nil && appState.isBusy {
                    Button("Отменить") {
                        uploadTask?.cancel()
                        uploadTask = nil
                    }
                    .font(BeautyFont.caption.weight(.semibold))
                    .accessibilityLabel("Отменить загрузку")
                }
            }
            ForEach(appState.scanStatuses) { status in
                HStack {
                    Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(status.isDone ? BeautyColor.success : BeautyColor.warmGray)
                    Text(status.label)
                        .font(BeautyFont.callout)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .beautyCard()
    }

    private func resultCard(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: BeautySpacing.md) {
            Text("Итог")
                .font(BeautyFont.headline)
            Text(result.summary)
                .font(BeautyFont.body)
                .foregroundStyle(BeautyColor.ink)
            ForEach(result.limitations, id: \.self) { item in
                Label(item, systemImage: "info.circle")
                    .font(BeautyFont.caption)
                    .foregroundStyle(BeautyColor.taupe)
            }
            Text(result.retentionPolicy ?? "Хранение исходного фото отключено по умолчанию.")
                .font(BeautyFont.caption)
                .foregroundStyle(BeautyColor.warmGray)
        }
        .beautyCard()
    }

    private var actionButtons: some View {
        VStack(spacing: BeautySpacing.sm) {
            HStack(spacing: BeautySpacing.sm) {
                Button {
                    requestCamera()
                } label: {
                    Label("Камера", systemImage: "camera")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BeautyColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Открыть камеру для необязательного beauty scan")

                PhotosPicker(selection: $selectedItem, matching: .images) {
                    Label("Галерея", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BeautyColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Выбрать фото из галереи")
            }

            #if DEBUG
            Button {
                useDevelopmentSamplePhoto()
            } label: {
                Label("Пример фото", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BeautyColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Использовать пример фото для симулятора")
            #endif

            PrimaryButton(title: selectedImageData == nil ? "Продолжить без фото" : "Использовать фото для подбора", systemImage: "sparkles", isLoading: appState.isBusy) {
                let data = selectedImageData
                guard data == nil || consentAccepted else {
                    permissionMessage = "Примите согласие на фото или продолжите без фото."
                    return
                }
                uploadTask = Task {
                    await appState.performScan(imageData: data, source: data == nil ? "questionnaire" : selectedSource)
                    uploadTask = nil
                }
            }
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
                    if granted { showingCamera = true }
                    else { permissionMessage = "Доступ к камере отклонён. Можно продолжить без фото или выбрать снимок из галереи." }
                }
            }
        case .denied, .restricted:
            permissionMessage = "Доступ к камере отключён. Можно продолжить без фото или выбрать снимок из галереи."
        @unknown default:
            permissionMessage = "Камера недоступна. Продолжите без фото."
        }
    }

    #if DEBUG
    private func useDevelopmentSamplePhoto() {
        if let image = UIImage(named: "scan_test_photo") {
            selectedImageData = image.jpegDataForUpload()
            selectedSource = "simulator_sample"
            consentAccepted = true
            permissionMessage = "Тестовое фото выбрано. Можно запускать скан без камеры и браузера."
            return
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200))
        let image = renderer.image { context in
            let cg = context.cgContext
            UIColor(red: 0.98, green: 0.94, blue: 0.90, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))

            UIColor(red: 0.88, green: 0.95, blue: 0.38, alpha: 0.28).setFill()
            cg.fillEllipse(in: CGRect(x: 80, y: 110, width: 260, height: 260))
            UIColor(red: 0.96, green: 0.80, blue: 0.76, alpha: 0.34).setFill()
            cg.fillEllipse(in: CGRect(x: 610, y: 260, width: 250, height: 250))

            UIColor(red: 0.27, green: 0.18, blue: 0.15, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 250, y: 115, width: 400, height: 520))
            UIColor(red: 0.87, green: 0.65, blue: 0.52, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 305, y: 220, width: 290, height: 390))
            cg.fill(CGRect(x: 410, y: 575, width: 80, height: 170))
            UIColor(red: 0.85, green: 0.93, blue: 0.28, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: 180, y: 710, width: 540, height: 390))

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
        permissionMessage = "Тестовое фото выбрано. Можно запускать скан без камеры и браузера."
    }
    #endif
}

private struct PrivacyScanSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BeautySpacing.md) {
                Text("Приватность фото")
                    .font(BeautyFont.title2)
                Text("Luma загружает необязательное фото только после согласия. Backend проверяет размер файла и MIME-тип. Хранение исходных фото выключено, пока production retention adapter явно не настроен.")
                    .font(BeautyFont.body)
                    .foregroundStyle(BeautyColor.taupe)
                Label("Без диагнозов и обещаний лечения", systemImage: "heart.text.square")
                Label("Можно продолжить без фото", systemImage: "arrow.right.circle")
                Label("Запросы на удаление и экспорт доступны в настройках", systemImage: "lock")
                Spacer()
            }
            .font(BeautyFont.callout)
            .padding(BeautySpacing.lg)
            .background(BeautyColor.ivory.ignoresSafeArea())
            .navigationTitle("Приватность")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
