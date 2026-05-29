import SwiftUI
import UIKit

struct BeautyScanCameraView: View {
    let onImage: (UIImage) -> Void
    var allowSkip: Bool = true
    var onSkip: () -> Void = {}
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = BeautyScanCameraController()
    @StateObject private var viewModel = BeautyScanViewModel()
    @State private var flashOpacity: Double = 0

    var body: some View {
        ZStack {
            BeautyCameraPreview(session: camera.session)
                .ignoresSafeArea()

            BeautyScanOverlayView(faceState: camera.faceState, stage: viewModel.stage)

            cameraChrome

            // Brief white flash on capture.
            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if let image = camera.capturedImage {
                BeautyScanConfirmationView(image: image, allowSkip: allowSkip) {
                    camera.resetCapture()
                    viewModel.reset()
                } onUse: {
                    onImage(image)
                    dismiss()
                } onSkip: {
                    onSkip()
                    dismiss()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task { camera.start() }
        .onDisappear { camera.stop() }
        .onReceive(camera.$faceState) { state in
            viewModel.update(faceState: state)
        }
        .onReceive(camera.$capturedImage) { image in
            if image != nil { viewModel.didCapture() }
        }
    }

    private var cameraChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: BeautySpacing.md)
            guidancePanel
        }
        .padding(.horizontal, BeautySpacing.md)
        .padding(.top, 14)
        .padding(.bottom, 26)
    }

    private var topBar: some View {
        HStack {
            Button {
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть камеру")

            Spacer()

            Text("Фото профиля")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.black.opacity(0.26), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))

            Spacer()

            // Symmetry spacer matching the close button width.
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private var guidancePanel: some View {
        VStack(spacing: BeautySpacing.md) {
            VStack(spacing: BeautySpacing.xs) {
                HStack(spacing: BeautySpacing.sm) {
                    BeautyScanLiveDot(isActive: viewModel.stage == .aligned || viewModel.stage == .capturing)
                    Text(viewModel.guidanceTitle)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.85)
                        .lineLimit(1)
                    if viewModel.stage == .aligned || viewModel.stage == .capturing {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BeautyColor.lime)
                    }
                }
                Text(viewModel.guidanceDetail)
                    .font(BeautyFont.callout)
                    .foregroundStyle(.white.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = camera.cameraError {
                cameraErrorCard(error)
            } else {
                hintChips
            }

            shutterRow
        }
        .padding(BeautySpacing.md)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var hintChips: some View {
        HStack(spacing: BeautySpacing.sm) {
            BeautyScanHintChip(icon: "face.dashed", text: "Лицо в овал")
            BeautyScanHintChip(icon: "eyeglasses", text: "Без очков")
            BeautyScanHintChip(icon: "sun.max", text: "Хороший свет")
        }
    }

    private func cameraErrorCard(_ message: String) -> some View {
        VStack(spacing: BeautySpacing.sm) {
            Text(message)
                .font(BeautyFont.callout)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Открыть настройки")
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var shutterRow: some View {
        HStack(alignment: .center, spacing: BeautySpacing.lg) {
            // Left slot: skip (optional flow only) — keeps the shutter centred.
            Group {
                if allowSkip {
                    Button {
                        onSkip()
                        dismiss()
                    } label: {
                        Text("Без фото")
                            .font(BeautyFont.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 64, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 64, height: 44)
                }
            }

            shutterButton

            // Right slot: keeps the shutter optically centred.
            Color.clear.frame(width: 64, height: 44)
        }
        .frame(maxWidth: .infinity)
    }

    private var shutterButton: some View {
        Button(action: triggerCapture) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(canTapCapture ? 0.9 : 0.4), lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(canTapCapture ? BeautyColor.lime : Color.white.opacity(0.35))
                    .frame(width: 62, height: 62)
                if camera.isCapturing || viewModel.stage == .capturing {
                    ProgressView()
                        .tint(BeautyColor.limeInk)
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(canTapCapture ? BeautyColor.limeInk : .white.opacity(0.7))
                }
            }
            .frame(width: 76, height: 76)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canTapCapture)
        .accessibilityLabel("Сделать фото")
        .accessibilityHint(canTapCapture ? "Лицо в кадре, можно фотографировать" : "Расположите лицо в овале")
    }

    private func triggerCapture() {
        guard canTapCapture else { return }
        Haptics.medium()
        withAnimation(.easeOut(duration: 0.08)) { flashOpacity = 0.75 }
        withAnimation(.easeIn(duration: 0.32).delay(0.08)) { flashOpacity = 0 }
        viewModel.startCapture()
        camera.capturePhoto()
    }

    private var canTapCapture: Bool {
        viewModel.canCapture && camera.isCameraReady && !camera.isCapturing
    }
}

private struct BeautyScanHintChip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(BeautyFont.caption2)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.82))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.1), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

private struct BeautyScanLiveDot: View {
    let isActive: Bool
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(isActive ? BeautyColor.lime : Color.white.opacity(0.55))
            .frame(width: 10, height: 10)
            .scaleEffect(isActive && pulse ? 1.22 : 1)
            .shadow(color: isActive ? BeautyColor.lime.opacity(0.34) : .clear, radius: 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

private struct BeautyScanConfirmationView: View {
    let image: UIImage
    var allowSkip: Bool = true
    let onRetake: () -> Void
    let onUse: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
            GeometryReader { proxy in
                VStack(spacing: BeautySpacing.lg) {
                    VStack(spacing: BeautySpacing.xs) {
                        Text("Проверьте снимок")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                        Text("Фото нужно для точного косметического подбора. Это не диагностика.")
                            .font(BeautyFont.callout)
                            .foregroundStyle(.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: min(420, proxy.size.height * 0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))

                    VStack(spacing: BeautySpacing.sm) {
                        Button(action: onUse) {
                            Label("Продолжить", systemImage: "checkmark")
                                .font(BeautyFont.callout.weight(.semibold))
                                .foregroundStyle(BeautyColor.limeInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(BeautyColor.lime, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: BeautySpacing.sm) {
                            Button(action: onRetake) {
                                Text("Переснять")
                                    .font(BeautyFont.callout.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(.white.opacity(0.11), in: Capsule())
                            }
                            .buttonStyle(.plain)

                            if allowSkip {
                                Button(action: onSkip) {
                                    Text("Без фото")
                                        .font(BeautyFont.callout.weight(.semibold))
                                        .foregroundStyle(.white.opacity(0.88))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 50)
                                        .background(.white.opacity(0.11), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(BeautySpacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}
