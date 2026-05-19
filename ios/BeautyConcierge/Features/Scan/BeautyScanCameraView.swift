import SwiftUI
import UIKit

struct BeautyScanCameraView: View {
    let onImage: (UIImage) -> Void
    let onSkip: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = BeautyScanCameraController()
    @StateObject private var viewModel = BeautyScanViewModel()

    var body: some View {
        ZStack {
            BeautyCameraPreview(session: camera.session)
                .ignoresSafeArea()

            BeautyScanOverlayView(faceState: camera.faceState, stage: viewModel.stage)

            cameraChrome

            if let image = camera.capturedImage {
                BeautyScanConfirmationView(image: image) {
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
            if image != nil {
                viewModel.didCapture()
            }
        }
    }

    private var cameraChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
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
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.30), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть камеру")

            Spacer()

            Text("Live Beauty Scan")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.black.opacity(0.26), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    private var guidancePanel: some View {
        VStack(spacing: BeautySpacing.md) {
            VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                HStack(spacing: BeautySpacing.sm) {
                    BeautyScanLiveDot(isActive: viewModel.stage == .aligned || viewModel.stage == .capturing)
                    Text(viewModel.guidanceTitle)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if viewModel.stage == .aligned || viewModel.stage == .capturing {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(BeautyColor.lime)
                    }
                }

                Text(viewModel.guidanceDetail)
                    .font(BeautyFont.callout)
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.12))
                        Capsule()
                            .fill(BeautyColor.lime.opacity(0.90))
                            .frame(width: max(8, proxy.size.width * viewModel.quality))
                    }
                }
                .frame(height: 5)
                .padding(.top, 4)
            }

            if let error = camera.cameraError {
                Text(error)
                    .font(BeautyFont.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: BeautySpacing.sm) {
                Button {
                    onSkip()
                    dismiss()
                } label: {
                    Text("Без фото")
                        .font(BeautyFont.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    guard viewModel.canCapture, camera.isCameraReady, !camera.isCapturing else { return }
                    Haptics.tap()
                    viewModel.startCapture()
                    camera.capturePhoto()
                } label: {
                    HStack(spacing: 8) {
                        if camera.isCapturing || viewModel.stage == .capturing {
                            ProgressView()
                                .tint(BeautyColor.limeInk)
                        } else {
                            Image(systemName: "viewfinder")
                        }
                        Text(camera.isCapturing || viewModel.stage == .capturing ? "Фиксирую" : "Зафиксировать")
                    }
                    .font(BeautyFont.callout.weight(.semibold))
                    .foregroundStyle(BeautyColor.limeInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background((canTapCapture ? BeautyColor.lime : Color.white.opacity(0.20)), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canTapCapture)
                .opacity(canTapCapture ? 1 : 0.72)
            }
        }
        .padding(BeautySpacing.md)
        .background(.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var canTapCapture: Bool {
        viewModel.canCapture && camera.isCameraReady && !camera.isCapturing
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
    let onRetake: () -> Void
    let onUse: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()
            VStack(spacing: BeautySpacing.lg) {
                VStack(alignment: .leading, spacing: BeautySpacing.xs) {
                    Text("Контекст зафиксирован")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Проверьте снимок. Он нужен только для косметического подбора.")
                        .font(BeautyFont.callout)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))

                VStack(spacing: BeautySpacing.sm) {
                    Button(action: onUse) {
                        Label("Использовать фото", systemImage: "sparkles")
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
            .padding(BeautySpacing.lg)
        }
    }
}
